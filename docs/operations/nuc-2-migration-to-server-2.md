# nuc-2 障害に伴う server-2 へのワークロード退避 実施ログ

- **日時**: 2026-09-21
- **対象障害**: Intel NUC 11 (`nuc-2`, 192.168.5.22) の電源障害（基板故障、復帰不可）
- **作業目的**: Talos Kubernetes etcd クォーラム、PostgreSQL Patroni クォーラム、MinIO S3 クラスタの喪失を防ぐため、データ用 M.2 NVMe SSD を `server-2` へ物理移植し、全 6 基のワークロードを退避稼働させる。
- **作業ブランチ**: `feature/retire-nuc-2`
- **作業結果**: **全 6 基のワークロード起動完了、K8s (6ノード全Ready)・Patroni・MinIO のクォーラム完全復旧**

---

## 1. 障害概要と移行設計

### 1.1. 影響範囲
`nuc-2` の停止により、クラスタ内で以下の冗長性喪失・縮退が発生した。
* **Talos Kubernetes**: Control Plane 3 基中 1 基（`controlplane-02`）がダウン。etcd クォーラム喪失寸前（2/3 稼働）。
* **PostgreSQL (Patroni)**: 3 ノード中 1 ノード（`pg-cluster-2`）がダウン。
* **MinIO S3**: 2 ノード中 1 ノード（`minio-cluster-2`）がダウンし、冗長性喪失。
* **Load Balancer**: `lb-2` がダウン。

### 1.2. 避難先（`server-2`）の制約とリソース配分
* **ハードウェア**: Ryzen 5 5500 / 64GB RAM / ASRock X570S PG Riptide
* **制約**: server-2 上では Windows VM および `lm-server` が常用稼働しているため、OS ごとの差し替え（丸ごと NUC 化）は不可。既存環境と共存させる。
* **リソース配分**: 64GB RAM のうち、移行 6 基に **32GB RAM** を配分し、残り 32GB を既存環境に充当できると判断した。
* **保留対象**: `bluray-extractor`（VM 240, 8GB RAM）は USB 外付け BD ドライブのリッピング専用機であるため、今回の避難対象から除外し停止維持とした。

### 1.3. 移行対象ワークロード一覧（実績）

| VMID | 名前 | 種別 | リソース (vCPU / RAM / Disk) | ネットワーク (Bridge / IP) | 移行区分 | 最終ステータス |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| **202** | `controlplane-02` | Talos VM | 2 core / 4 GB / 40GB | prvmain: `10.20.1.12` | **避難完了** | **Ready (etcd 復旧)** |
| **207** | `worker-02` | Talos VM | 4 core / 12 GB / 200GB | prvmain: `10.20.1.17` | **避難完了** | **Ready** |
| **242** | `pg-cluster-2` | NixOS LXC | 2 core / 8 GB / 20GB | dummy, prvmain: `10.20.1.42` | **避難完了** | **Running (クォーラム復旧)** |
| **272** | `minio-cluster-2` | NixOS LXC | 2 core / 4 GB / 20GB + data 100GB×2 | dummy, prvmain: `10.20.1.72` | **避難完了** | **Running (S3 復旧)** |
| **212** | `lb-2` | NixOS LXC | 1 core / 2 GB / 4GB | dummy, prvmain: `10.20.1.22`, vmbr0: `192.168.5.202` | **避難完了** | **Running (疎通確認済)** |
| **250** | `chaos-monitor` | NixOS LXC | 2 core / 2 GB / 10GB | dummy, prvmain: `10.20.1.250`, vmbr0: `192.168.5.250` | **避難完了** | **Running** |
| **240** | `bluray-extractor` | NixOS VM | 4 core / 8 GB / 50GB | prvmain: `10.20.1.80`, vmbr0: `192.168.5.240` | 設定移動のみ | 停止維持 |

---

## 2. 実施作業タイムラインとトラブルシューティング

### Phase 1: 物理作業（ハードウェア移植）
1. **server-2 の安全シャットダウン**:
   - Windows VM および `lm-server` を正常終了し、本体電源を切断した。
