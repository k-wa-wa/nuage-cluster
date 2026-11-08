# ネットワーク詳細設計 (Detailed Network Design)

## 1. デザイン方針 (Design Principles)

*   **Proxmox SDN Native First:** 可能な限り Proxmox SDN (BGP EVPN Controller) の標準機能を活用し、外部VM等への依存を減らす。
*   **Simple Naming:** ゾーン名やIDは予測可能で管理しやすい体系とする。
*   **Private IP Scope:** RFC1918 (プライベートアドレス) を効率的に利用し、CIDRの衝突を防ぐ。

## 2. ASN (Autonomous System Number) 設計

EVPN構成において、各ノードやゾーンに割り当てるAS番号の設計。
プライベートAS範囲 (`64512` - `65534`) を使用する。

| 役割 | ASN範囲 | 割り当てルール | 備考 |
| :--- | :--- | :--- | :--- |
| **Spine / RR** | `65000` | 固定 | 全ノードがiBGPピアリングする際の共通ASN (Route Reflector)。 |
| **Leaf (Nodes)** | `65001` - `65009` | ノードID毎 | 各Proxmoxノード固有のASN (eBGP構成の場合)。今回はiBGP構成(同ASN)を想定？ |
| **Zone (VRF)** | `65100` - `65199` | ゾーンID毎 | 各Zone (VRF) に割り当てるASN。 |

**推奨構成 (iBGP Full Mesh / RR):**
*   Local AS: `65000` (全ノード共通)
*   Controller: `bgp-evpn-controller`

## 3. ID設計 (VNI / VLAN)

VXLAN Network Identifier (VNI) および VLAN ID の割り当てルール。

| 種別 | ID範囲 | 用途 | 備考 |
| :--- | :--- | :--- | :--- |
| **VNI (User)** | `10000` - `19999` | ユーザー用VNet | `100` + `UserID(2桁)` + `SubnetID(2桁)` |
| **VNI (Shared)** | `20000` - `20999` | 共有サービス用 | `200` + ServiceID |
| **VNI (System)** | `30000` - `39999` | 管理・検証用 | |

## 4. IPアドレス設計 (IPAM)

内部ネットワークには `10.0.0.0/8` (Class A Private) を使用し、ゾーンごとに `/16` を割り当てる。

### 4.1 Zone IP割り当て

| Zone Name | CIDR (IPv4) | 用途 | 備考 |
| :--- | :--- | :--- | :--- |
| **`zone-mgmt`** | `10.0.0.0/16` | 管理基盤 | Proxmox Host, PBS, DNS, Infra VM |
| **`zone-shared`** | `10.10.0.0/16` | 共通サービス | MinIO, Postgres, Auth, Monitoring |
| **`zone-user-01`** | `10.101.0.0/16` | ユーザー01 | テナント1 (例: User A) |
| **`zone-user-02`** | `10.102.0.0/16` | ユーザー02 | テナント2 (例: User B) |
| ... | ... | ... | (`10.{100+ID}.0.0/16`) |

### 4.2 Services Subnet (詳細例)

**`zone-shared` (10.10.0.0/16)**
*   `10.10.1.0/24`: Core Services (DNS, LDAP/Auth)
*   `10.10.2.0/24`: Database (Postgres)
*   `10.10.3.0/24`: Storage (MinIO)
*   `10.10.254.0/24`: Gateway / Exit Interconnect (もし必要なら)

## 5. 出口設計 (Exit Nodes & NAT)

Proxmox SDN EVPN Zone の `Exit Nodes` 機能を使用する。

*   **Exit Node:** 特定のProxmoxノード (例: `pve-01`, `pve-02`) をExit Nodeとして指定。
*   **SNAT:** `Enable SNAT` を有効化し、各VNetからのOutbound通信をExit Nodeの主IP (NIC3) でマスカレードしてインターネットへ抜ける。
*   **Default Gateway:** 各ZoneのVNet作成時に `Gateway` (例: `10.101.0.1`) を設定し、VMのデフォルトゲートウェイとする。

## 6. Proxmox SDN設定値 (Configuration)

