# メインフレーム (MVS 3.8j on Hercules)

LXC `mainframe` の上で、IBM のメインフレーム用 OS「MVS 3.8j」を常駐させている。
COBOL のバッチジョブを流し、結果を帳票として受け取るための環境である。

最終的な目的は、クラスタの使用量を COBOL で集計し、昔ながらの帳票として出すことである (未着手)。

## 1. ひとことで言うと

**テキスト (JCL + COBOL のソース) を送ると、実行結果がテキストファイルで返ってくる箱**である。

- 箱そのもの (メインフレーム) は常に動いている。k8s のクラスタにあたる
- その上で、バッチジョブを投げては終わらせる。k8s の Job にあたる

## 2. 全体像

```
 Mac (c3270) ── TN3270 ──▶ lb の VIP 192.168.5.200:3270 ──┐
                                                          │
 ┌─ LXC: mainframe (NixOS, 10.20.1.90) ────────────────────┼──────────┐
 │                                                        ▼          │
 │  hercules.service ─ Hercules (メインフレームの機械を真似するソフト) │
 │                       └─ MVS 3.8j (OS)                            │
 │                            ├─ JES2 (ジョブの受付・順番待ち・出力) │
 │                            ├─ TSO  (ログインして対話操作する環境) │
 │                            └─ COBOL コンパイラ など               │
 │                                                                   │
 │  入口: mvs-submit ─▶ カードリーダ 127.0.0.1:3505                   │
 │  出口: 1403 プリンタ ─▶ /var/lib/mainframe/printers/prt00e.txt     │
 │  操作: mvs-console ─▶ /run/mainframe/console                       │
 │  表示: journalctl -u hercules  (MVS のコンソールメッセージ)        │
 └───────────────────────────────────────────────────────────────────┘
```

### どこからがメインフレームか

`ssh mainframe` で入れるのは、Hercules を載せている **Linux (NixOS の LXC)** であり、メインフレームそのものではない。
メインフレームは **Hercules のプロセスの内側**から始まる。

```
 server-1 (Proxmox)
  └─ LXC mainframe (NixOS)           ← ssh で入る場所。マシン室と管理用 PC にあたる
      └─ Hercules のプロセス           ← ここから内側がメインフレーム (CPU・16MB の主記憶・装置)
          └─ MVS 3.8j                 ← メインフレームの OS。SSH は存在しない
              └─ JES2 / TSO / ジョブ
```

| ポート | 着く先 | 層 |
| :-- | :-- | :-- |
| 22 (SSH) | NixOS | Linux |
| 3270 (TN3270) | MVS の TSO・VTAM | メインフレーム |
| 3505 (カードリーダ) | MVS の JES2 | メインフレーム |

MVS 3.8j の時代には SSH も TCP/IP も無く、人は 3270 端末で、ジョブはカードで入った。
現代の z/OS には UNIX 互換の環境 (z/OS UNIX) があり SSH で入れるが、それは後から追加された部分である。
なお本物のメインフレームにも、筐体を電源投入・IPL・監視するための管理用 PC (HMC) が付いている。
この環境では、LXC と systemd・`mvs-console` がその役割を担う。

## 3. 用語集

### 基盤

| 用語 | 意味 | 身近なものに例えると |
| :-- | :-- | :-- |
| メインフレーム | 銀行の勘定系などで使われる、大量の業務データを確実に処理するための大型コンピュータ | - |
| Hercules | メインフレームの機械 (CPU・ディスク・プリンタ等) をソフトウェアで再現するエミュレータ | QEMU |
| MVS 3.8j | 1970〜80 年代の IBM のメインフレーム用 OS。パブリックドメインで無料で使える。今の z/OS の先祖 | 昔の Linux ディストリビューション |
| MVS/CE | MVS 3.8j を、すぐ使える状態に組み上げた配布物 (Community Edition) | インストール済みの OS イメージ |
| IPL | メインフレームの起動 (Initial Program Load) | ブート |

### ジョブまわり

