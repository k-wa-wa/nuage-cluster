# 物理配線

ルーター・スイッチのポートごとの接続先を記録する。設定の正は Omada Controller (`192.168.5.163:8043`) である。

- ルーター ↔ スイッチは両方の表に書き、終端の機器はスイッチ側にだけ書く (NIC の詳細は [hardware-inventory.md](./hardware-inventory.md))
- ケーブルの両端にスイッチ側のポート名 (例: `ES-05`) を貼り、配線を変えたら表とラベルを一緒に直す

## ネットワーク

| 名前 | 出所 | VLAN | サブネット | 用途 |
| :-- | :-- | :-- | :-- | :-- |
| - | ONU/メインルーター (192.168.1.1) | - | 192.168.1.0/24 | ER605 の WAN、server-1 vmbr1 (`.60`) |
| network-management | ER605 | 1 | 192.168.0.0/24 | Omada の機器管理 |
| oc1-proxmox | ER605 | 5 | 192.168.5.0/24 | vmbr0 (Proxmox 管理) |
| oc1-prod | ER605 | 1000 | 10.0.1.0/24 | vmbr11 (インターネット出口) |

## ER605 (192.168.0.1)

| Port | 接続先             | ネットワーク                          |
| :---- | :--------------- | :------------------------------- |
| 1    | Nuroルーター        | WAN                             |
| 2    | -               | 未使用                             |
| 3    | -               | 未使用                             |
| 4    | TL-SG108S Port2 | VLAN1 untagged                  |
| 5    | ES220GMP Port1  | VLAN1 untagged / 5, 1000 tagged |

## ES220GMP (192.168.0.100)

| Port | プロファイル | 接続先 |
| :-- | :-- | :-- |
| 1 | All | ER605 Port5 |
| 2 | network-management | - |
| 3 | Disable | - |
| 4 | Disable | - |
| 5 | oc1-proxmox | - |
| 6 | oc1-proxmox | server-1 `enp42s0` (vmbr0) |
| 7 | oc1-proxmox | nuc-1 `enp89s0` (vmbr0) |
| 8 | oc1-proxmox | TrueNAS (192.168.5.30) |
| 9 | oc1-proxmox | - |
| 10 | oc1-proxmox | server-2 `enp13s0` (vmbr0) |
| 11 | oc1-proxmox | Windows PC |
| 12 | oc1-proxmox | MacBook Pro |
| 13 | oc1-prod | - |
| 14 | oc1-prod | server-1 `enp6s0` (vmbr11) |
| 15 | oc1-prod | nuc-1 `enx9c69d320e0b2` (vmbr11) |
| 16 | oc1-prod | server-2 `enp10s0` (vmbr11) |
| 17 | 要確認 | - |
| 18 | 要確認 | - |
| 19 | 要確認 | - |
| 20 | 要確認 | - |

## TL-SG108S (Omada 管理用)

| Port | 接続先 |
| :-- | :-- |
| 1 | server-1 `enp41s0f1` (vmbr999) |
| 2 | ER605 Port4 |

## TL-SG105S (SDN Fabric)

| Port | 接続先 |
| :-- | :-- |
| 1 | 要確認 |
| 2 | 要確認 |
| 3 | 要確認 |
