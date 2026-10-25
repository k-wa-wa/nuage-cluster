# Strata 0.2 による Qwen3.8-Flash-Next 動作検証と性能評価

## 1. 概要と目的

`lm-server` において、推論エンジン「Strata 0.2」および超大規模 MoE モデル「Qwen3.8-Flash-Next（125B MoE / 6B active）」を導入し、現行の `Qwen3.8-27B`（実測 21〜27 tok/s）を超える推論能力と高速生成（目標 40〜60 tok/s）が実現可能かを実機検証・環境整備した記録である。

## 2. 検証環境スペック

- **ホスト VM (`lm-server`)**:
  - CPU: host 4 コア (AVX-2 対応)
  - RAM: 32 GiB (OS 認識: 31 GiB)
  - ディスク: 200 GB (`/dev/vda2` オンライン拡張済み、空き容量約 96 GiB)
  - OS: NixOS 26.05
- **GPU**:
  - Sapphire Radeon RX 7600 XT 16GB (PCIe 02:00.0 パススルー、Navi 33 / `gfx1102`、VRAM 16,368 MiB)
  - PCIe 帯域: 実測 3.1〜3.3 GB/s (Host -> Device)
- **ソフトウェア構成**:
  - ROCm: 7.2.3 (NixOS rocmPackages)
  - 推論エンジン: Strata 0.2 (Engine 0.1.50, `rx7900` Linux パッケージ / gfx1102 最適化)
  - モデル: `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF` (IQ2_XS 量子化)
    - Shard 1 (39.2 GB): `Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf`
    - Shard 2 (28.8 GB / PLE table): `Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00002-of-00002.gguf`

## 3. ROCm (`gfx1102`) 向けビルド環境と API サーバー構成の検証

### 3.1 ソースビルド環境と公式 prebuilt の採用
- `rocmPackages.clr` (Clang 22.0.0, hipClang), `rocmPackages.hipblas`, `rocmPackages.hipblaslt`, `rocmPackages.rocblas` を用いた環境において、`-DCMAKE_HIP_ARCHITECTURES=gfx1102` を指定した CMake / Ninja ビルドの configure が正常に通ることを確認した。
- `find_package(hipblas)` および `find_package(hipblaslt)` が正常に解決され、`roc::hipblaslt` がリンク対象として検出されることを確認した。
- ただし、上流の `CMakeLists.txt` には `install` ルールが定義されておらず、また HIP カーネルのフルビルド完了とリンク動作確認までは未完了である。
- そのため、実機検証および再現可能な Nix パッケージ化にあたっては、`gfx1102`（Navi 33）向けコードオブジェクトが同梱された公式 prebuilt リリース（`rx7900`）を採用し、NixOS の autoPatchelf を適用した derivation (`nix/hosts/lm-server/pkgs/strata.nix`) として整備した。

### 3.2 サーバー構成と OpenAI 互換 API 起動経路
- 推論エンジンバイナリ `strata` の `--serve` オプションは stdin/stdout 経由で 1 行ずつ要求を処理する IPC モードであり、直接 systemd サービスとして起動すると stdin が `/dev/null` となり EOF で終了を繰り返す。
- OpenAI 互換 HTTP API (ポート 8085) は、Python 製のサーバー層 (`serve/server.py`) が `strata.json` を解釈してエンジンを子プロセスとして管理・中継することで提供される。
- NixOS 上で再現可能に動作させるため、`pkgs/strata.nix` において推論エンジンと `strata-control`（Python サーバー層）を統合し、`strata-server` および pack 生成ツール `strata-pack` を生成するラッパーを整備した。

### 3.3 ランタイムリンクと gfx1102 最適化
- Navi 33 (`gfx1102`) では、デフォルトの `CUDA_R_16BF` (BFLOAT16) による GEMM が `HIPBLAS_STATUS_EXECUTION_FAILED` (code 6) を返す挙動が確認された。
- 以下の環境変数を指定することで、RDNA3 の WMMA ネイティブ GEMM および FP16 ルートが正常に起動し、安定動作することを確認した：
  - `STRATA_HIP_PROMPT_F16=1`: プロンプトの 16-bit GEMM を FP16 入出力で実行
  - `STRATA_WMMA_GEMM=1`: RDNA3 ネイティブ WMMA 行列積を有効化
  - `STRATA_PF_GEMM=1`: プレフィルの最適化 GEMM を有効化

## 4. 推論動作確認と性能実測比較

同一ハードウェア上において、現行の `llama-cpp` (Qwen3.8-27B) と `Strata` (Qwen3.8-Flash-Next 125B MoE) に同一プロンプト（`Why is the sky blue? Answer in 3 concise paragraphs.`）を送信して比較した。

### 4.1 性能メトリクス比較表

| 項目 | 現行: llama-cpp (Qwen3.8-27B) | 検証: Strata 0.2 (Flash-Next 125B MoE) |
| :--- | :--- | :--- |
| **モデル規模** | 27B dense | **125B MoE** (6B active) |
| **量子化方式** | UD-IQ4_XS (14.2 GB) | GSQ-RCO IQ2_XS (計 68.0 GB) |
| **トークン生成速度** | **22.41 tok/s** (201 tok / 8.92 s) | **10.5〜10.8 tok/s** (233 tok / 22.15 s) |
| **初回プロンプト処理 (TTFT)** | **875 ms** (74.3 tok/s) | **4,593〜5,239 ms** (12.4〜14.2 tok/s) |
| **ホスト RAM 使用量** | 2.3 GiB | **2.8 GiB** (プロセス RSS。OS ページキャッシュ最大 43.2 GB 利用) |
| **GPU VRAM 使用量** | 15.5 GiB / 16.0 GiB | **15.39 GiB** / 16.0 GiB (16GB 枠内に完全収容) |
| **投機的デコード (MTP)** | 有効 (採択率 55.7%) | 有効 (採択率 53.3〜62.5%) |
| **VRAM エキスパート数** | 全層常駐 (100%) | **8,616 スロット (11.53 GiB)** (キャッシュヒット率 84.5〜87.8%) |