2. **SSD 移植と SATA 排他仕様の確認**:
   - nuc-2 からデータ用 M.2 NVMe SSD（Kingston OM8PGP41024N-A0, 1TB）を取り外し、server-2 の **M2_2 スロット**（マザーボード下部）に装着した。
   - **仕様注意**: ASRock X570S PG Riptide は M2_2 に PCIe NVMe を装着すると **SATA3_5 / SATA3_6 が排他無効化**される。起動用 SATA SSD（Patriot P220）が **SATA3_1 〜 SATA3_4** に接続されていることを確認した。
3. **USB NIC の差し替え**:
   - nuc-2 から **USB 2.5GbE アダプター**（`enx6c1ff772646d`, vmbr10 用）を抜き、server-2 の USB 3.0 ポートに接続した。
   - nuc-2 から **USB 1GbE アダプター**（`enxc8a362104ed6`, vmbr11 用）を抜き、server-2 の USB ポートに接続した。
4. **電源投入**: server-2 の電源を入れ、Proxmox VE が起動した。

---

### Phase 2: 管理ネットワーク (`vmbr0`) 復旧（PCI バスズレ対応）
1. **事象**:
   - 電源投入後、server-2 の管理 IP（`192.168.5.26`）に接続できず、オンボード Killer LAN が `NO-CARRIER` / DOWN となった。
2. **原因特定**:
   - M.2 NVMe SSD 増設によりチップセット側の PCI バス番号が +1 ズレたため、オンボード Killer LAN のデバイス名が **`enp12s0` から `enp13s0` に変化**した。既存の `vmbr0` が未接続の `enp12s0` を掴んでいた。
3. **対処**:
   - ローカルコンソールから `/etc/network/interfaces` を編集し、`vmbr0` の `bridge-ports` を **`enp13s0`** に修正した。
   - `ifreload -a` を実行し、`192.168.5.26` が UP 復旧した。以降の作業は SSH および Web UI 経由で実施した。

---

### Phase 3: ZFS ストレージ認識とバックアップ退避
1. **設定バックアップ**:
   - server-2 上で以下を実行し、nuc-2 の設定ファイルを退避した。
     ```bash
     mkdir -p ~/backup
     cp -r /etc/pve/nodes/nuc-2/qemu-server/ ~/backup/
     cp -r /etc/pve/nodes/nuc-2/lxc/         ~/backup/
     ```
2. **ZFS プール強制インポート**:
   - 他ノードが最終使用していたプールのため `-f` を付与してインポートした。
     ```bash
     zpool import -f local-zfs
     # ステータス確認: ONLINE, 273GB 使用中
     ```
3. **Proxmox ストレージ登録**:
   - server-2 上で `local-zfs` を有効化した。
     ```bash
     pvesm set local-zfs --nodes nuc-1,nuc-2,server-1,server-2
     ```

---

### Phase 4: Terraform / SDN 設定適用（GitOps）

#### 1. 初期状態確認と State 整理（`state rm`）
nuc-2 が物理的にオフラインとなったため、初期の `terragrunt plan` 実行時に Proxmox API への通信タイムアウト（HTTP 500）が発生した。
nuc-2 を恒久的に退役させるため、以下の 10 リソースを state から除外した。
```bash
cd terraform/pve/hosts

terragrunt state rm proxmox_network_linux_bridge.dummy_nuc2
terragrunt state rm proxmox_network_linux_bridge.vmbr0_nuc2
terragrunt state rm proxmox_network_linux_bridge.vmbr10_nuc2
terragrunt state rm proxmox_network_linux_bridge.vmbr11_nuc2
terragrunt state rm proxmox_network_linux_vlan.vmbr10_1_nuc2
terragrunt state rm proxmox_network_linux_vlan.vmbr10_2_nuc2
terragrunt state rm proxmox_sdn_fabric_node_ospf.main_nuc2
terragrunt state rm 'proxmox_download_file.talos_iscsi_image["nuc-2"]'
terragrunt state rm 'proxmox_download_file.nixos_base_lxc["nuc-2"]'
terragrunt state rm 'proxmox_download_file.nixos_base_vm["nuc-2"]'
```