### 6.1 EVPN Zone設定
*   **ID:** `zone-{name}` (e.g., `zone-user-01`)
*   **VRF VXLAN Tag:** 自動割り当て (または `100`〜`255` で管理)
*   **Controller:** `bgp-evpn`
*   **Exit Nodes:** `pve-01` (Primary), `pve-02` (Secondary)
*   **Advertise Subnets:** Yes

### 6.2 VNet設定
*   **ID:** `vnet-{id}` (e.g., `vnet-10101`)
*   **Zone:** `zone-user-01`
*   **Tag:** `10101` (VNIに相当)
*   **Subnet:** `10.101.1.0/24`
*   **Gateway:** `10.101.1.1`
*   **SNAT:** Checked (Zone設定に従う)

## 7. 物理ノードIP割り当て (Physical Nodes)

各Proxmoxノードに固定IPを割り当てる。
SDN Fabric (NIC 2) は `10.0.0.0/24`、インターネット出口 (NIC 3) は `10.0.1.0/24` を使用する。Proxmox ホストの default gateway は NIC 3 側の `10.0.1.1` であり、SDN の SNAT もここから抜ける。

| ノード名 | (NIC 1) 管理 `vmbr0` | (NIC 2) SDN Fabric `vmbr10` | (NIC 3) Exit/Internet `vmbr11` |
| :--- | :--- | :--- | :--- |
| **nuc-1** | `192.168.5.21` | `10.0.0.10` (fabric: `10.254.1.21`) | `10.0.1.10` |
| **dm-1** | `192.168.5.23` | `10.0.0.14` (fabric: `10.254.1.23`) | `10.0.1.14` |
| **server-1** | `192.168.5.25` | `10.0.0.12` (fabric: `10.254.1.25`) | `10.0.1.12` |
| **server-2** | `192.168.5.26` | `10.0.0.13` (fabric: `10.254.1.26`) | `10.0.1.13` |

※ nuc-2 (`192.168.5.22` / `10.0.0.11` / `10.0.1.11`) は故障で退役

## 8. アンダーレイ OSPF Fabric 設計と将来構想 (PTP Mesh & Direct Connect)

### 8.1 現状の PTP 完全メッシュ設計
本クラスタのアンダーレイ（物理ノード間ルーティング）は、物理スイッチ (TL-SG105S) 上に Linux VLAN を定義し、4 ノード完全メッシュ ($K_4$) の Point-to-Point (PTP) リンクとして構成している。
各インターフェースで DR/BDR 選定をスキップすることで、高速なコンバージェンス（障害検知・切り替え）を担保する。

* VLAN 1: `nuc-1` ↔ `server-2`
* VLAN 2: `server-1` ↔ `server-2`
* VLAN 3: `nuc-1` ↔ `server-1`
* VLAN 4: `nuc-1` ↔ `dm-1`
* VLAN 5: `server-1` ↔ `dm-1`
* VLAN 6: `server-2` ↔ `dm-1`

### 8.2 将来構想: server-1 ↔ server-2 間の物理直結 PTP リンク
アンダーレイを単一サブネットのブロードキャスト構成にせず、あえて PTP メッシュを維持している主たる動機は、**server-1 と server-2 間の物理直結構想**を視野に入れているためである。

1. **背景とトラフィック特性**:
   * `server-1` と `server-2` は同一ラック内に収容された主力コンピュート機であり、PostgreSQL ストリーミングレプリケーション、SeaweedFS ボリューム同期、Kubernetes Pod 間通信など、クラスタ内最大の East-West トラフィックが発生する。
2. **物理リソースの空き**:
   * 両機ともに 4 ポート 2.5GbE カード（Realtek RTL8125）を搭載しており、未接続の空きポート（server-1: `enp8s0`, server-2: `enp11s0` など）が存在する。
3. **直結ルーティングの実現性**:
   * 将来、空きポート同士を LAN ケーブル（または DAC）で物理直結し、OSPF コストを調整することで、**「通常時はスイッチを介さない直結 2.5Gbps ケーブルで高速通信し、障害時は自動的にスイッチ経由にフェイルオーバーする」** 冗長・高速化構成が OSPF だけで自然に実現できる。
4. **設計方針**:
   * ノード追加時の VLAN ペアリング定義という運用コストはあるものの、上記の物理直結 PTP との親和性およびトラフィック分離の自由度を最優先とし、現在の PTP メッシュ設計を正として維持する。