### 4.2 メモリ挙動の評価
- **ホスト RAM**:
  - 全エキスパート（35.4 GB）を物理 RAM に常駐させる `--resident-experts` は 32GB RAM の VM では OOM となるが、Strata の `--mmap-experts` モードを使用することで、OS のページキャッシュと連携して動作させた。
  - プロセスの実メモリ（RSS）は **2.8 GiB** に抑えられ、ページキャッシュ（ログ記録: 最大 43,243 MB）は OS のファイルキャッシュとして動的に解放・再利用されるため、32GB 枠内で安全に稼働した。
- **GPU VRAM**:
  - KV キャッシュを `q4_0`、KV streaming を `20480`、VRAM エキスパートキャッシュを `auto`（8,616 スロット、約 11.53 GiB）に配分することで、合計 **15.39 GiB** となり、16GB の VRAM に完全に収容された。

### 4.3 起動に必要な環境構築手順
Strata による Qwen3.8-Flash-Next の環境構築は以下の手順で実施する：

1. **モデル GGUF のダウンロード**:
   ```bash
   mkdir -p /var/lib/strata/models/IQ2_XS
   cd /var/lib/strata/models/IQ2_XS
   # Shard 1 (39.2 GB)
   aria2c -s 8 -x 8 -k 1M -c "https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF/resolve/main/IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf"
   # Shard 2 (28.8 GB)
   aria2c -s 8 -x 8 -k 1M -c "https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF/resolve/main/IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00002-of-00002.gguf"
   ```

2. **Pack の抽出・生成**:
   `strata.nix` パッケージ同梱の `strata-pack` ツールを用いて、GGUF から pack (`dense.bin` および tokenizer) を作成する。
   ```bash
   strata-pack \
     --gguf /var/lib/strata/models/IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf \
     --out /var/lib/strata/packs/iq2_xs
   ```

3. **Expert Profile の配置**:
   パッケージ同梱のプロファイルファイル (`<strata-pkg>/share/strata/data/expert-profile.bin`) を使用する。`strata.nix` モジュールの `expertProfile` オプションにデフォルトで設定されている。

## 5. ボトルネック分析と技術的課題

目標生成速度（40〜60 tok/s）および現行 27B（21〜27 tok/s）に達しなかった要因をログとプロファイリングから特定した：

1. **ストレージ I/O 待ちが全生成時間の約 54% を占有**:
   - エンジンログ：
     `decode waited 5040.2 ms in 3103 fetches` (総生成時間 9,297 ms 中)
   - VRAM キャッシュから漏れた約 12〜15% のエキスパート参照において、仮想ディスク (`/dev/vda2`) からのオンデマンド読み出しが発生した。
   - 純粋な計算時間のみであれば 9,297 - 5,040 = 4,257 ms (100 トークン) であり、**約 23.5 tok/s** の計算能力が出ているが、ストレージ I/O 待ちによって見かけの速度が約 10.8 tok/s に低下している。
2. **PCIe 転送帯域の物理制約**:
   - PCIe 帯域の実測値が 3.1〜3.3 GB/s（PCIe 3.0 x4 相当）にとどまり、ミスヒットしたエキスパートをホストから GPU に転送する際の帯域ネックが生じている。
3. **125B パラメータ規模のオフロード限界**:
   - Qwen3.8-27B（14GB）は全パラメータが 16GB VRAM 内に収まり純粋な GPU メモリ帯域（数百 GB/s）で動作する。
   - 一方、125B MoE（68GB）は単一 16GB GPU では物理的にオフロードが不可避であり、PCIe / ディスク I/O 帯域が全体の律速となる。

## 6. 結論と本番運用の推奨

1. **動作検証の結論**:
   - Strata 0.2 による `Qwen3.8-Flash-Next` の起動、OpenAI 互換 API による推論リクエスト、および 32GB RAM / 16GB VRAM 枠内での安定稼働を実機で実証した。
   - 生成速度は実測 **10.5〜10.8 tok/s** であり、目標（40〜60 tok/s）や現行 27B（21〜27 tok/s）には届かないが、125B 級の知能を持つモデルが 16GB GPU + 32GB RAM のコンシューマ環境で OOM なく完走することを確認した。
2. **本番運用の推奨**:
   - **対話応答速度を重視する場合**: 現行の `Qwen3.8-27B` (21〜27 tok/s) を継続利用することが推奨される。
   - **推論知能・長文推論品質を重視する場合**: 今回整備した `strata.nix` により、必要に応じて Strata (Qwen3.8-Flash-Next) に切り替え可能な構成が確立された。
3. **実機上の検証資材の扱い**:
   - 実機 `/var/lib/strata` に配置された検証用資材（モデルファイル約 64GB、pack 約 1.5GB、計約 67GB）は、現状ルートディスク（200GB）の空き容量が約 96GB あり運用に影響がないため、再検証や必要時の切り替え用に保持している。不要であれば削除可能である。