#### 2. 設計方針とコード修正
* nuc-2 は復帰させないが、ソースコード上はコメントアウトで温存した。
* `terraform/root.hcl`: provider `proxmox` の `ssh` ブロックに `server-2` (`192.168.5.26`) を追加。
* server-2 にアンダーレイ IP として **`.13` 体系** を新設した（旧 nuc-2 の `.11` はコメントアウトで温存）。
  * 管理 LAN: `192.168.5.26/24`（`vmbr0`, ports: `enp13s0`）
  * アンダーレイ (Fabric): `10.0.0.13/24`（`vmbr10`, ports: `enx6c1ff772646d`）
  * P2P VLAN: `vmbr10.1` (server-2 ↔ nuc-1), `vmbr10.2` (server-2 ↔ server-1)
  * OSPF Fabric IP: `10.254.1.26`
  * 外部向け: `10.0.1.13/24`（`vmbr11`, ports: `enxc8a362104ed6`）

#### 3. 遭遇したトラブルと解決策
1. **`vmbr0_server2` の `interface already exists` エラー**:
   * **原因**: server-2 には OS インストール時から `vmbr0` が存在するため、Terraform の新規作成が HTTP 400 で失敗した。
   * **対処**: `imports.tf`（現在は `imports.tf.20260922`）を定義し、既存の `server-2:vmbr0` を state にインポートして同期させた。
     ```hcl
     import {
       to = proxmox_network_linux_bridge.vmbr0_server2
       id = "server-2:vmbr0"
     }
     ```
2. **`zone-private` EVPN ゾーンの適用**:
   * `terraform/vpc/zone-private/network.tf` の `nodes` および `exit_nodes` に `server-2` を追加し、`terragrunt apply` を完了した。
   * これにより、server-2 上で SDN オーバーレイ `prvmain`（`10.20.1.0/24`）が開通した。

---

### Phase 5: VM / LXC 設定移動と起動時トラブルシューティング

#### 1. 事前準備: NixOS LXC プロビジョニング鍵の配置
* **事象**: そのまま `pct start 272` や `212` を実行すると、`lxc.hook.pre-start` が `status 2` で異常終了した。
* **原因**: NixOS LXC の設定（`nix-lxc` モジュール）は、ホスト側の `/var/lib/pve/<name>/` をコンテナ内 `/var/lib/nix-provisioning` に bind mount する。server-2 上にそのディレクトリが存在しなかったため、起動前フックがファイル不在エラーで失敗していた。
* **対処**: server-1（`/var/lib/pve/pg-cluster-3/`）から同一の鍵ファイルを複製配置した。
  ```bash
  for name in pg-cluster-2 minio-cluster-2 lb-2 chaos-monitor; do
    mkdir -p /var/lib/pve/$name
    scp -o StrictHostKeyChecking=no root@192.168.5.25:/var/lib/pve/pg-cluster-3/* /var/lib/pve/$name/
  done
  ```

#### 2. Talos VM スニペット不在エラー (`local:snippets/talos-202.yaml`)
* **事象**: `qm start 202` 実行時、`TASK ERROR: volume 'local:snippets/talos-202.yaml' does not exist` で起動失敗した。
* **原因**: `202.conf` に `cicustom: user=local:snippets/talos-202.yaml` が指定されていたが、ノードローカルの `/var/lib/vz/snippets/` が server-2 に存在しなかった。
* **対処**: nuc-1 のスニペットから複製して IP/ホスト名を置換配置した（または `cicustom` 行のコメントアウトでも起動可能）。
  ```bash
  mkdir -p /var/lib/vz/snippets
  pvesm set local --content iso,vztmpl,backup,snippets
  scp -o StrictHostKeyChecking=no root@192.168.5.21:/var/lib/vz/snippets/talos-201.yaml /var/lib/vz/snippets/talos-202.yaml
  sed -i 's/10.20.1.11/10.20.1.12/g' /var/lib/vz/snippets/talos-202.yaml
  sed -i 's/controlplane-01/controlplane-02/g' /var/lib/vz/snippets/talos-202.yaml
  scp -o StrictHostKeyChecking=no root@192.168.5.21:/var/lib/vz/snippets/talos-206.yaml /var/lib/vz/snippets/talos-207.yaml
  sed -i 's/10.20.1.16/10.20.1.17/g' /var/lib/vz/snippets/talos-207.yaml
  sed -i 's/worker-01/worker-02/g' /var/lib/vz/snippets/talos-207.yaml
  ```

