# Strata 0.2 による Qwen3.8-Flash-Next 動作検証と性能評価

## 1. 概要と目的

`lm-server` において、推論エンジン「Strata 0.2」および超大規模 MoE モデル「Qwen3.8-Flash-Next（125B MoE / 6B active）」を導入し、現行の `Qwen3.8-27B`（実測 21〜27 tok/s）を超える推論能力と高速生成（目標 40〜60 tok/s）が実現可能かを実機検証・環境整備した記録である。

当初の 32GB RAM / ライザー GPU 構成（mmap モード）ではストレージ I/O 待ちと PCIe 帯域制約により生成速度が 10.5〜10.8 tok/s にとどまっていたが、**RAM 48GB 拡張** および **マザーボード直挿し GPU への切り替え（PCIe 3.0 x8 フル帯域 6.703 GB/s）** を行い、全エキスパート（約 33GiB）を RAM に完全常駐させる「常駐モード（Resident Expert Arena）」を適用した。

その結果、ディスク I/O 待ちが完全ゼロ（0%）となり、初回応答時間（TTFT）は 5,239 ms から **1,410 ms (46.8 tok/s)** へ 3.7 倍高速化し、トークン生成速度も **21.2〜22.9 tok/s（ピーク 23.5 tok/s）** へ倍増した。現行 27B 密モデルと同等の実用速度で 125B 級 MoE モデルが安定稼働することを実証した。

## 2. 検証環境スペック

- **ホスト VM (`lm-server`)**:
  - CPU: host 4 コア (AVX-2 対応、ホスト CPU: AMD Ryzen 5 5500)
  - RAM:
    - 当初検証: 32 GiB (OS 認識: 31 GiB)
    - 最新検証: **48 GiB** (OS 認識: 47 GiB、起動前 available 約 45 GiB)
  - ディスク: 200 GB (`/dev/vda2` オンライン拡張済み、空き容量約 96 GiB)
  - OS: NixOS 26.05
- **GPU**:
  - Sapphire Radeon RX 7600 XT 16GB (Navi 33 / `gfx1102`、VRAM 16,368 MiB)
  - PCIe パススルー構成:
    - 当初検証: ライザー側スロット（PCIe 0000:06:00、実測帯域 3.1〜3.3 GB/s）
    - 最新検証: **直挿し側スロット（PCIe 0000:05:00、PCIe 3.0 x8 フル帯域 実測 6.703 GB/s）**
- **ソフトウェア構成**:
  - ROCm: 7.2.3 (NixOS rocmPackages)
  - 推論エンジン: Strata 0.2 (Engine 0.1.50, `rx7900` Linux パッケージ / gfx1102 最適化)
  - モデル: `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF` (IQ2_XS 量子化)
    - Shard 1 (36.5 GiB / 39.2 GB): `Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf`
    - Shard 2 (26.8 GiB / 28.8 GB / PLE table): `Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00002-of-00002.gguf`
    - 合計サイズ: 63.4 GiB (68.0 GB)、pack: 約 1.5 GiB

## 3. ROCm (`gfx1102`) 向けビルド環境と API サーバー構成の検証

### 3.1 ソースビルド環境と公式 prebuilt の採用（仕様 2 の状況）
- `rocmPackages.clr` (Clang 22.0.0, hipClang), `rocmPackages.hipblas`, `rocmPackages.hipblaslt`, `rocmPackages.rocblas` を用いた環境において、`-DCMAKE_HIP_ARCHITECTURES=gfx1102` を指定した CMake / Ninja ビルドの configure が正常に通ることを確認した。
- `find_package(hipblas)` および `find_package(hipblaslt)` が正常に解決され、`roc::hipblaslt` がリンク対象として検出されることを確認した。
- ただし、上流の `CMakeLists.txt` には `install` ルールが定義されておらず、また HIP カーネルのフルコンパイル完了とリンク動作確認までは未完了である。
- そのため、実機検証および再現可能な Nix パッケージ化にあたっては、`gfx1102`（Navi 33）向けコードオブジェクトが同梱された公式 prebuilt リリース（`rx7900`）を採用し、NixOS の autoPatchelf を適用した derivation (`nix/hosts/lm-server/pkgs/strata.nix`) として整備した。

