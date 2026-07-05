# TODO / 改善アイディア集

現状の実装とドキュメントを俯瞰した上での、改善候補・実験アイディアの一覧。
本リポジトリの思想を前提とする:

- **3 層 IaC** (Terragrunt+OpenTofu → Nix Flake → Argo CD) で全構成を Git 起点に管理する
- **Ansible を排除**し、宣言的なツールに寄せる
- **シークレットは SOPS + Age で全て Git 管理**し、人間が守る鍵は管理者 Age 鍵 1 つに集約する
- 将来的には **spec/cloud.md のマルチテナント環境**(Zone 単位のテナント分離)へ発展させる

---

## 0. 過去のアーキテクチャ変更に伴う ADR

完了・クローズした検討事項と、その結論の記録。

| 検討事項 | 結論 |
| :-- | :-- |
| Ingress or Ngrok 等の検討 | **Cilium Ingress** で実装 |
| Argo CD の導入 | 導入済み (ApplicationSet + Kustomize + SOPS プラグイン) |
| kube-vip による HA Cluster 化 | 一旦実装したものの、**外部 HAProxy によるロードバランス**に変更 |
| AZ を追加して VPN で繋ぐ | 実施済み |
| Ansible のコンテナ実行・リファクタ | **Terraform + Nix により Ansible を排除**する方針とし、クローズ |
| DB の外出し (VM 化) or Operator 使用 | **NFS / Minio / PostgreSQL のみ外出し**。他は一時 DB としてクラスター内に作成する方針 |

---

## 1. 信頼性・データ保護 (優先度: 高)

- [ ] **Terraform state のリモートバックエンド化**
  - 現状はローカル `terraform.tfstate` のため、実行マシンの喪失 = state の喪失となる (operations.md 7 章)
  - クラスター外で稼働している **Minio (S3 互換) を backend に使う**のが構成的に自然。ただし「Minio 自体を作る terraform」だけはローカル state に残す、という鶏卵の切り分けが必要
  - 併せて OpenTofu の **state encryption** 機能を試すのも面白い (Age/PBKDF2 でクライアントサイド暗号化できる)
- [ ] **バックアップ基盤 (PBS) の構築**
  - spec/cloud.md で要件化済みだが未構築。Proxmox Backup Server を立て、NIC1 (管理セグメント) 経由で VM/LXC の増分バックアップを取る
  - TrueNAS があるので **PBS のデータストアを TrueNAS に置く** or TrueNAS の zfs replication と役割分担を決める
- [ ] **oc1-nfs のデータバックアップ**
  - `protection = true` で誤削除は防げるが、データ本体のバックアップが無い (operations.md 注意点)。PBS か zfs send/recv で外部にコピーする
- [ ] **PostgreSQL (pg-1/2/3) のバックアップ・リストア手順の整備**
  - pgBackRest / wal-g で Minio へ WAL アーカイブ + 定期フルバックアップ。リストア演習まで一度やっておく
- [ ] **etcd スナップショットの定期取得**
  - `talosctl etcd snapshot` を定期実行して Minio へ退避する。クラスター全損時の復旧手段になる
- [ ] **k8s の PV バックアップ (Velero)**
  - local-path-provisioner の hostPath データはノード障害で消える。Velero + Minio で PVC スナップショットを取るか、「クラスター内は揮発・永続データは外部 (NFS/Minio/PG)」の方針を明文化して割り切る
- [ ] **障害訓練 (Chaos Day) の定例化**
  - replace-all-node.md はあるので、「ノード 1 台電源断」「lb VIP フェイルオーバー」「Argo CD 全消し → apply-apps.sh 再実行」等を年数回実施して手順の腐敗を防ぐ

## 2. CI / 自動化 (優先度: 高)

現状 GitHub Actions は `nix-images.yaml` (LXC イメージビルド) のみ。master push = 即本番同期 (prune + selfHeal) なので、push 前の検証が手薄い。

