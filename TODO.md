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
- [x] **バックアップ基盤 (PBS) の構築**
  - spec/cloud.md で要件化済みだが未構築。Proxmox Backup Server を立て、NIC1 (管理セグメント) 経由で VM/LXC の増分バックアップを取る
  - TrueNAS があるので **PBS のデータストアを TrueNAS に置く** or TrueNAS の zfs replication と役割分担を決める
- [ ] **PostgreSQL (pg-1/2/3) のバックアップ・リストア手順の整備**
  - pgBackRest / wal-g で Minio へ WAL アーカイブ + 定期フルバックアップ。リストア演習まで一度やっておく
- [x] ~~**etcd スナップショットの定期取得**~~ (実施しない)
  - 構成・思想的に、クラスター全損はリスクではない（復旧時間は必要）ため実施しない。
- [x] ~~**k8s の PV バックアップ (Velero)**~~ (実施しない)
  - クラスター内は揮発とし、永続データは外部 (NFS/Minio/PostgreSQL) に配置する方針で割り切り、実施しない。
- [ ] **障害訓練 (Chaos Day) の定例化**
  - replace-all-node.md はあるので、「ノード 1 台電源断」「lb VIP フェイルオーバー」「Argo CD 全消し → apply-apps.sh 再実行」等を年数回実施して手順の腐敗を防ぐ

## 2. CI / 自動化 (優先度: 高)

現状 GitHub Actions は `nix-images.yaml` (LXC イメージビルド) のみ。master push = 即本番同期 (prune + selfHeal) なので、push 前の検証が手薄い。

- [x] **マニフェスト検証 CI**
  - `kustomize build --enable-helm` を全 overlay に対して実行 + **kubeconform** でスキーマ検証。壊れた YAML が Argo CD に届く前に落とす
- [x] **IaC 検証 CI**
  - `tofu validate` / `terragrunt hclfmt --check` / `tflint`。state 不要な範囲だけでも価値がある
  - `nix flake check` + 各 nixosConfiguration の `build` (dry-run) を CI で回す
- [ ] **シークレット漏洩ガード**
  - pre-commit + CI で「`secrets.yaml` が SOPS 暗号化済みか (`sops_mac` の存在チェック)」を検証。gitleaks の導入も検討
- [ ] **Renovate の導入**
  - 更新対象が多層に散っている: Cilium chart version (`manifests/common/cilium/kustomization.yaml`、現在 1.15.0 でかなり古い)、Talos version (`modules/k8s-cluster/talos.tf` にハードコード)、nix flake inputs (nixpkgs 24.11)、terraform providers。Renovate はこれら全てに対応しており、PR ベースの更新フローに乗せられる
- [ ] **ApplicationSet 自体の GitOps 化 (App of Apps)**
  - 現状 `manifests/apps/*.yaml` (ApplicationSet 2 つ) は `apply-apps.sh` で手動 apply する。この層も Argo CD 自身に管理させると、ブートストラップ後の手作業がゼロに近づく

## 3. 監視・可観測性 (README TODO「監視・バックアップなど運用の効率化」の具体化)

- [ ] **アラート通知経路の整備**
  - nuage-monitoring-stack (外部リポジトリ) に Alertmanager → **ntfy** (ideas/ntfy.yaml が既にある) の経路を作り、スマホに届くようにする。Argo CD Notifications も同じ ntfy に集約すると面白い
- [ ] **クラスター外コンポーネントの監視**
  - lb (HAProxy/keepalived/CoreDNS)、pg-1/2/3、egress-gateway、Proxmox ホスト自体。NixOS 側に prometheus-node-exporter / haproxy-exporter を Nix モジュールとして足すだけなので、②層の思想と相性が良い
  - Proxmox は `pve-exporter` で VM 単位のメトリクスまで取れる
- [ ] **Hubble の有効化**
  - Cilium を使っているのに `hubble.enabled: false` はもったいない。Hubble UI で Pod 間フローが可視化でき、NetworkPolicy 導入 (後述) の前提にもなる
- [ ] **外形監視**
  - Gatus / Uptime Kuma を 1 つ立てて `*.cluster.wpc` と Cloudflare Tunnel 経由の公開 URL を監視する。クラスター障害時に監視も死ぬのを避けるため、dev-server など**クラスター外**に置くのがポイント
- [ ] **Dashboard 作成 (README TODO)**
  - Homepage / Homarr 系のポータルを `manifests/apps/` に足し、Argo CD・Grafana・Proxmox・TrueNAS へのリンクとヘルス表示を集約する

## 4. リファクタ・技術的負債の返済

- [x] **`scripts/apply-datastore.sh` の削除**
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
- [ ] **LMServer (lm-server) の再構築 + KEDA / PVE API による自律電源制御 (サーバーレス LLM)**
  - nixos-anywhere + `flake.nix#lm-server` で作り直し、モデル選定 (現在 qwen3.5:35b-a3b) と ROCm 周りの設定を見直す
  - 発展として、Ollama へのリクエストを Kubernetes KEDA やリバースプロキシで検知し、自動で Proxmox API 経由で server-2 を WoL 起動、一定時間のアイドル状態で自動サスペンド/シャットダウンするオンデマンド電源制御を構築する
- [ ] **Self-hosted GitHub Actions Runner (ARC) をクラスターに置く**
  - nix-images のビルドや CI (2 章) を自宅で回せる。Terragrunt の plan だけ CI で実行 → 結果を PR コメント、まで行くと「手動 push 型」の①層が半自動化される
