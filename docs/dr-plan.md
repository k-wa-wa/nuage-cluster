# DR (災害復旧) とバックアップの計画

自宅の環境が丸ごと失われても、データを失わず、主なサービスを別の場所で動かせるようにする。あわせて、本番が乗っ取られてもバックアップを消されない「安全なバックアップ環境」にする。

本書は設計の方針と進め方を定める。各段階の実装は、段階ごとに仕様を確かめてから別の PR で行う。

## 1. 目的

### What

- 一次側の NAS を TrueNAS から NixOS に移し、管理を Nix に統一する
- 隔地 (別の拠点) に x86 の小型 NAS (`dr-nas`) を置き、一次側の NAS から pull で複製する
- 隔地の Raspberry Pi で、主なサービスを Git から作り直して常に動かしておく。コンテナはアクセスがあったときに起動する
- 拠点間は Tailscale で結び、届く範囲を最小にする

### Why

- 今はすべての機器が同じラックにあり、UPS も無い。火災・落雷・盗難・浸水で、本番とバックアップを同時に失う
- 本番 (GitHub・bot・atelier のエージェントを含む) が乗っ取られたとき、今の構成ではバックアップも消せてしまう
- TrueNAS は手作業の管理が残っており、Terraform・Nix・Argo CD でそろえた他の層から浮いている

## 2. 現状

| 項目 | 状態 |
| :-- | :-- |
| 置き場所 | PVE 3 台 (nuc-1 / server-1 / server-2)・TrueNAS・スイッチがすべて同じラックにある。UPS は無い |
| TrueNAS | N150 / 8GB / WD Red Plus 8TB × 3 / M.2 NVMe スロット × 2 (`192.168.5.30`)。pool `pool-1` は暗号化していない (`terraform/truenas/main.tf`) |
| PBS | TrueNAS 上のコンテナ (`dockurr/proxmox-backup:latest`)。パスワード `root` を平文で書いている (`terraform/truenas/main.tf`) |
| VM / LXC のバックアップ | PBS へ毎日。7 日・4 週・12 か月分を残す (`terraform/vpc/modules/nix-lxc/main.tf`) |
| PostgreSQL | `archive_command = "true"` で WAL を取っていない (`nix/hosts/postgres-cluster/patroni.nix`)。LXC ごと PBS に取っているだけで、ある時点まで戻す復元はできない |
| SeaweedFS | 3 台の中で複製している (`-defaultReplication=001`)。LXC ごと PBS に取っているだけで、オブジェクトとしての控えは無い |
| k8s | クラスタの中は揮発とし、永続データはクラスタの外に置く方針である (`TODO.md`) |
| 構成 | すべて Git (GitHub, public) にある。シークレットは SOPS + Age で、管理者の鍵・紙に控えたマスター鍵・各ホストの SSH ホスト鍵などで開く (9 章) |
| Terraform の state | 手元のマシンにしか無い |
| Tailscale | 既存の subnet router が `192.168.5.0/24` を広報している。ACL の中身は未確認 |
| 余っている機器 | Raspberry Pi 5 8GB × 4、GeeekPi のクラスターケース、1U ラックマウント |

## 3. 想定する災害と守る範囲

| 想定 | 今の対策 | 本計画での対策 |
| :-- | :-- | :-- |
| ノード 1 台の故障 | PVE 3 台と、各クラスタの quorum | 変えない |
| NAS の故障 | なし | 隔地の dr-nas に複製がある |
| 自宅が丸ごと失われる | なし | 隔地の dr-nas にデータがあり、隔地の Pi クラスタで作り直す |
| 本番・GitHub・bot の乗っ取り、ランサムウェア | なし | dr-nas は pull 型で、受けるのは計算用の Pi からの NFS だけである。更新は nuage-dr の master からだけ入り、master に入れられるのは k-wa-wa だけである。本番の側からは消せない |
| 操作の誤り (誤削除・GitOps の prune) | PBS の世代 | 加えて、dr-nas 側のスナップショットを dr-nas 側の決まりだけで残す |
| 隔地での機器の盗難 | — | 鍵の置き方による (未決。9 章) |

守るデータは、次の 3 つに分けて考える。