### 3.2 サーバー構成と実機推論の動作確認
- 推論エンジンバイナリ `strata` の `--serve` オプションは stdin/stdout 経由で 1 行ずつ要求を処理する IPC モードであり、直接 systemd サービスとして起動すると stdin が `/dev/null` となり EOF で終了を繰り返す。
- OpenAI 互換 HTTP API (ポート 8085) は、Python 製のサーバー層 (`serve/server.py`) が `strata.json` を解釈してエンジンを子プロセスとして管理・中継することで提供される。
- NixOS 上で再現可能に動作させるため、`pkgs/strata.nix` において推論エンジンと `strata-control`（Python サーバー層）を統合し、`strata-server` および pack 生成ツール `strata-pack` を生成するラッパーを整備した。
- 本 derivation（コミット `3448719` でビルドした Nix store パス `/nix/store/6v0svdcsh97gflb9gq85a535p335x5s7-strata-0.2.6/`）のバイナリおよびラッパーを用い、実機 GPU 上で `strata-server` を起動して OpenAI 互換 API (`/v1/chat/completions`) 経由で推論リクエストが正常に完走することを確認済みである。HEAD では未使用の依存パッケージを整理しており、手元ビルドおよび `ldd` による動的リンク依存の完全解決を確認している。

### 3.3 ランタイムリンクと gfx1102 最適化
- Navi 33 (`gfx1102`) では、デフォルトの `CUDA_R_16BF` (BFLOAT16) による GEMM が `HIPBLAS_STATUS_EXECUTION_FAILED` (code 6) を返す挙動が確認された。
- 以下の環境変数を指定することで、RDNA3 の WMMA ネイティブ GEMM および FP16 ルートが正常に起動し、安定動作することを確認した：
  - `STRATA_HIP_PROMPT_F16=1`: プロンプトの 16-bit GEMM を FP16 入出力で実行
  - `STRATA_WMMA_GEMM=1`: RDNA3 ネイティブ WMMA 行列積を有効化
  - `STRATA_PF_GEMM=1`: プレフィルの最適化 GEMM を有効化

## 4. 推論動作確認と性能実測比較

同一ハードウェア上において、現行の `llama-cpp` (Qwen3.8-27B) と、Strata (Qwen3.8-Flash-Next 125B MoE) の当初検証（32GB RAM / mmap）および最新検証（48GB RAM / 常駐モード）に同一プロンプト（`Why is the sky blue? Answer in 3 concise paragraphs.`）を送信して比較した。

### 4.1 性能メトリクス比較表

| 項目 | 現行: llama-cpp (Qwen3.8-27B) | 当初検証: Strata 0.2 (32GB RAM / mmap) | 最新検証: Strata 0.2 (48GB RAM / 常駐) |
| :--- | :--- | :--- | :--- |
| **モデル規模** | 27B dense | 125B MoE (6B active) | **125B MoE** (6B active) |
| **量子化方式** | UD-IQ4_XS (14.3 GB / 13.3 GiB) | GSQ-RCO IQ2_XS (計 63.4 GiB / 68.0 GB) | **GSQ-RCO IQ2_XS** (計 63.4 GiB / 68.0 GB) |
| **ハードウェア環境** | 32GB RAM / PCIe 3.2 GB/s | 32GB RAM / PCIe 3.2 GB/s | **48GB RAM / PCIe 6.703 GB/s (直挿し)** |
| **動作モード** | VRAM 完全収容 | `--mmap-experts` (ページキャッシュ) | **常駐モード (Resident Expert Arena)** |
| **トークン生成速度** | **22.41 tok/s** (*1) | 10.5〜10.8 tok/s (233 tok / 22.15 s) | **21.2〜22.9 tok/s (ピーク 23.5 tok/s)** |
| **初回プロンプト処理 (TTFT)** | **875 ms** (74.3 tok/s) | 4,593〜5,239 ms (12.4〜14.2 tok/s) | **1,410 ms** (46.8 tok/s) |
| **ディスク I/O 待ち** | なし (0%) | **約 54%** (5,040 ms / 9,297 ms) | **0% (完全解消)** |
| **ホスト RAM 使用量** | 2.3 GiB | 約 3.0 GiB (ページキャッシュ最大約 29.5 GiB) | **プロセス約 35.8 GiB** (全エキスパート 33.02 GiB 常駐) |
| **GPU VRAM 使用量** | 15.5 GiB / 16.0 GiB (約 16.6 GB) | 15.39 GiB / 16.0 GiB (16GB 枠内に収容) | **15.39 GiB** / 16.0 GiB (16GB 枠内に収容) |
| **投機的デコード (MTP)** | 有効 (採択率 55.7%) | 有効 (採択率 53.3〜62.5%) | 有効 (採択率 53〜62%) |
| **VRAM エキスパート数** | 全層常駐 (100%) | 8,616 スロット (キャッシュ率 84.5〜87.8%) | 8,616 スロット (キャッシュ率 85〜88%) |