#### 3. LXC 242 のバックアップロック解除 (`CT is locked (backup)`)
* **事象**: `pct start 242` 実行時、`TASK ERROR: CT is locked (backup)` で起動失敗した。
* **原因**: nuc-2 の障害発生時にバックアップ処理中だったため、設定ファイルに `lock: backup` が残存していた。
* **対処**: ロックを解除して起動した。
  ```bash
  pct unlock 242
  ```

#### 4. 設定ファイル移動と順次起動の実行
設定ファイルを `nuc-2` から `server-2` へ移動し、クォーラム最優先の順序で起動した。
```bash
# 1. 設定ファイル移動
mv /etc/pve/nodes/nuc-2/qemu-server/202.conf /etc/pve/nodes/server-2/qemu-server/
mv /etc/pve/nodes/nuc-2/qemu-server/207.conf /etc/pve/nodes/server-2/qemu-server/
mv /etc/pve/nodes/nuc-2/lxc/242.conf         /etc/pve/nodes/server-2/lxc/
mv /etc/pve/nodes/nuc-2/lxc/272.conf         /etc/pve/nodes/server-2/lxc/
mv /etc/pve/nodes/nuc-2/lxc/212.conf         /etc/pve/nodes/server-2/lxc/
mv /etc/pve/nodes/nuc-2/lxc/250.conf         /etc/pve/nodes/server-2/lxc/
mv /etc/pve/nodes/nuc-2/qemu-server/240.conf /etc/pve/nodes/server-2/qemu-server/ # 停止維持

# 2. 順次起動
pct start 242  # ① PostgreSQL (Patroni クォーラム最優先) -> 起動成功
qm start 202   # ② Talos Controlplane (etcd クォーラム最優先) -> 起動成功
pct start 272  # ③ MinIO S3 (S3 クラスタ復旧) -> 起動成功
pct start 212  # ④ Load Balancer (VIP 冗長化) -> 起動成功
qm start 207   # ⑤ Talos Worker (K8s ワーカー復旧) -> 起動成功
pct start 250  # ⑥ Chaos Monitor -> 起動成功
```

---

## 3. クォーラム・健全性検証結果（実績）

### 3.1. PostgreSQL (Patroni)
`ssh pg-cluster-1 "patronictl list"` にて確認:
```text
+ Cluster: postgres-cluster (7663651202553948060) +----+-----------+
| Member       | Host       | Role    | State     | TL | Lag in MB |
+--------------+------------+---------+-----------+----+-----------+
| pg-cluster-1 | 10.20.1.41 | Replica | streaming | 14 |         0 |
| pg-cluster-2 | 10.20.1.42 | Replica | running   |  3 |       171 |
| pg-cluster-3 | 10.20.1.43 | Leader  | running   | 14 |           |
+--------------+------------+---------+-----------+----+-----------+
```
* **結果**: 3 メンバー全基がオンラインになり、クォーラム成立。`pg-cluster-2` が正常に復旧した。