| 種類 | 中身 | 戻し先 |
| :-- | :-- | :-- |
| 構成 | Git (GitHub) と Age 鍵 | どこでも作り直せる。自宅を失っても GitHub に残る |
| データ | PostgreSQL・S3 のオブジェクト・NFS のファイル・メディア | ファイルとして持ち運べる形で取り、どこでも戻せるようにする |
| VM / LXC のイメージ | PBS | x86 の Proxmox にだけ戻せる。Pi には戻せない |

Pi の上での DR は「Git から作り直し、データだけを戻す」形とする。PBS のイメージは、自宅の Proxmox を作り直すときに使う。

## 4. 全体構成

```
自宅                                                   隔地 (最初の設置のあとは物理的に触らない)
┌──────────────────────────────────┐                 ┌─────────────────────────────────────┐
│ PVE 3 台 (本番)                    │                 │ dr-nas (x86 2 ベイ機, NixOS)          │
│   pg / swfs / k8s / atelier ...   │                 │   syncoid で pull (raw send)        │
│        │ pgBackRest・S3 の写し     │                 │   sanoid で世代を管理                 │
│        ▼                          │   Tailscale      │   NFS は tailscale0 で pi-1〜3 へ    │
│ nas (TrueNAS の機械に NixOS)       │ ◀── 22/tcp ───── │   更新は nuage-dr の master          │
│   ZFS / NFS / PBS (コンテナ)       │ dr-nas→nas のみ  │                                     │
│   sanoid                          │                 │ pi-1〜3 (Pi 5, NixOS + k3s)          │
│   更新は master + autoUpgrade      │                 │   常時稼働。コンテナはアクセスで起動   │
└──────────────────────────────────┘                 └─────────────────────────────────────┘
```

一次側の `nas` と二次側の `dr-nas` は、同じ NixOS モジュール (nuage-dr の `nixosModules.nas`) を source と replica の役で使う。

### リポジトリと更新の経路

隔地の機器 (dr-nas と計算用の Pi 3 台) の構成と、共有する NAS モジュールは、nuage-cluster とは別のリポジトリ `nuage-dr` に置く。一次側の `nas` は本番なので nuage-cluster に置き、NAS モジュールを flake input として読む。

| 項目 | 方針 |
| :-- | :-- |
| 分ける理由 | 隔地の機器に効く変更だけを見て通せるようにする。`flake.lock` (nixos-raspberrypi・aarch64) を本番と分ける。更新の経路が本番と違う。自宅を失っても nuage-dr だけで作り直せる |
| 依存の向き | nuage-cluster が nuage-dr を input にする。逆にはしない。bot が push できる nuage-cluster を、バックアップの信頼の根元に入れないためである |
| 隔地の機器の更新 | nuage-dr の master を `system.autoUpgrade` で取り込む |
| master の保護 | ルールセットで PR を必須にし、CI (`check` と `build-dr-nas`。x86 の `nix flake check` と dr-nas のビルド) を必須のチェックにする。計算用の Pi を作るときに、arm64 のビルドを足す。master を更新できるのは素通し (bypass) の権限を持つ k-wa-wa だけで、それも PR のマージのときに限る (`bypass_mode = "pull_request"`)。k-wa-wa も master へ直接 push できない。CI は bot には強制で、k-wa-wa はマージのときに明示すれば素通しできる (壊れた CI を直す PR を通すため)。force push と削除を禁じる。bot は write までとし、admin にしない。bot は素通しの権限を持たないので、PR をマージできない |
| 入力の更新の警告 | `flake.lock` やキャッシュの設定 (`nixConfig`) を変える PR では、CI が警告と比較のリンクを出す。nixos-raspberrypi は個人の方が保守する flake なので、差分を見てからマージする |

署名タグ (`git verify-tag` で確かめてから取り込む形) は後で足す。今の形で守れる範囲は次のとおりである。

| 乗っ取られるもの | master の保護 (今) | 署名タグを足したとき |
| :-- | :-- | :-- |
| bot・atelier のエージェント | 守れる | 守れる |
| GitHub Actions の token | 守れる (ルールセットで push を拒む) | 守れる |
| k-wa-wa の GitHub アカウント | 守れない (保護を外せる) | 守れる |
| GitHub そのもの | 守れない | 守れる |

守れない場合は、悪い設定が dr-nas に入り、dr-nas 側のスナップショットまで消される。署名を足すときに取り込みの処理だけを差し替えられるよう、取り込みは 1 か所にまとめておく。