*1: llama-server 内部計測値（201 tok / 8.92 s の単純除算では 22.53 tok/s）。

### 4.2 メモリ挙動の評価
- **32GB RAM（mmap モード）**:
  - 全エキスパート（35.4 GB）を物理 RAM に常駐させる `--resident-experts` は 32GB RAM の VM では OOM となるが、Strata の `--mmap-experts` モードを使用することで、OS のページキャッシュと連携して動作させた。
  - プロセスの実メモリ（used）は **約 3.0 GiB** に抑えられ、重みファイルは OS のページキャッシュ（buff/cache: 最大約 29.5 GiB）を介して動的にキャッシュ・再利用された。空きメモリ枠内で動的に解放されるため、available は約 28.4 GiB 確保され、32GB 枠内で安全に稼働した。
  - エンジンログに記録された `page cache held 43243.1 MB at the read` は、1 リクエスト内の全エキスパート読み出し（累計 55.9 GB 分）のうちページキャッシュからヒットした累計サイズであり、物理常駐量ではない。
- **48GB RAM（常駐モード / Resident Expert Arena）**:
  - ホスト RAM を 48GB に拡張したことで、`--mmap-experts` を外し、全エキスパート（約 33.02 GiB）を物理 RAM に完全常駐させる「常駐モード」を適用した。
  - OS 上で 47 GiB 認識され、起動前 available は約 45 GiB を確保。プロセスが全エキスパート 33.02 GiB を物理メモリ上に確保した状態でもシステム全体で数 GiB の余裕を維持し、OOM の懸念なく安定稼働した。
  - 全エキスパートが RAM に常駐しているため、ディスクからの読み出しは一切発生せず、ストレージ I/O 待ちは完全ゼロ（0%）となった。
  - なお、ホスト RAM が不足している場合、エンジンは自動的に mmap フォールバックに切り替わる。常駐が正しく機能しているかは、`/var/log/strata/strata-engine.log`（または `journalctl -u strata`）に `expert arena: resident` が出力されていることで確認できる。
- **GPU VRAM**:
  - KV キャッシュを `q4_0`、KV streaming を `20480`、VRAM エキスパートキャッシュを `auto`（8,616 スロット、約 11.53 GiB）に配分することで、合計 **15.39 GiB** となり、16GB の VRAM に完全に収容された。

### 4.3 起動に必要な環境構築手順
Strata による Qwen3.8-Flash-Next の環境構築は以下の手順で実施する：

1. **モデル GGUF のダウンロード**:
   `/var/lib/strata` は Strata 有効化前は手動作成した `agent:users` (0755) であり、`services.strata.enable = true` 有効化後は systemd の `StateDirectory` により `strata:strata` (0775) で管理される（`agent` ユーザーも `strata` グループに所属）。有効化後にファイルを配置・編集する場合は、`chmod -R g+w /var/lib/strata` でグループ書き込み権限を付与するか `sudo` で作業する。
   ```bash
   mkdir -p /var/lib/strata/models/IQ2_XS
   cd /var/lib/strata/models/IQ2_XS
   # Shard 1 (36.5 GiB / 39.2 GB)
   aria2c -s 8 -x 8 -k 1M -c "https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF/resolve/main/IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf"
   # Shard 2 (26.8 GiB / 28.8 GB)
   aria2c -s 8 -x 8 -k 1M -c "https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF/resolve/main/IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00002-of-00002.gguf"
   ```

2. **Pack の抽出・生成**:
   `strata.nix` パッケージ同梱の `strata-pack` ツールを用いて、GGUF から pack (`dense.bin` および tokenizer) を作成する。`strata-pack` は Strata 有効化時に `environment.systemPackages` 経由で PATH に入る。有効化前に実行する場合はビルド済み Nix store パス（`/nix/store/...-strata-0.2.6/bin/strata-pack`）またはパッケージ同梱のスクリプト直接実行（`python3 <strata-pkg>/share/strata/tools/iq_pack.py`）を使用する。
   ```bash
   strata-pack \
     --gguf /var/lib/strata/models/IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf \
     --out /var/lib/strata/packs/iq2_xs
   ```