| 用語 | 意味 | 例えると |
| :-- | :-- | :-- |
| ジョブ | 1 回のバッチ処理の単位 | k8s の Job |
| JCL | ジョブの指示書。「どのプログラムを、どの入力で動かし、出力はどこへ」を書く | Job の YAML |
| ステップ | ジョブの中の 1 工程 (例: コンパイル → 実行で 2 ステップ) | Job の中のコンテナ 1 つ |
| カタログ手続き (PROC) | よく使うステップの組み合わせを定型化したもの。`EXEC COBUCG` のように呼ぶ | シェルスクリプトの関数 |
| COBUCG | COBOL を **C**ompile して **G**o (そのまま実行) する PROC | `go run` |
| JES2 | ジョブを受け付けて順番待ちさせ、実行し、出力をまとめる仕組み | スケジューラ + ジョブキュー |
| スプール | JES2 がジョブの入力と出力を一時的に溜めておく場所 | キューのストレージ |
| イニシエータ | ジョブを実際に動かす実行枠。`CLASS=A` のジョブは A の枠で動く | ワーカー |
| SYSOUT | ジョブの出力 (ログ・コンパイルリスト・`DISPLAY` の内容など) | 標準出力 |
| MSGCLASS | ジョブのログをどの出力クラスに出すか。`A` ならプリンタ 1 へ出る | ログの出力先 |
| 条件コード (COND CODE / RC) | ステップの終了コード。`0000` が成功 | exit code |
| ABEND | ジョブの異常終了。`S0C7` (数値データ不正) などのコードが付く | クラッシュ |

### 入出力装置 (Hercules では Linux 上のファイルやソケットになる)

| 装置 | 昔の実物 | この環境での実体 | 用途 |
| :-- | :-- | :-- | :-- |
| カードリーダ (3505) | 80 桁の紙カードを読む装置 | `127.0.0.1:3505` の TCP ソケット | **ジョブの入口**。JCL を流し込むと JES2 が受け付ける |
| ラインプリンタ (1403) | 1 行 132 文字を高速に印字するプリンタ | `printers/prt00e.txt` (追記されていく) | **ジョブの出口**。SYSOUT がここに出る |
| カードパンチ (3525) | カードに穴を開けて出力する装置 | `punchcards/*.txt` | MVS からデータを外に出す |
| DASD | ディスク装置 | `DASD/*.3350` などのイメージファイル | OS とデータ (データセット) が入る |
| 3270 端末 | 緑の文字のブロック型端末 | TN3270 (3270 番ポート) | TSO にログオンして対話操作する |
| マスターコンソール | オペレータ用の操作卓 | `journalctl -u hercules` と `mvs-console` | 起動・停止・状態確認 |

JCL の 1 行が 80 桁なのは、紙のカード 1 枚が 80 桁だったからである。

### データ・帳票まわり

| 用語 | 意味 |
| :-- | :-- |
| データセット | MVS のファイル。`SYS1.PROCLIB` のようにドット区切りの名前を持つ |
| PDS | 区分データセット。中に複数のメンバーを持つ、ディレクトリのようなデータセット |
| VSAM | キーで引けるデータセット。簡易的な DB として使える |
| EBCDIC | メインフレームの文字コード。ASCII とは別物で、Hercules が変換する |
| パック 10 進数 | 数字を 10 進数のまま保持する形式。お金の計算で誤差が出ない |
| 帳票 | 業務で使う決まった形式の印刷物 (請求書・日報・一覧表など)。バッチ処理の最終成果物 |
| コントロールブレイク | キー順に並んだデータを上から読み、キーが変わったところで小計を出す処理の型 |

## 4. 構成要素

### リポジトリ