## 5. 一次側の NAS (TrueNAS → NixOS)

TrueNAS の機械に NixOS を直接入れ、今の ZFS pool をそのまま import する。TrueNAS の pool は通常の OpenZFS なので、データの移し替えは要らない。

| 項目 | 方針 |
| :-- | :-- |
| OS | NixOS を直接入れる。dr-nas と同じく raw イメージ (nixpkgs の `system.build.images.raw-efi`) を作り、Mac から USB の NVMe ケース越しに新しい NVMe へ `dd` で焼いて挿す。データのディスクには触れない |
| 更新 | 他の NixOS ホストと同じく、master への push と `system.autoUpgrade` |
| ディスク | 今の HDD のまま使う。SSD は高騰しており、移行の間も今の pool を唯一のコピーとして触らずに済むためである。SSD に替えるかは、dr-nas に控えができてから考え直す |
| ZFS | 今の `pool-1` を import する。パス (`/mnt/pool-1/...`) は今と同じにする |
| PBS | NixOS の上でコンテナ (`virtualisation.oci-containers`) として動かす。データストアのパスを変えないので、PVE のストレージ定義 (`truenas-pbs`) はそのまま使える。イメージのタグを固定し、パスワードは SOPS から渡す |
| NFS | NixOS の設定で export を書く |
| スナップショット | sanoid で取る |
| pull の受け口 | dr-nas 専用のユーザーを作り、`zfs allow` で `send,hold` だけを渡す。destroy の権限は渡さない |
| 暗号化 | 暗号化した dataset を新しく作り、ローカルで `zfs send \| zfs recv` して移す。raw send のために必要である。空き容量が要る |

### 移行の安全策

移行の時点では、まだ隔地に控えが無い。TrueNAS の中身が唯一のコピーなので、必ず戻せる形で進める。

- NixOS は空いている M.2 スロットの新しい SSD に入れる。TrueNAS の起動ディスクには手を付けない。戻すときは TrueNAS で起動し直し、pool を import する
- 最初は `zpool import -o readonly=on` で import し、中身を確かめてから読み書きで import する
- NixOS 側で `zpool upgrade` をしない。feature flag を上げると TrueNAS に戻せなくなる
- 事前に TrueNAS で `zpool get all pool-1 | grep feature@` を見て、使っている ZFS の機能を確かめる。ZFS 2.3 の機能を使っていれば、今の nixpkgs 24.11 (ZFS 2.2) では import できない。nixpkgs の更新を先に済ませる
- `terraform/truenas` は、移行が終わるまで今の構成の記録として残す。扱いは移行のあとで決める

## 6. 二次側の NAS (隔地の dr-nas)

焼いたイメージで動き、ログインしないアプライアンスとする。

| 項目 | 方針 |
| :-- | :-- |
| ハードウェア | x86 の 2 ベイの小型機 (N100・N150 など。例: UGREEN DXP2800) に、4TB の HDD を 2 台挿して mirror にする。起動用に小容量の NVMe を 1 枚挿す。Raspberry Pi 5 + PCIe の SATA HAT は使わない。電源の不足、カーネルの更新でディスクが見えなくなる、HAT が固まって電源の入れ直しが要る、という報告があり、触らない隔地には向かないためである。USB 接続の HDD も、接続のリセットで pool が落ちやすいので使わない |
| OS | NixOS の raw イメージ (nixpkgs の `system.build.images.raw-efi`) を atelier で作り、Mac から USB の NVMe ケース越しに起動用の NVMe へ `dd` で焼く。手順は nuage-dr の `docs/dr-nas-setup.md` にある。OS は状態を持たず、壊れたら前の世代に戻す。データは別ディスクの pool に置く |
| 複製 | syncoid で一次側から pull する。暗号化した dataset を raw send で受ける。PBS の dataset もそのまま複製する。PBS は立てない。受ける通信を NFS だけにするためである。自宅の Proxmox を作り直すときだけ、x86 の機械で一時的に起動して読む |
| 世代 | sanoid で管理する。世代の決まりは dr-nas 側にだけ置く |
| 待ち受け | SSH は無効にする。受けるのは計算用の Pi からの NFS (tailscale0、NFSv4 の 2049/tcp) だけとし、Tailscale の ACL で絞る。NFS を出す前の段階は `tailscale up --shields-up` で、受ける通信をすべて拒否する |
| 更新 | nuage-dr の master を `system.autoUpgrade` で取り込む (4 章の「リポジトリと更新の経路」)。署名タグは後で足す |
| pool | 宣言で作らない。最初の 1 回だけ、手順書のとおり手で `zpool create` する。NixOS は import するだけにし、データのディスクに Nix が触れないようにする |
| 秘密 | syncoid の SSH 鍵などは、Nix の store に入れずにファイルのパスで受け取る。ファイルが無ければユニットがエラーで止まる |
| 失敗したときの戻し | 更新のあと一定時間内に Tailscale と heartbeat が戻らなければ、前の世代に自動で戻す。ハードウェアの watchdog で、固まったら再起動させる (機種で使えるかを確かめる。11 章) |
| 監視 | dr-nas から本番の側へ、最後に取れたスナップショットの時刻と pool の状態を送る (heartbeat)。本番から dr-nas へ向かう経路は開けない |
| 停電 | 通電で自動起動するよう BIOS で設定する (機種で設定できるかを確かめる。11 章) |
| 隔地の LAN | 他の人の端末もつながる、こちらでは管理しない網である。何も公開しない。NFS は tailscale0 にだけ bind する |