- [ ] **マニフェスト検証 CI**
  - `kustomize build --enable-helm` を全 overlay に対して実行 + **kubeconform** でスキーマ検証。壊れた YAML が Argo CD に届く前に落とす
- [ ] **IaC 検証 CI**
  - `tofu validate` / `terragrunt hclfmt --check` / `tflint`。state 不要な範囲だけでも価値がある
  - `nix flake check` + 各 nixosConfiguration の `build` (dry-run) を CI で回す
- [ ] **シークレット漏洩ガード**
  - pre-commit + CI で「`secrets.yaml` が SOPS 暗号化済みか (`sops_mac` の存在チェック)」を検証。gitleaks の導入も検討
- [ ] **Renovate の導入**
  - 更新対象が多層に散っている: Cilium chart version (`manifests/common/cilium/kustomization.yaml`、現在 1.15.0 でかなり古い)、Talos version (`modules/k8s-cluster/talos.tf` にハードコード)、nix flake inputs (nixpkgs 24.11)、terraform providers。Renovate はこれら全てに対応しており、PR ベースの更新フローに乗せられる
- [ ] **ApplicationSet 自体の GitOps 化 (App of Apps)**
  - 現状 `manifests/apps/*.yaml` (ApplicationSet 2 つ) は `apply-apps.sh` で手動 apply する。この層も Argo CD 自身に管理させると、ブートストラップ後の手作業がゼロに近づく
- [ ] **apply-apps.sh の冪等化**
  - `kubectl create secret` は 2 回目の実行で失敗する。`--dry-run=client -o yaml | kubectl apply -f -` 形式に直し、スクリプト全体を何度でも実行可能にする

## 3. 監視・可観測性 (README TODO「監視・バックアップなど運用の効率化」の具体化)

- [ ] **アラート通知経路の整備**
  - nuage-monitoring-stack (外部リポジトリ) に Alertmanager → **ntfy** (ideas/ntfy.yaml が既にある) の経路を作り、スマホに届くようにする。Argo CD Notifications も同じ ntfy に集約すると面白い
- [ ] **クラスター外コンポーネントの監視**
  - lb (HAProxy/keepalived/CoreDNS)、pg-1/2/3、nfs-proxy、Proxmox ホスト自体。NixOS 側に prometheus-node-exporter / haproxy-exporter を Nix モジュールとして足すだけなので、②層の思想と相性が良い
  - Proxmox は `pve-exporter` で VM 単位のメトリクスまで取れる
- [ ] **Hubble の有効化**
  - Cilium を使っているのに `hubble.enabled: false` はもったいない。Hubble UI で Pod 間フローが可視化でき、NetworkPolicy 導入 (後述) の前提にもなる
- [ ] **外形監視**
  - Gatus / Uptime Kuma を 1 つ立てて `*.cluster.wpc` と Cloudflare Tunnel 経由の公開 URL を監視する。クラスター障害時に監視も死ぬのを避けるため、dev-server など**クラスター外**に置くのがポイント
- [ ] **Dashboard 作成 (README TODO)**
  - Homepage / Homarr 系のポータルを `manifests/apps/` に足し、Argo CD・Grafana・Proxmox・TrueNAS へのリンクとヘルス表示を集約する

## 4. リファクタ・技術的負債の返済

- [ ] **`scripts/apply-datastore.sh` の削除**
  - 参照先 (`terraform/environments/dev-persistent`, `playbooks/postgres.yml`) が現存しない旧構成向け (operations.md 7 章)。混乱の元なので消す
- [ ] **`playbooks/` の完全撤去**
  - 残っているのは data-store (NFS/Minio) と omada-controller。「Ansible 排除」の思想を完遂するには、NFS/Minio を TrueNAS or NixOS VM へ、Omada Controller を LXC (Nix or 公式コンテナ) へ移行する。README の取り消し線 TODO 2 件がこれで完全クローズできる