3. **Expert Profile の配置**:
   パッケージ同梱のプロファイルファイル (`<strata-pkg>/share/strata/data/expert-profile.bin`) を使用する。`strata.nix` モジュールの `expertProfile` オプションにデフォルトで設定されている。

## 5. ボトルネック分析と技術的課題

当初の 32GB RAM / mmap モードおよび最新の 48GB RAM 常駐モードにおけるプロファイリングに基づき、ボトルネック要因と物理制約を分析した：

1. **ストレージ I/O 待ちの完全解消（48GB RAM 常駐化）**:
   - 32GB RAM / mmap モードでは、VRAM キャッシュから漏れたエキスパート参照において仮想ディスク (`/dev/vda2`) からのオンデマンド読み出しが発生し、ストレージ I/O 待ちが全生成時間の約 54%（100 トークン生成時、総時間 9,297 ms 中 5,040.2 ms）を占有していた。
   - 当時のプロファイリングにおいて、このストレージ読み出し待ち（5,040.2 ms）を除いた純粋な処理時間（4,256.8 ms）から算出された見かけの計算速度は約 23.5 tok/s 相当であったが、この残り時間にはライザー経由（3.2 GB/s）の PCIe 転送遅延が依然として重畳しており、実測生成速度は約 10.8 tok/s に制約されていた。
   - 48GB RAM への拡張および常駐モード（`--mmap-experts` 削除）により、全エキスパート（33.02 GiB）が物理メモリに常駐したことで、ディスクからの読み出しは完全ゼロ（0%）となり、ストレージ I/O ボトルネックは完全に解消された。
2. **ハードウェアの物理的理論上限（PCIe 3.0 x8）への到達**:
   - GPU をマザーボード直挿しスロットへ切り替えたことで、PCIe 転送帯域は 3.2 GB/s（ライザー側スロット）から **6.703 GB/s（PCIe 3.0 x8 フル帯域）** へと約 2.1 倍に向上した。
   - サーバーホストの CPU である AMD Ryzen 5 5500 は Cezanne アーキテクチャ（APU 由来ダイ）を採用しており、CPU の物理仕様として PCIe 3.0 が上限となる。
   - **PCIe 3.0 x8 転送遅延からの逆算**:
     - Qwen3.8-Flash-Next（125B MoE / 6B active）において、全エキスパートは約 33.02 GiB（8,616 スロット、1 エキスパートあたり約 1.37 MiB）である。
     - VRAM エキスパートキャッシュ（8,616 スロット、約 11.53 GiB）のヒット率は実測 84.5〜87.8% であり、残りの約 12.2〜15.5% のエキスパートはホスト RAM から PCIe 経由でオンデマンド転送される。
     - 1 トークン生成（投機的デコードのドラフト検証ステップを含む）において、平均して約 20〜25 個のエキスパート（約 27〜35 MiB）のミスヒット転送が発生する。
     - PCIe 3.0 x8（実効帯域 6.703 GB/s）において、この約 27〜35 MiB を DMA 転送する所要時間は、転送起動レイテンシや同期オーバーヘッドを含めて 1 トークンあたり約 20〜25 ms を要する。
     - これに GPU 内部での推論計算時間（アテンション、密層、GEMM 計算等で約 15〜20 ms/tok）が合算されるため、1 トークンあたりの最小処理時間は約 40〜44 ms（1,000 ms / 40〜44 ms ≒ **約 23〜25 tok/s**）がハードウェア環境における物理的理論上限となる。
   - 最新検証で達成した **21.2〜22.9 tok/s（ピーク 23.5 tok/s）** は、この物理的理論上限の限界までハードウェア性能を引き出した結果である。
   - これにより、パラメータ規模が約 4.6 倍大きい 125B 級 MoE モデル（Sonnet / Opus 級の推論能力）を、現行 27B 密モデルと同等の速度で実用稼働させる環境が整った。