- [ ] **リージョン追加 + Cilium ClusterMesh**
  - Tailscale で別拠点 (実家・VPS 等) と繋ぎ、第 2 クラスター or リモートノードを ClusterMesh で接続。EVPN over Tailscale の検証も兼ねられる
- [ ] **自宅 IoT メトリクスの取り込み (ideas/ble-metrics.yaml)**
  - BLE 温湿度計 → Prometheus → Grafana。監視スタック整備 (3 章) のついでに載せると生活に還元される
- [ ] **Argo Rollouts / Keel の使い分け整理**
  - keel が既に apps にいる。外部リポジトリ (pechka 等) のイメージ更新フローを「Keel の自動更新」から「Renovate + Git commit」に寄せると GitOps 純度が上がる — どちらの思想で行くか決める
- [ ] **Terragrunt / OpenTofu の GitOps 化 (①層の自動デプロイ)**
  - 現状はローカルから手動実行している `terragrunt apply` を、GitHub Actions (または Atlantis / Digger などのインフラ GitOps ツール) に移行する。PR 上での plan 結果確認からマージ時の自動 apply までを完結させ、インフラの完全宣言的運用を達成する
- [ ] **Minio を活用した自前 Nix バイナリキャッシュの構築 (②層の高速化)**
  - クラスター外の Minio を Nix のバイナリキャッシュサーバー (`nix-cache`) として構成する。dev-server や CI でのビルド結果を Minio にキャッシュすることで、複数ノード間での NixOS ビルド処理の重複を排除し、デプロイやイメージ生成を極限まで高速化する
- [ ] **AI-driven 自律運用 (AI Copilot Operator) の構築**
  - Slack や Matrix にローカル LLM (lm-server) バックエンドのボットを常駐させ、Kubernetes API や Prometheus へのアクセス権限（ツール呼び出し）を与える。自然言語で「最近のクラスターの調子は？」と対話できる機能に加え、Alertmanager の発報を検知した際に LLM がログやイベントを自動解析して原因分析と復旧コマンドを自動提案する半自律型自己修復基盤を PoC する
- [ ] **永続データの外部オブジェクトストレージへの自動暗号化レプリケーション**
  - クラスター内は揮発とする割り切りを補完するため、外部の永続データ (PostgreSQL WAL, Minio, NFS) について、`restic` や `rclone` を用いて外部オブジェクトストレージ (Cloudflare R2 や Backblaze B2) へ自動で暗号化バックアップする。これにより、自宅の物理災害時にもデータ損失を避ける 3-2-1 バックアップルールを確立する
- [ ] **Prometheus と物理空間の双方向連携 (Ambient IoT-Ops)**
  - 自宅 BLE 温湿度計のメトリクスや各物理ノードの温度に基づき、室温上昇時や特定ノード過熱時に VM/LXC のライブマイグレーションや Pod ドレインを実行する自律熱分散を構築する。同時に、クラスターのヘルス状態（Argo CD の同期失敗やアラート発生）に応じて部屋のスマートLED (Hue/WLED) を明滅・発色させ、インフラの状態を物理空間にアンビエントに視覚化する
- [ ] **スマートメーターと在室状況に連動する完全自律エコシステム (Eco-Ops)**
  - 在室状況（スマートロックの施錠、または自宅ルーターの Wi-Fi 接続リストからの登録端末消失）を検知した際に、開発環境や不要な K8s ノードを Proxmox API でメモリ退避（サスペンド）させる。同時に、スマートメーターから電力量や電気代の情報を取得し、電力が安い時間帯に重いジョブを自動で寄せる。これらエコチューニングの成果を Grafana でゲーム感覚でスコア化する
- [ ] **新規ミニPCを LAN に挿すだけの「ゼロタッチ物理プロビジョニング (ZTP)」**
  - ルーターの DHCP / PXE (iPXE/Matchbox) を使い、LAN に新しい PC を接続して電源を入れるだけで自動的に Talos Linux / NixOS がインストールされ、BGP ピアリングと EVPN ゾーンが自動構成されて K8s クラスターに worker ノードとして自動参加する物理自動拡張基盤を構築する
- [ ] **スマートプラグ連携による「物理カオスエンジニアリング (Physical Chaos Monkey)」**
  - 単なるポッド削除などのソフトウェアカオスを超え、スマートプラグ (Tapo等) の API と連携して物理ノードの電源を突発的かつ物理的に切断する。Talos Linux の HA や PostgreSQL のレプリケーションが自動フェイルオーバーするかを実証したのち、自動で通電してノードを復旧させる全自動物理カオス試験を構築する
- [ ] **Tailscale + ClusterMesh による「ハイブリッド・クラウドバースト」の自動化**
  - 自宅物理クラスターのリソース（特に GPU やメモリ）の枯渇を検知した際、自動的にパブリッククラウド (AWS / Hetzner 等) の安価なスポットインスタンスを Terraform でデプロイし、Cilium ClusterMesh で自宅クラスターを一時拡張して負荷を逃がす。ジョブ完了後に自動でインスタンスを破棄するクラウドバーストを自動化する
- [ ] **市販ルーターを排除した「NixOS による完全宣言的自律ルーター」の構築**
  - 現在の Omada ルーター ER605 を排除し、余剰 PC に NixOS をインストールして自作のソフトウェアルーターを仕立てる。nftables によるファイアウォール、FRR による BGP/OSPF ルーティング、DNS/DHCP をすべて Nix Flake で宣言的に記述し、ネットワークコアまで完全に GitOps 管理下におく