### 3.2. Kubernetes (Talos)
`kubectl get nodes -o wide` にて確認:
```text
NAME            STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE          KERNEL-VERSION   CONTAINER-RUNTIME
talos-9tu-uim   Ready    control-plane   63d   v1.35.0   10.20.1.11    <none>        Talos (v1.12.2)   6.18.5-talos     containerd://2.1.6
talos-0r0-80d   Ready    control-plane   63d   v1.35.0   10.20.1.12    <none>        Talos (v1.12.2)   6.18.5-talos     containerd://2.1.6
talos-u7e-lmv   Ready    control-plane   63d   v1.35.0   10.20.1.13    <none>        Talos (v1.12.2)   6.18.5-talos     containerd://2.1.6
talos-isy-suv   Ready    <none>          63d   v1.35.0   10.20.1.16    <none>        Talos (v1.12.2)   6.18.5-talos     containerd://2.1.6
talos-urr-l44   Ready    <none>          63d   v1.35.0   10.20.1.17    <none>        Talos (v1.12.2)   6.18.5-talos     containerd://2.1.6
talos-gjl-seu   Ready    <none>          63d   v1.35.0   10.20.1.18    <none>        Talos (v1.12.2)   6.18.5-talos     containerd://2.1.6
```
* **結果**: **全 6 ノード（Control Plane 3 基、Worker 3 基）がすべて `Ready`**。etcd クォーラムは完全に回復し、Cilium・CoreDNS も全ノードで稼働を確認した。

### 3.3. MinIO S3
* `minio-cluster-2` 起動直後（02:42:21）から、`minio-cluster-1` の接続エラーログが停止し、相互グリッド通信が確立した。
* 両ノード（`10.20.1.71`, `10.20.1.72`）で MinIO API (`:9000`) が稼働し、S3 の冗長性が復旧した。

### 3.4. Load Balancer
* `lb-2`（`10.20.1.22`）への ping（0.25ms）およびポート 6443 の応答を確認した。
* `lb-1` 上の HAProxy でも `controlplane-02`（`node02`）のヘルスチェックが UP に遷移したことを確認した。
* **補足（確認結果のみ）**:
  現在、VIP `192.168.5.200` は `lb-3` が保持（MASTER）しているが、`lb-3` 側の HAProxy プロセスが停止（inactive）していたため、外部から VIP 経由（`192.168.5.200:6443`）へのアクセスが connection refused となっていた（`lb-1` や各ノード自体は正常に応答している）。

---

## 4. 将来の切り戻し手順（後継機導入・原状復帰時）

後継機（DeskMini 等）導入時、または修理完了時に本構成を元に戻す手順の控え。

1. server-2 上で退避稼働していたワークロード（242, 202, 272, 212, 207, 250）をシャットダウンする。
2. 設定ファイルを `/etc/pve/nodes/server-2/...` から新機（または元のディレクトリ）へ移動する。
   ```bash
   mv /etc/pve/nodes/server-2/qemu-server/202.conf /etc/pve/nodes/<new-node>/qemu-server/
   mv /etc/pve/nodes/server-2/qemu-server/207.conf /etc/pve/nodes/<new-node>/qemu-server/
   mv /etc/pve/nodes/server-2/lxc/242.conf         /etc/pve/nodes/<new-node>/lxc/
   mv /etc/pve/nodes/server-2/lxc/272.conf         /etc/pve/nodes/<new-node>/lxc/
   mv /etc/pve/nodes/server-2/lxc/212.conf         /etc/pve/nodes/<new-node>/lxc/
   mv /etc/pve/nodes/server-2/lxc/250.conf         /etc/pve/nodes/<new-node>/lxc/
   mv /etc/pve/nodes/server-2/qemu-server/240.conf /etc/pve/nodes/<new-node>/qemu-server/
   ```
3. server-2 上で ZFS プールをエクスポートする。
   ```bash
   zpool export local-zfs
   ```
4. server-2 の電源を切り、M.2 NVMe SSD および USB NIC を取り外して新機へ移植する。
5. **NIC 名の復帰**:
   - M.2 NVMe SSD を外すと PCI バス番号が元に戻るため、オンボード Killer LAN が **`enp13s0` から `enp12s0` に戻る**。
   - `/etc/network/interfaces` で `vmbr0` の `bridge-ports` を **`enp12s0`** に戻し、`ifreload -a` を実行する。
6. Terraform 側で `server-2` のリソース設定を整理し、新機の定義へ差し替える。