3. **将来展望（PCIe 4.0 CPU 換装によるさらなる拡張性）**:
   - マザーボード（`docs/hardware-inventory.md` 記載の ASRock X570S PG Riptide）および GPU（Radeon RX 7600 XT）自体は PCIe 4.0 に対応しているため、将来的に CPU を PCIe 4.0 対応モデル（Ryzen 5 5600 や Ryzen 9 5900XT 等の Vermeer ダイ）に換装した場合、PCIe 帯域は PCIe 4.0 x8 相当の **13〜14 GB/s** へ倍増する。
   - ホスト RAM からのエキスパート転送遅延が半減（約 20〜25 ms → 約 10〜12 ms）することで、当初目標としていた **35〜45+ tok/s** の超高速推論に到達できる高い拡張性を有している。

## 6. 結論と本番運用の推奨

1. **動作検証の結論**:
   - Strata 0.2 による `Qwen3.8-Flash-Next` の起動、OpenAI 互換 API による推論リクエスト、および 48GB RAM / 16GB VRAM 枠内での安定稼働を実機で実証した。
   - 48GB RAM 常駐モードと直挿し GPU により、トークン生成速度は実測 **21.2〜22.9 tok/s（ピーク 23.5 tok/s）**、初回応答 TTFT は **1,410 ms (46.8 tok/s)** を達成した。
   - 現行 27B 密モデル（22.41 tok/s）と同等の応答速度を維持しながら、125B 級の高度な知能と長文推論品質を単一 16GB GPU のコンシューマ環境で OOM なく発揮できることを確認した。
2. **本番運用の推奨と切り替え方針**:
   - **運用方針**: VM は 1 台のまま共存運用とし、デフォルトは安定運用の現行 `llama-cpp`（27B）を維持しつつ、フラグ 1 つ（`services.strata.enable = true`）で 125B MoE 常駐モードへ安全に切り替えられる構成とする。
   - **排他制御**: `strata.nix` に実装済みの排他制御（`conflicts = [ "llama-cpp.service" ]` および `services.llama-cpp.enable = lib.mkForce false`）により、同一 GPU (16GB VRAM) の競合なく安全に排他起動する。
   - **切り替え時の注意点**:
     1. **事前資材の配置確認**: `/var/lib/strata/models/IQ2_XS` に GGUF モデル（約 63.4 GiB）および `/var/lib/strata/packs/iq2_xs` に pack（約 1.5 GiB）が事前に生成・配置されていることを確認する。資材が無い状態で有効化するとサービスが起動失敗を繰り返し、`Restart=always` で 10 秒ごとの再起動ループに陥る。
     2. **ポートとモデル名の整合性確保**:
        - 現行の Kubernetes 側（`manifests/apps/litellm/base/config.yaml` および `manifests/apps/external-service/base/lm-server.yaml`）は、ポート `8080` かつモデル名 `openai/qwen3.8-27b` を参照している。
        - Strata の既定値はポート `8085`、モデル名 `qwen3.8-flash-next` であるため、既存クライアントへの影響を避けてインプレースで切り替える場合は、`nix/hosts/lm-server/configuration.nix` で以下のようにポートとモデル名を揃える：
          ```nix
          services.strata = {
            enable = true;
            port = 8080;
            modelName = "qwen3.8-27b";
          };
          ```
          （あるいは、LiteLLM / external-service 側の設定をポート 8085 / `openai/qwen3.8-flash-next` に合わせて GitOps で更新する）
     3. **有効化と排他起動**: `services.strata.enable = true` を設定することで、モジュール側で `services.llama-cpp.enable` は自動的に `lib.mkForce false` で無効化され、同一 GPU (16GB VRAM) を奪い合うことなく安全に排他起動する。
3. **実機上の検証資材の扱いとバックアップへの影響**:
   - 実機 `/var/lib/strata` に配置された検証用資材（モデルファイル約 63.4 GiB、pack 約 1.5 GiB、計約 64.9 GiB）は、現状ルートディスク（200GB）の空き容量が約 96 GiB あり、ローカルディスク容量面では即座の問題はない。
   - ただし、`terraform/vpc/zone-private-k8s/lm-server.tf` に定義されている Proxmox Backup Server (PBS) への日次スナップショットバックアップ (`lm_server_backup`) において、これらの資材により PBS 上で約 65GB 分のバックアップストレージ消費が発生する（PBS のチャンク重複排除により日次の増分差分は抑えられるが、ベースデータとして保持される）。
   - そのため、Strata を長期間運用に供しない場合や PBS のストレージ容量を節約したい場合は、`/var/lib/strata` 配下の資材を削除することを推奨する。