### DR 環境へのデータの出し方 (常時)

DR 環境は常に動かしておく。切り替えのフラグは置かない。

```
起動時:  zfs load-key → 最新のスナップショットから clone を作る (複製の本体は書き換えない)
         → clone を NFS で出す (tailscale0 のみ)
平時:    syncoid の pull が新しいスナップショットを持ってきたら、clone を作り直す
         ただし clone に書き込みがあれば (`written` が 0 でなければ) 作り直さず、heartbeat で知らせる
自宅を失ったあと: 新しいスナップショットが来ないので、clone はそのまま使われ続ける
```

- clone に書くので、複製の本体は無傷で残る。復旧のあと (failback) にも、差分の送り直しが崩れない
- clone に書き込みがあるときに作り直さないのは、DR の間に書いた分を、自宅が戻って複製が再開したときに消さないためである。人が確かめてから、捨てるか failback する。余計な書き込みで止まらないよう、clone は `atime=off` にする
- clone の元のスナップショットは消せない。作り直すときは、古い clone を消してから sanoid に古い世代を消させる
- 鍵を常に読み込んでも、盗難への強さはほぼ変わらない。鍵のファイルは元から dr-nas にあるためである。変わるのは、動いている dr-nas が乗っ取られたときに中身を読まれることである。鍵を dr-nas の外に移すとき (11 章) は、アクセスがあったときに読み込む形にする

## 7. DR 用の計算 (隔地の Pi クラスタ)

| 項目 | 方針 |
| :-- | :-- |
| 台数 | Pi 5 8GB × 3 (計 24GB)。残る 1 台は自宅に予備として置く |
| 置き場所 | 隔地。自宅を失ったときに動かすため、dr-nas と同じ場所に置く |
| OS | NixOS + k3s を仮置きする。既存の `nix/` の資産を使い回せる。Talos が Pi 5 に対応しているかは要確認 |
| 平時 | 常に動かす。k3s と Argo CD は常に動かし、DR 用の構成を同期しておく。アプリのコンテナは 0 台にしておき、アクセスがあったら起動する (scale to zero。仕組みは 11 章) |
| 動かすもの | 主なアプリに絞る。lm-server (GPU)・bluray-extractor は対象外。対象の一覧は別途決める |
| データ | dr-nas の clone を NFS で使う。PostgreSQL は pgBackRest のリポジトリから戻す。戻すのに時間がかかるので、すぐ起動する形は 11 章で決める |

### DR で作り直すための前提

- **データを持ち運べる形で取る。** PostgreSQL は pgBackRest (または wal-g) で、WAL と定期のフルバックアップを一次側の NAS の dataset へ取る。S3 (SeaweedFS) のオブジェクトは rclone などで、一次側の NAS の dataset へ写す
- **コンテナイメージを arm64 でも動くようにする。** pechka などのイメージを multi-arch でビルドする (nuage-workspace の共通 workflow を直す)
- **DR 用の構成を Git に置く。** 対象のアプリだけを同期する overlay と、NFS・PostgreSQL の向き先を DR 用にした設定

## 8. ネットワーク (Tailscale)