| ファイル | 役割 |
| :-- | :-- |
| `terraform/vpc/zone-private-mainframe/mainframe.tf` | LXC 本体 (VMID 290 / server-1 / 2 コア・2GB・20GB / prvmain `10.20.1.90`) |
| `terraform/pve/hosts-secrets/main.tf` | LXC にマウントする `/var/lib/pve/mainframe` (sops 鍵・GitHub トークン) の配置 |
| `nix/hosts/mainframe/configuration.nix` | ホストの基本設定 |
| `nix/hosts/mainframe/hercules.nix` | Hercules の systemd サービス、補助コマンド、ファイアウォール |
| `nix/hosts/mainframe/hercules.cnf` | Hercules の構成 (= メインフレームのハードウェア構成。装置とつなぎ先の一覧) |
| `nix/hosts/mainframe/mvsce.nix` | MVS/CE v3.0.0 のリリース (DASD の初期イメージ、起動・停止スクリプト) |
| `nix/hosts/mainframe/samples/` | 動作確認用のジョブ (`/etc/mainframe/samples/` に配置される) |
| `nix/hosts/mainframe/mvs-config.nix` | MVS の中の設定を Git の内容に揃える `mvs-config.service` |
| `nix/hosts/mainframe/mvs-config/` | MVS の中の設定のあるべき姿 (`<データセット名>/<メンバー名>`) |
| `nix/hosts/mainframe/tools/mvsctl.py` | ジョブの投入・終了待ち・結果判定と、設定反映を行う CLI |
| `nix/hosts/mainframe/secrets.yaml` | MVS の管理者 (IBMUSER) のパスワード (SOPS) |
| `nix/hosts/loadbalancer/haproxy.cfg` | VIP `:3270` → `10.20.1.90:3270` の TN3270 中継 |

### LXC 上

| パス・ポート | 内容 |
| :-- | :-- |
| `/var/lib/mainframe/DASD/` | ディスクイメージ。MVS が書き換え続ける**状態**であり、PBS で日次バックアップされる |
| `/var/lib/mainframe/printers/prt00e.txt` | 1403 プリンタの出力 (ジョブ結果が追記されていく) |
| `/var/lib/mainframe/mvslog.txt` | マスターコンソールの記録 (IPL のたびに作り直される) |
| `/var/lib/mainframe/mvs-config.applied.json` | mvs-config が前回反映した内容のハッシュ (再 IPL の要否判定に使う) |
| `/run/mainframe/console` | Hercules へのコマンド入力口 (FIFO) |
| TCP 3270 | TN3270 (外部公開は lb 経由・LAN 内のみ) |
| TCP 3505 / 3506 | カードリーダ (localhost のみ) |
| TCP 9100 | node-exporter |

## 5. 使い方

### ジョブを流して結果を見る

```bash
ssh mainframe

# サンプルの COBOL ジョブを投入する
mvs-submit /etc/mainframe/samples/hello-cobol.jcl

# 結果を見る (数秒で出る)
grep -a "HELLO" /var/lib/mainframe/printers/prt00e.txt
# HELLO, NUAGE MAINFRAME
# 0.1 + 0.2 = 0.3
```

プリンタ出力の各ジョブは、ジョブ名を大きく描いたバナーページから始まる。
`IEF142I ... COND CODE 0000` が各ステップの成否である。

終了まで待って、そのジョブの出力だけを受け取るには `mvsctl submit` を使う。
終了コードは、COND CODE が `--max-cc` 以下で ABEND も JCL エラーも無ければ 0 になる。

```bash
mvsctl submit /etc/mainframe/samples/hello-cobol.jcl > hello.txt
# HELLOCOB: MAXCC=0000
```

JCL を書くときの注意:

- 1 行は 71 桁まで (72 桁目は継続記号、73〜80 桁目は連番欄)
- 中身は ASCII のみ (カードは EBCDIC に変換されるため、日本語は書けない)
- `MSGCLASS=A` にする (mvsctl はプリンタ 1 の出力でジョブの終了を判定する)

### コンソールを見る・操作する

```bash
# MVS のコンソールメッセージを流し見る
journalctl -u hercules -f

# オペレータコマンドを送る (先頭の / は MVS 向けの印)
mvs-console /D A,L     # 実行中のジョブ一覧
mvs-console '/$DA'     # JES2 で実行中のジョブ
```

### TSO にログオンする (Mac から)

```bash
brew install x3270     # c3270 (ターミナル版の 3270 端末エミュレータ) が入る
c3270 192.168.5.200:3270
```

ロゴ画面で Enter を押し、`logon IBMUSER/SYS1` と入力する。

| ユーザー | パスワード |
| :-- | :-- |
| IBMUSER | SYS1 |
| MVSCE01 | CUL8TR |
| MVSCE02 | PASS4U |

### MVS の中の設定を変える (GitOps)