- [ ] **nix/flake.nix の重複排除**
  - lb-1/2/3 がほぼ同一定義の 3 連コピー。`map` / `genAttrs` で `mkLb = name: ...` に畳む。ホストが増えたときの雛形にもなる
- [ ] **nixpkgs 24.11 のアップグレード**
  - 24.11 は EOL 済みのはず。25.x へ上げ、sops-nix のコミット固定も release ブランチ追従に変える
- [ ] **Longhorn の残骸整理 or 導入判断**
  - talos.tf に `/var/lib/longhorn` の extraMount・iscsi-tools 拡張・データ用空ディスク (scsi1) が仕込み済みだが、実際は local-path-provisioner を使用中。**Longhorn を導入する**か、**残骸を消して local-path に一本化する**かを決める (中途半端が一番良くない)
- [ ] **ドキュメントと実装の乖離修正**
  - secrets-management.md は Secret 名を `argocd-sops-key` と書くが、apply-apps.sh が作るのは `sops-age-key`。どちらかに統一する
  - spec/network_design.md の IPAM 設計 (10.101.x 系 / SDN Overlay 10.0.1.0/24) と実装 (prvmain 10.20.1.0/24 / vmbr10 10.0.0.0/24) がズレている。spec を「将来の理想形」として残すなら、その旨と現状とのマッピングを冒頭に書く
- [ ] **EVPN Controller の手動設定の扱い**
  - Terraform 管理外 (GUI 手動) が唯一の「Git に無い構成」。bpg/proxmox provider が対応するまでの間、最低限 `pvesh` コマンド or 設定値スナップショットを setup.md に残して再現可能にする
- [ ] **setup.md の「TODO: 手順再作成」の解消**
  - ゼロからの再構築手順が途切れている。1 章から通しで再構築演習をやり、そのログで埋めるのが確実

## 5. セキュリティ強化

- [ ] **Age マスターキーの冗長化**
  - 「人間が守る鍵は 1 つ」の思想は美しいが、単一障害点でもある。`.sops.yaml` に **バックアップ用の第 2 受信者** (金庫保管のオフライン鍵 or age-plugin-yubikey) を追加しておくと、思想を崩さず耐障害性が上がる
- [ ] **NetworkPolicy の導入**
  - せっかく Cilium なので CiliumNetworkPolicy でアプリ間通信を絞る。Hubble (3 章) でフローを観測 → ポリシー生成、の流れが実践的
- [ ] **Argo CD の RBAC / SSO**
  - 現状の認証構成を確認し、Cloudflare Zero Trust 側と役割を整理する。admin パスワード運用なら Dex + GitHub OAuth 等へ
- [ ] **Talos の KubeSpan / Pod Security 標準の適用検討**
  - namespace への PSS ラベル付与を bootstrap/namespaces.yaml に足すだけでベースラインが上がる
- [ ] **Proxmox ホストファイアウォールの Default Drop**
  - spec/cloud.md 5.1 の要件だが、実装状況が Git から読み取れない。terraform/pve/hosts で管理下に置く

## 6. マルチテナント構想 (spec/cloud.md) の前進

- [ ] **Shared Services Zone の実体化**
  - 現状 PG/NFS/Minio は zone: private 内や旧セグメントに同居。spec 通り `zone-shared` を切って移設すると、テナント追加時に共有サービスへの経路設計が綺麗になる
- [ ] **BGP EVPN Route Leaking (フェーズ 2) の検証**
  - Hub & Spoke を飛ばして VRF Leaking を先に PoC する価値あり。zone-waai が既にあるので、waai ↔ shared 間で試せる
- [ ] **内部 DNS 基盤 (Technitium 等) の導入**
  - 現状 lb 上の CoreDNS がゾーン 1 つ分をハードコード。テナントごとの `*.<tenant>.lab.internal` を払い出すなら、API で管理できる Technitium / PowerDNS への置き換えが効く