- 自宅の LXC・VM に 1 台ずつ Tailscale を入れることはしない。今の subnet router のままとする
- Tailscale を直接入れるのは、隔地の機器 (dr-nas と計算用の Pi) だけとする
- Tailnet Lock を有効にし、Tailscale の運営側から知らない端末を足されることを防ぐ。隔地の機器を焼くときの auth key は、前もって署名しておく
- auth key は 1 台に 1 本とし、1 回だけ使える (reusable でない) key にする。dr-nas に `tag:dr-nas` の 1 本、pi-1〜3 に `tag:pi-k8s` の 3 本を作る。期限は焼く作業に要る分だけ (例: 1 日) にし、使われなかった key もすぐ切れるようにする
- ACL は既定で拒否し、次の 3 行だけを許す

```jsonc
"grants": [
  { "src": ["autogroup:member"], "dst": ["*"], "ip": ["*"] },              // 自分の端末は全部へ
  { "src": ["tag:dr-nas"], "dst": ["192.168.5.30/32"], "ip": ["tcp:22"] }, // dr-nas は一次側の NAS の SSH だけ
  { "src": ["tag:pi-k8s"], "dst": ["tag:dr-nas"], "ip": ["tcp:2049"] }     // 計算用の Pi は dr-nas の NFS だけ
]
```

- 隔地の機器は他の人の端末もつながる LAN にあり、自分以外の人も物理的に触れる。乗っ取られても、自宅の LAN へは、dr-nas から NAS の SSH にしか届かないようにする。計算用の Pi は自宅の LAN へ届かない
- Tailnet Lock は、すでに入っている端末が乗っ取られた場合を防げない。この場合は、dr-nas が受けるのを計算用の Pi からの NFS だけにしていることと、pull 用のユーザーの権限 (`send,hold` のみ) で守る
- subnet router を通った通信は、送り元が subnet router の IP に書き換わる (SNAT)。そのため NAS の側では接続元を見分けられず、絞り込みは Tailscale の ACL に頼る

## 9. 鍵の整理

家の中の鍵は 2026-11-01〜03 に整理した。外で効く秘密と、以前 `lb_key` で暗号化していた値の作り直しが残っている。
鍵の扱いのやり方は `.agents/skills/sops-secrets/` と、各スクリプト (`scripts/gen-host-keys.sh`・`scripts/gen-login-key.sh`・`scripts/gen-atelier-agent-key.sh`) の冒頭に書いてある。

### 方針 (2026-11-01 に決めた)

- **家の中だけで効く秘密は、Git に置く。** Tailscale で守られているものとして、SOPS で暗号化して public のリポジトリに置く。SSH の鍵も含め、置けるものは置く。
- **外で効く秘密は、基本は置かない。** fine-grained の token のように権限を絞れるものだけを置く。
- **鍵は分ける。** ホスト鍵はホストごと、ログイン用の鍵は接続元ごとにする。1 つが漏れても、ほかに広がらないようにする。
- **漏れたかもしれない値は、暗号化し直すだけでなく値そのものを作り直す。**
- **SOPS は、変える値だけを書き換える** (`sops set` / `sops unset`)。全体を暗号化し直すと、変えていない値の暗号文まで変わり、差分が読めなくなる。

### 鍵の今の形

| 鍵 | 置き場所 | 開けるもの・入れる先 |
| :-- | :-- | :-- |
| 管理者の鍵 (日々使う) | Mac の `~/.config/sops/age/keys.txt` | すべての SOPS のファイル |
| マスター鍵 | 紙 2 部。Mac にも、AI が触れる場所にも置かない | すべての SOPS のファイル (3 リポジトリの 14 ファイル)。管理者の鍵を失ったときの最後の手段 |
| Argo CD の鍵 | Mac の `~/.config/sops/age/argocd-keys.txt` と、k8s の Secret (`docs/secrets-management.md`) | k8s 用のファイル |
| 各ホストの SSH ホスト鍵 | 秘密鍵は `terraform/pve/hosts-secrets/host-keys.yaml` (管理者の鍵とマスター鍵だけで開く)。公開鍵は `.ssh/known_hosts` | そのホストの `nix/hosts/<host>/secrets.yaml`。sops-nix が `ssh-to-age` で Age 鍵として使う |
| ログイン用の鍵 | `.ssh/login-keys.yaml` (`nixos`・`pve-root`・`omada`)。Mac は `.ssh/keys/` にも置く | `nixos` は全 NixOS ホスト、`pve-root` は Proxmox 3 台の root、`omada` は Omada のコントローラー |
| atelier の `agent` の鍵 | `nix/hosts/atelier/secrets.yaml` (atelier 自身のホスト鍵で開く) | 全 NixOS ホストの `agent` ユーザー (atelier からだけ) |

