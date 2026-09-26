# 物理機器インベントリ

稼働中の物理機器の構成を記録する。

## 1. 全体像

| 区分 | 機器 | 役割 |
| :-- | :-- | :-- |
| 回線終端 | シンクレイヤ SGP200W (GPON ONU, Wi-Fi 内蔵) | ONU / メインルーター (192.168.1.0/24) |
| ルーター | TP-Link Omada ER605 (ギガビット マルチ WAN VPN ルーター) | VLAN ルーター (192.168.1.201 → 192.168.5.0/24) |
| L2 スイッチ | TP-Link Omada ES220GMP (20 ポート, PoE+ 16 ポート, 250W, SFP 2) | 管理 LAN 収容 |
| L2 スイッチ | TP-Link TL-SG108S (8 ポート, アンマネージド) | SDN Fabric (10.0.0.0/24) 専用スイッチの候補 ※要確認 |
| Proxmox ノード | nuc-1 (Intel NUC 11) | 各アプリ基盤 (nuc-2 は 2026-09 に故障で退役) |
| Proxmox ノード | server-1 (自作 AM4, Ryzen 9 5900XT / 64GB) | 各アプリ基盤 |
| Proxmox ノード | server-2 (自作 AM4, Ryzen 5 5500 / 64GB / RX 7600 系 × 2) | 各アプリ基盤、GPU サーバー |
| ストレージ | TrueNAS | バックアップ、PBS |
| ラック | StarTech 4POSTRACK25U (25U 4 ポスト オープンフレーム) | 全機器の収容 |

## 2. Proxmox ノード

### 2.1 nuc-1 (Intel NUC 11)

| 項目 | 内容 |
| :-- | :-- |
| 機種 | Intel NUC 11 Pro Kit **NUC11PAHi7** (ボード NUC11PABi7, BIOS PATGL357.0047 / 2022-06-27) |
| CPU | Intel Core i7-1165G7 (4C/8T) |
| メモリ | 32GB = Lexar DDR4-3200 SO-DIMM 16GB (LD4S16G32C22ST) × 2 (スロット 2 / 最大 64GB) |
| ストレージ (起動) | Patriot P220 128GB SATA SSD (LVM `pve`) |
| ストレージ (データ) | Kingston OM8PGP41024N 1TB NVMe (QLC, DRAM レス) → ZFS `local-zfs` |
| NIC (vmbr0) | `enp89s0` = オンボード Intel I225-V 2.5GbE (igc)。リンクは 1000Mbps |
| NIC (vmbr10) | `enx6c1ff772390f` = USB 2.5GbE アダプター (Realtek RTL8156, r8152)。リンクは 1000Mbps |
| NIC (vmbr11) | `enx9c69d320e0b2` = USB 1GbE アダプター (ASIX AX88179, cdc_ncm) |
| その他 | Wi-Fi 6 AX201 / Bluetooth、Thunderbolt 4 |
| 購入 | 2024-08-05 |

### 2.2 nuc-2 (Intel NUC 11) — 故障・退役済み (server-2 へ移行)