`nix/hosts/mainframe/mvs-config/<データセット名>/<メンバー名>` を編集して master に push する。
autoUpgrade で `mvs-config.service` が動き、IEBUPDTE ジョブでメンバーを書き換える。
`SYS1.PARMLIB` のように再 IPL が必要なものは、前回から変わっていれば自動で再 IPL する。

| 管理しているもの | 内容 |
| :-- | :-- |
| `SYS1.PARMLIB(PARMTZ)` | タイムゾーン。`E,09` (日本時間)。MVS/CE の初期値は `W,05` (米国中部時間) |

```bash
journalctl -u mvs-config     # 反映結果 (MVSCONF: MAXCC=0000 など)
```

### 起動・停止

```bash
sudo systemctl stop hercules     # 正規の停止手順を流す (約 45 秒)
sudo systemctl start hercules    # IPL する (約 10 秒で TSO にログオンできる)
```

## 6. 設計判断

| 論点 | 結論 | 理由 |
| :-- | :-- | :-- |
| どの OS を使うか | MVS 3.8j (MVS/CE) | z/OS は Hercules での稼働がライセンス上許されない。MVS 3.8j はパブリックドメインで、COBOL コンパイラも同梱される。MVS/CE は sysgen をスクリプトで再現して作られており、リリースを固定して使える |
| k8s か LXC か | LXC で常駐 | DASD は書き換わる状態であり、「クラスタ内はステートレス」の原則に合わない。IPL も重く、常駐させて都度ジョブを投げる使い方が自然である |
| DASD の扱い | store のリリースから初回だけコピー | DASD は MVS が書き換える状態なので、store の読み取り専用イメージは「初期値」とする。リリースを上げても既存 DASD は置き換わらない |
| コマンドの入力経路 | FIFO を標準入力に読み書き両用で開く | Hercules の `--NoUI` は標準入力をコマンドとして読む。読み書き両用で開くと EOF にならず、systemd 管理下でもコマンドを受け続けられる |
| 停止方法 | `SHUTDOWN.RC` を流して完了を待つ | いきなり kill すると JES2 のスプールや DASD を壊す可能性がある |
| カードリーダの公開範囲 | localhost のみ | 接続できれば誰でもジョブを実行できるため |
| TN3270 の公開 | lb の VIP で中継、LAN 内のみ | LXC に管理セグメントの足を出さない。TN3270 は平文のため Cloudflare では公開しない |
| HAProxy のヘルスチェック | 付けない | チェックの接続ごとに Hercules が端末を割り当て、コンソールにログが出続けるため |
| ホストのシェル実行 | 禁止 (`SHCMDOPT DISABLE`) | MVS 側から LXC のシェルを叩ける経路を塞ぐ |
| MVS の中の設定の管理 | Git のファイルを IPL ごとにジョブで書き込む | DASD の中身は Nix から直接書き換えられない。毎回書き込むことで冪等かつ自己修復になり、手作業での変更も次の IPL で Git の内容に戻る |
| ジョブの完了判定 | プリンタ出力の `END JOB` バナー行 | コンソールログ (mvslog.txt) は IPL のたびに作り直されるが、プリンタ出力は追記され続けるため、投入前の末尾位置からの差分だけを見れば確実に自分のジョブを切り出せる |
| 管理者権限 | ジョブに `USER=IBMUSER` を付け、パスワードは SOPS で管理する | RAKF により、ユーザー指定なしのジョブはシステムのデータセットを書き換えられない (S913) |

## 7. 既知の課題・今後

- **初期パスワードのまま**: IBMUSER 等は公開されている既定値である。LAN 内限定とはいえ、TSO から変更する
- **初期パスワードの変更も mvs-config で行いたい**: RAKF のユーザー定義を mvs-config の管理対象にすれば、パスワード変更も GitOps にできる見込みである (未検証)
- **プリンタ出力が増え続ける**: `prt00e.txt` は追記され続ける。稼働中に空にしても正しく先頭から書き直されることは確認済みであり、ジョブ単位に切り出す仕組みと合わせて整理する
- **使用量レポート (本題)**: 設計は [mainframe-usage-report.md](./mainframe-usage-report.md) を参照