- **ホスト鍵は前もって作り、作り直しても同じ鍵で戻る。** LXC には `terraform/pve/hosts-secrets` が Proxmox の `/var/lib/pve/<host>/` に置いて mount する。VM (bluray-extractor・atelier・lm-server) には cloud-config で渡す。
- **ssh は、リポジトリの `.ssh/known_hosts` で接続先を確かめる** (`.ssh/ssh_config` の `StrictHostKeyChecking yes`)。Proxmox の 3 台も対象である。

### 済んだこと

| 日付 | 中身 | PR |
| :-- | :-- | :-- |
| 2026-11-01 | マスター鍵を作り、すべての SOPS のファイルの受信者に足した。管理者の鍵は日々使う鍵に格下げした | #67 |
| 2026-11-01 | ホストごとの鍵にした。すべての LXC が共有していた `lb_key` を `.sops.yaml` と Terraform から外した (Proxmox などに残った写しは #102) | #68・#69・#71・#72 |
| 2026-11-01 | Mac から NixOS に入る鍵を作り直し、base イメージに焼く鍵も替えた | #73〜#76 |
| 2026-11-01 | Proxmox の root に入る鍵 (`pve-root`) と Omada に入る鍵 (`omada`) を作り直した。古い `.ssh/id_rsa` はどこにも入れない | #78 |
| 2026-11-01 | atelier の `agent` の鍵を SOPS に入れ、atelier と lm-server のホスト鍵も固定した | #80・#81・#82 |
| 2026-11-03 | ssh で接続先のホスト鍵を確かめるようにした | #88 |
| 2026-11-03 | keepalived の VRRP のパスワードを、VIP を動かさずに作り直した (`docs/operations/2026-11-03-keepalived-password-rotation.md`) | #92・#103 |

### 残っていること

- **以前 `lb_key` で暗号化していた値の作り直しと、`lb_key` の写しの削除。** git の履歴の古い暗号文は `lb_key` があれば読める。#97〜#102 に分けてある。
- **外で効く秘密を作り直し、権限を絞る。**
  - GitHub の token (`terraform/secrets.yaml`、`scripts/secrets.yaml`。後者は Argo CD の鍵でも開ける)
  - Cloudflare の API token (`terraform/secrets.yaml`、`terraform/cloudflare/secrets.yaml`、cert-manager)
  - LLM の API key (litellm、pechka の `OPENAI_API_KEY`)
  - 絞れないものを置く場所は未決である (11 章)。
- **平文の秘密。** PBS のパスワード `root` (`terraform/truenas/main.tf`)。Terraform の state には復号した値が平文で残り、その state が手元のマシンにしか無い。
- **信頼の根元が 1 つにまとまっている。** 本番の更新は master への push だけで入り、bot も push できる。バックアップ先の更新を同じ経路に載せると、GitHub か bot が乗っ取られたときにバックアップまで消せてしまう。nuage-dr の master の保護 (4 章) で分ける。
- **ドキュメントの書き直し。** `docs/secrets-management.md` と `docs/setup.md` に、古いやり方 (`lb_key` など) が残っている。

### あるべき姿

| 区分 | 例 | 置き場所 |
| :-- | :-- | :-- |
| 家の中だけで効くもの | DB・S3・keepalived・ZFS の dataset の鍵・syncoid の SSH 鍵・k3s の token・ログイン用の SSH 鍵 | SOPS (Git) |
| 外で効くもの | GitHub・Cloudflare・LLM の token | 権限を最小に絞る。絞れたものは SOPS に置いてよい。絞れないものは SOPS に置かない (置き場所は 11 章)。どこに何が要るかの一覧は Git に置く |
| SOPS を守るもの | 管理者の鍵・マスター鍵 | 管理者の鍵は Mac、マスター鍵は紙 2 部 (済み) |
| 更新の信頼の根元 | nuage-dr の master に入れられる k-wa-wa の GitHub アカウント (後でタグの署名鍵)、Tailnet Lock の鍵とその解除用の secret | 端末の中 (置き場所は 11 章)。SOPS にも bot にも持たせない |

- Age 鍵が漏れても、データを読めるだけで、隔地のバックアップは消せない。消すには、k-wa-wa の GitHub アカウントが要る (署名タグを足したあとは、別に持っている署名の鍵が要る)。
- 隔地の機器に要る秘密は、焼くときにシークレット用パーティション (Pi は SD、dr-nas は起動用の NVMe の ESP) へ書き込む。Nix の store とイメージファイルには秘密を入れない。

## 10. 進め方

| # | 段階 | 中身 | 人の手が要る所 |
| :-- | :-- | :-- | :-- |
| 1 | 鍵の整理 | 9 章のあるべき姿にする。家の中の鍵は済んだ。残りは 9 章の「残っていること」 | SOPS の操作、token の作り直し |
| 1' | Tailscale (1 と並べて進める) | ACL を 8 章の形にし、Tailnet Lock をかける | 管理画面の操作 |
| 2 | 一次側の NAS を NixOS に移す | nixpkgs の更新 → NAS 用のモジュール → 新しい SSD に導入 → 読むだけで import して確かめる → 本番として切り替える → 暗号化した dataset へ移す | 機械への導入、`terragrunt apply` |
| 3 | データを持ち運べる形にする | pgBackRest と S3 の写しを一次側の NAS へ | — |
| 4 | dr-nas を用意する | 自宅で組んで試してから隔地に置く | 焼く、設置する |
| 5 | DR 用の計算と演習 | 計算用の Pi 3 台を用意し、arm64 のイメージと DR 用の構成を作り、アクセスで起動する仕組みを入れて通しの演習をする | 演習 |
| 6 | 運用 | バックアップの鮮度の監視 (chaos-monitor)、定期の演習 | — |

## 11. 未決事項

| 項目 | 仮置き | 備考 |
| :-- | :-- | :-- |
| dr-nas に ZFS の鍵をどう置くか | 常に dr-nas に置き、起動時に読み込む | 盗難も防ぐなら、dr-nas の外に置き、アクセスがあったときにスマホから Tailscale 越しに送る案がある |
| scale to zero の仕組み | 未決 | Sablier (k3s の Traefik の plugin)・KEDA の HTTP add-on・Knative から、Pi の 24GB に収まるものを選ぶ |
| PostgreSQL をすぐ起動する形 | 未決 | pgBackRest のリポジトリから WAL を当て続ける待機系を常に動かす案 (コンテナを落とす方針の例外になる) と、定期に restore しておく案がある |
| DR 環境への入り口 | 未決 | DR 用のホスト名を別に持つか、同じホスト名を自宅が落ちたときに切り替えるか |
| 最初の設置 | 未決 | 自分で持っていくか、組んで焼いた状態で送るか |
| PBS を残すか | NixOS の上でコンテナとして残す | やめてデータ単位のバックアップだけにする案もある |
| DR で動かすアプリ | 未決 | 24GB に収まる範囲で決める |
| 計算用の Pi の OS | NixOS + k3s | Talos の Pi 5 対応は要確認 |
| TrueNAS の中身と使用量 | 未確認 | 版、`zpool list` と `zfs list`、PBS 以外の共有、起動ディスク。dr-nas のディスクの容量と、暗号化への移行に要る空きが決まる |
| メディアを複製の対象にするか | 選んだものだけ | 全部含めると dr-nas のディスクの容量に効く |
| Tailscale の現状 | 未確認 | subnet router がどの機器で動いているか、ACL が allow-all のままか |
| 外で効く秘密の置き場所 | 未決 | 1Password は使っていない。権限を絞れない token と、Tailnet Lock の鍵・GitHub アカウントの回復用の情報をどこに置くかを決める |
| 署名タグ | 入れない。nuage-dr の master の保護で守る | k-wa-wa の GitHub アカウントや GitHub が乗っ取られた場合も守るなら足す (4 章) |
| dr-nas の機種 | x86 の 2 ベイ機 (例: UGREEN DXP2800) に 4TB の HDD × 2 の mirror | 通電で自動起動する設定、ハードウェアの watchdog、NixOS で起動できるか (メーカーの OS 向けの watchdog を BIOS で切れるか) を確かめて選ぶ。ディスクの by-id は届いてから書く |
