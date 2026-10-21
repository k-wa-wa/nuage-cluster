# クラスタ使用量の日次帳票 (設計・仮置き)

メインフレーム ([mainframe.md](./mainframe.md)) で、クラスタの前日分の使用量を COBOL で集計し、
昔ながらの帳票 (1403 ラインプリンタ形式) として出力する。課金はしない。

本書は設計の仮置きである。出力項目は実際に動かしてから見直す。

## 1. 決まっていること

| 項目 | 内容 |
| :-- | :-- |
| 頻度 | 日次。毎朝、前日 (日本時間 0:00〜24:00) 分を出す |
| 実行時刻 | 06:00 (自動アップグレードによる再 IPL の 04:50 を避ける) |
| 成果物 | 帳票のテキスト (`.txt`) と PDF (`.pdf`) |
| 置き場所 | LXC 内の `/var/lib/mainframe/reports/YYYY/MM/usage-YYYY-MM-DD.{txt,pdf}`。LXC ごと PBS でバックアップされる |
| 集計 | MVS の中で行う (SORT → COBOL)。Linux 側はデータの取得と、帳票の受け取り・PDF 化だけを担う |

## 2. 出力項目 (仮)

データは VictoriaMetrics (`http://10.20.1.20:8427/api/v1/query`、prvmain から参照可) から PromQL で取る。
取得できることは確認済みである。

### 区分 K8S: namespace ごと

| 列 | 意味 | PromQL (前日 1 日分) |
| :-- | :-- | :-- |
| CPU-H | CPU 使用量 (コア時間) | `sum by (namespace) (increase(container_cpu_usage_seconds_total{container!=""}[1d])) / 3600` |
| MEM-GBH | メモリ使用量 (平均 GB × 24 時間) | `sum by (namespace) (avg_over_time(container_memory_working_set_bytes{container!=""}[1d])) / 2^30 * 24` |
| NET-GB | 通信量 (受信 + 送信) | `sum by (namespace) (increase(container_network_receive_bytes_total[1d]) + increase(container_network_transmit_bytes_total[1d])) / 1e9` |
| STOR-GB | 確保しているストレージ (PVC の要求量、日末時点) | `sum by (namespace) (kube_persistentvolumeclaim_resource_requests_storage_bytes) / 2^30` |

### 区分 HOST: NixOS の LXC / VM ごと

node-exporter の値から同じ列を作る (CPU は `node_cpu_seconds_total` の idle 以外、メモリは `MemTotal - MemAvailable` の平均、
通信量は `node_network_*_bytes_total`、ストレージは `/` の使用量)。k8s ノードは二重計上になるため含めない。
LXC 内の node-exporter が LXC 自身の値を正しく返すかは要検証である。

### 帳票のイメージ

区分が変わるところで小計を出し (コントロールブレイク)、最後に総合計を出す。

```
 NUAGE CLUSTER                    DAILY RESOURCE USAGE REPORT                         PAGE    1
 USAGE DATE: 2026-10-21                                                   RUN DATE: 2026-10-22

 CLASS  NAME                          CPU-H       MEM-GBH        NET-GB       STOR-GB
 -----  ------------------------  ---------  ------------  ------------  ------------
 K8S    KUBE-SYSTEM                   12.00        249.95        261.32          0.00
 K8S    NUAGE-MONITORING-STACK         5.78        125.22        115.83         86.00
 K8S    PECHKA                         3.70        202.68         18.66         40.00
   ...
                              * CLASS TOTAL  K8S   ...
 HOST   PG-CLUSTER-1                   3.97           ...
   ...
                              * CLASS TOTAL  HOST  ...
                             ** GRAND TOTAL        ...
```

### 後で足したいもの

- **前日比**: 日々のデータを MVS の中のデータセットに貯めていき、前日との増減を出す。メインフレームを常駐させる意味が出る部分である
- **月次の締め**: 月末に 1 か月分を集計した月報を出す

## 3. 処理の流れ

```
 mainframe LXC (systemd timer, 毎日 06:00)
  1. 取得    Python: PromQL で前日分を取得し、80 桁の固定長レコード (カード) にする
  2. 組立    JCL を組み立てる: データカード + COBOL ソース (リポジトリ管理)
  3. 実行    mvsctl submit で投入し、終了と COND CODE を確認する
               MVS 内: STEP1 SORT (区分・名前順) → STEP2 COBOL (集計して帳票を出力)
  4. 回収    ジョブ出力から帳票部分を切り出し、.txt として保存する
  5. PDF 化  Python (reportlab): 132 桁を横向きに配置し、緑の縞模様 (グリーンバー) を敷く
```

ジョブの投入・終了待ち・判定には、mvs-config と同じ `mvsctl submit` を使う。

### 固定長レコード (仮)

COBOL は固定長レコードを読むのが基本である。数値は小数点を持たず、桁位置で小数を表す (`PIC 9(7)V99`)。

| 桁 | 長さ | 内容 | COBOL の定義 |
| :-- | :-- | :-- | :-- |
| 1-5 | 5 | 区分 (`K8S  ` / `HOST `) | `PIC X(5)` |
| 6-29 | 24 | 名前 (大文字) | `PIC X(24)` |
| 30-38 | 9 | CPU-H × 100 | `PIC 9(7)V99` |
| 39-47 | 9 | MEM-GBH × 100 | `PIC 9(7)V99` |
| 48-56 | 9 | NET-GB × 100 | `PIC 9(7)V99` |
| 57-65 | 9 | STOR-GB × 100 | `PIC 9(7)V99` |
| 66-80 | 15 | 予備 | `PIC X(15)` |

## 4. 要検証・未決事項

| 項目 | 内容 |
| :-- | :-- |
| 帳票とジョブログの分離 | 帳票を別の出力クラスに出し、プリンタ 2 (`prt00f.txt`) で受けると、ジョブログと混ざらず切り出しが楽になる。JES2 のプリンタ 2 がどのクラスを受け持つかは未確認 |
| SORT の使い方 | MVS 3.8j の SORT (カタログ手続き `SORT`) で並べ替えられるか確認する |
| HOST 区分の値 | LXC 内の node-exporter の CPU・メモリが、LXC 自身の値になっているか確認する |
| PDF の参照方法 | 当面は `scp mainframe:/var/lib/mainframe/reports/...` で取り出す。ブラウザで見たくなったら HTTP 配信を検討する |
| 失敗時の通知 | systemd unit の失敗を監視・通知に載せる (node-exporter の systemd コレクター経由) |