| 項目 | 内容 |
| :-- | :-- |
| 機種 | GEEK+ Intel NUC 11 Mini PC (ベースキットは NUC11PAHi7、ASIN: [B0CF9CH9QP](https://www.amazon.co.jp/dp/B0CF9CH9QP)) |
| CPU | Intel Core i7-1165G7 (4C/8T, 最大 4.7GHz) |
| メモリ | 32GB DDR4-3200 |
| ストレージ (起動) | Patriot P220 128GB SATA SSD (LVM `pve`) |
| ストレージ (データ) | Kingston OM8PGP41024N-A0 1TB NVMe (QLC, DRAM レス) → **server-2 の M2_2 へ移植** |
| NIC (vmbr0) | `enp89s0` = オンボード Intel I225-V 2.5GbE (nuc-1 と同等) |
| NIC (vmbr10) | `enx6c1ff772646d` = USB 2.5GbE アダプター (Realtek RTL8156) → **server-2 へ移植** |
| NIC (vmbr11) | `enxc8a362104ed6` = USB 1GbE アダプター (ASIX AX88179) → **server-2 へ移植** |
| その他 | Wi-Fi 6E / Bluetooth 5.2、Thunderbolt |
| 購入 | 2024-12 (Amazon, 販売: GEEK+ Store, ASIN: B0CF9CH9QP) |
| 状態 | **2026-09-21 に電源障害（基板故障）で停止、退役**。データ用 SSD と USB NIC は server-2 へ移植し、ワークロードを退避稼働中 ([nuc-2-migration-to-server-2.md](./operations/nuc-2-migration-to-server-2.md) 参照) |

### 2.3 server-1 (自作 PC)

| 項目 | 内容 |
| :-- | :-- |
| マザーボード | MSI MPG B550 GAMING PLUS (MS-7C56, BIOS 1.I0 / 2024-07-13) |
| CPU | AMD Ryzen 9 5900XT (16C/32T) / クーラー PCCOOLER K4 |
| メモリ | 64GB = Crucial Pro DDR4 32GB (CP32G4DFRA32A) × 2。**2933MT/s で動作** (定格 3200)。4 スロット中 2 スロット使用、最大 128GB |
| ストレージ (起動) | Patriot P220 128GB SATA SSD (LVM `pve`) |
| ストレージ (データ) | Crucial T500 2TB NVMe (CT2000T500SSD8) → ZFS `local-zfs` |
| GPU | ASRock Radeon RX 550 Low Profile 4GB |
| 電源 | CORSAIR CX650 |
| NIC: オンボード | `enp42s0` = Realtek RTL8111H 1GbE → **vmbr0** (192.168.5.25) |
| NIC: 4 ポート 2.5GbE カード | Realtek RTL8125 × 4 (2025-09 購入の RTL8125B 4 ポートカード)。`enp6s0` → vmbr11 / `enp7s0` → **vmbr10 (SDN Fabric)** / `enp8s0`, `enp9s0` は未接続 |
| NIC: デュアルポート 1GbE カード | Intel PRO/1000 PT Dual Port Server Adapter (82571EB, e1000e)。`eno1` → vmbr1 (192.168.1.60) / `enp41s0f1` → vmbr999 (192.168.0.10, Omada 用) |
| Wi-Fi | Realtek RTL8852BE (AzureWave, 802.11ax)。TP-Link WiFi PCIe AX1800 |
| ケース | SilverStone 4U ラックマウント SST-RM400 |

### 2.4 server-2 (自作 PC)

| 項目 | 内容 |
| :-- | :-- |
| マザーボード | ASRock X570S PG Riptide (BIOS P5.60 / 2024-01-19) |
| CPU | AMD Ryzen 5 5500 (6C/12T) / クーラーは付属の Wraith Stealth |
| メモリ | 64GB = Crucial Pro DDR4 32GB (CP32G4DFRA32A) × 2, 3200MT/s。4 スロット中 2 スロット使用、最大 128GB |
| ストレージ (起動) | Patriot P220 128GB SATA SSD (LVM `pve`) |
| ストレージ (データ) | Crucial T500 1TB NVMe (CT1000T500SSD8) → LVM-thin `local-thinpool` |
| GPU | **Sapphire Radeon RX 7600 系 (Navi 33) × 2 枚** (同じサブシステム ID `1da2:e485`) |
| NIC: オンボード | `enp13s0` = Killer E3000 2.5GbE (Realtek) → **vmbr0** (192.168.5.26) |
| NIC: 4 ポート 2.5GbE カード | Realtek RTL8125 × 4 (`enp9s0`〜`enp12s0`)。未使用 |
| NIC (vmbr10) | `enx6c1ff772646d` = USB 2.5GbE アダプター (Realtek RTL8156)。nuc-2 から移植 |
| NIC (vmbr11) | `enxc8a362104ed6` = USB 1GbE アダプター (ASIX AX88179)。nuc-2 から移植 |
| 電源・ケース | SilverStone 4U ラックマウント SST-RM41-506 |

## 3. ストレージ

### 3.1. TrueNAS

| 項目 | 内容 |
| :-- | :-- |
| マザーボード | HKUXZR N150 NAS マザーボード (Mini-ITX, Intel N150, 10GbE × 1 + i226-V 2.5GbE × 2, SATA × 6, M.2 NVMe × 2, DDR5 SO-DIMM × 1) |
| メモリ | Samsung DDR5-4800 SO-DIMM 8GB (M425R1GB4BB0) |
| 起動ディスク | ※要確認 |
| HDD | WD Red Plus 8TB (WD80EFPX, CMR, 5400rpm) 3 台 |
| 電源 | 玄人志向 KRPW-BK550W/85+ (550W, 80 PLUS Bronze) |
| ケース | SilverStone 2U ラックマウント SST-RM23-502 |

## 4. ラック・周辺機器

| 機器 | 備考 |
| :-- | :-- |
| StarTech.com 4POSTRACK25U | 25U, 4 ポスト オープンフレーム, 奥行 59〜104cm |
| StarTech.com 棚板 CABSHELFV1U / CABSHELFV (2U) | スイッチ、NUC 等の載せ置き用 |
| SilverStone スライドレール SST-RMS06-22 | 4U ケース用 |
| QHStealthy 24 ポート ケーブル管理ダクト | |
| サンワサプライ TAP-SP2110N-2BK | 10 個口電源タップ |
| LAN ケーブル | CAT 7 / CAT 6A 等混在 |
| Raspberry Pi 5 8GB × 4 + GeeekPi クラスターケース + 27W 電源 × 4 | 現在不使用 |
| GeeekPi 19 インチ 1U ラックマウント品 | Raspberry Pi 5 用 |

UPS は未導入。