- [ ] **テナント払い出しの Terraform モジュール化**
  - `module "tenant"` 一発で EVPN Zone + VNet + Exit Node + Cloudflare Tunnel + DNS レコードまで出来る形にする。「パブリッククラウドに準ずる環境」の思想が最も体現される部分

## 7. 面白い実験・試してみたいこと

- [ ] **Cilium BGP Control Plane で lb 層を薄くする**
  - 既にアンダーレイが BGP EVPN なので、Cilium の BGP Control Plane + LB-IPAM で Service type=LoadBalancer の VIP を直接広報できる可能性がある。成功すれば HAProxy の NodePort 中継が不要になり、lb LXC は API サーバー用に縮退できる。kube-vip → 外部 HAProxy と変遷してきた歴史の次の一手として面白い
- [ ] **LMServer (lm-server) の再構築 + Wake-on-LAN 自動化**
  - まず再構築: nixos-anywhere + `flake.nix#lm-server` で作り直し、モデル選定 (現在 qwen3.5:35b-a3b) と ROCm 周りの設定を見直す
  - 発展として「Ollama へのリクエストを検知 → WoL マジックパケットで server-2 起動 → 起動後にプロキシ」する仕組み (n8n や小さな Go デーモン)。アイドル時間で自動シャットダウンまでやると"サーバーレス LLM"ごっこができる
- [ ] **exo による分散 LLM 推論 (ideas/exo が既にある)**
  - nuc-1/2 + server-1/2 の GPU/CPU を束ねて 1 モデルを動かす実験。おうちクラスターならではのネタ
- [ ] **Cluster API Provider Proxmox (ideas/cluster-api-for-proxmox)**
  - 現在の Terraform 直管理と対極の「k8s から k8s クラスターを生やす」方式。マルチテナントで「テナントごとに k8s クラスターを払い出す」未来があるなら PoC する価値あり
- [ ] **KubeVirt (ideas/kubevirt)**
  - 逆に「k8s の中に VM を生やす」方向。PVE との棲み分け整理も含めて一度触ると設計判断の材料になる
- [ ] **Self-hosted GitHub Actions Runner (ARC) をクラスターに置く**
  - nix-images のビルドや CI (2 章) を自宅で回せる。Terragrunt の plan だけ CI で実行 → 結果を PR コメント、まで行くと「手動 push 型」の①層が半自動化される
- [ ] **リージョン追加 + Cilium ClusterMesh (README TODO「リージョンを追加して VPN で繋ぐ」)**
  - Tailscale で別拠点 (実家・VPS 等) と繋ぎ、第 2 クラスター or リモートノードを ClusterMesh で接続。EVPN over Tailscale の検証も兼ねられる
- [ ] **PVE on PVE の常設検証環境**
  - server-1 に vmbr10 (PVE on PVE 用) が既にある。SDN や Talos アップグレードを本番に当てる前に流す「ステージング」をネスト仮想化で作る
- [ ] **自宅 IoT メトリクスの取り込み (ideas/ble-metrics.yaml)**
  - BLE 温湿度計 → Prometheus → Grafana。監視スタック整備 (3 章) のついでに載せると生活に還元される
- [ ] **Argo Rollouts / Keel の使い分け整理**
  - keel が既に apps にいる。外部リポジトリ (pechka 等) のイメージ更新フローを「Keel の自動更新」から「Renovate + Git commit」に寄せると GitOps 純度が上がる — どちらの思想で行くか決める

---

## 優先順位の私見

1. **1 章 (state リモート化・バックアップ)** — 「壊れたら Git から再現できる」思想の最後の穴が state とデータ本体
2. **2 章 (CI)** — master push = 即本番、の構成は検証 CI が入って初めて安心して回せる
3. **3 章 (監視・通知)** — README TODO の中で日々の体験改善が最も大きい
4. 4〜5 章は随時、6〜7 章は楽しみながら
