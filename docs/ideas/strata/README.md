# Strata による Qwen3.8-Flash-Next (125B MoE) 運用構想と検証知見

## 1. 背景と目的

AMD Radeon RX 7600 XT（Navi 33 / `gfx1102`、16GB VRAM）および 48GB/64GB RAM を搭載したコンシューマハードウェア環境において、超大規模 MoE モデル「Qwen3.8-Flash-Next（125B MoE / 6B active）」をオフロード実行する検証を行った。

単一の 16GB GPU では通常 125B 級のモデルを保持できないが、推論エンジン「Strata 0.2」のエキスパートオフロード機構（ホスト RAM への全エキスパート常駐 + VRAM キャッシュ + 投機的デコード MTP）を活用することで、Sonnet / Opus 級の推論能力をローカル環境で実用的な速度で稼働させることを目指した。

## 2. 検証実績とパフォーマンス成果

### 2.1 RAM 40.7GB 常駐（Resident Expert Arena）
- 当初の 32GB RAM / 仮想ディスク mmap 構成では、ストレージ I/O 待ちが全生成時間の約 54% を占有していた。
- ホスト RAM を 48GB に拡張し、`resident = true`（`--mmap-experts` 削除）を適用したことで、全エキスパート（約 33.02 GiB）を物理 RAM に完全常駐させた。
- ディスクからのオンデマンド読み出しが完全ゼロ（0%）となり、プロセス常駐メモリ約 35.8 GiB、システム全体で約 40.7GB を常駐させて OOM なく安定稼働した。

### 2.2 推論速度 20〜30 tok/s の達成
- GPU をマザーボード直挿しスロットへ切り替え、PCIe 3.0 x8 フル帯域（実測 6.703 GB/s）を確保した。
- これにより、初回プロンプト処理（TTFT）は 5,239 ms から **1,410 ms (46.8 tok/s)** へ 3.7 倍高速化し、トークン生成速度も **21.2〜22.9 tok/s（ピーク 23.5 tok/s）** を記録した。
- 現行の単一 GPU 全層常駐モデル `Qwen3.8-27B`（実測 22.41 tok/s）と同等の生成速度で 125B 級 MoE モデルが稼働することを実証した。

### 2.3 PLE 行キャッシュ拡大による初動 SSD I/O の劇的改善
- PLE（Predictive Layer Expert）行キャッシュを既定値の 1,048,576 行（約 90MB）から **50,000,000 行（約 4.2GB）** へ拡大した（`pleRowCache = 50000000`）。
- N-gram テーブルの SSD ランダムアクセスを大幅に削減し、初回プロンプト処理時の I/O ボトルネックを劇的に改善した。

## 3. 採用見送りの根本理由

性能面・速度面では目標水準に達したものの、エージェントコーディングや実務 CLI ツール（Aider, Claude Code）との実用適合性検証において、以下の致命的な課題が判明したため本番採用を見送った。

### 3.1 2bit 極限圧縮 (IQ2_XS) の量子化歪み
- 自然言語の一般的な対話や解説では流暢な日本語・英語を生成するが、コード差分・障害ログ・例外スタックトレース・シンボル名といった記号や構造化テキストが混在するコンテキストにおいて、アテンションが局所的に崩壊する。
- 特に構文木やインデント、特殊文字の整合性が極めて重要なコーディングタスクにおいて、無効な構文の出力や編集箇所の誤認が多発し、実用的なコード生成精度を維持できない。

### 3.2 Thinking モデル特有の思考ループ（ウロボロスループ）
- 推論過程（`<thought>` トレース）を出力するモデル構造において、Aider や Claude Code のメタ指示・プロンプトテンプレート（システムプロンプトや編集形式指示）を誤認・過剰解釈する。
- 自身の推論ステップ内で同じメタ指示を反芻・再解釈し続け、万単位のトークンを消費しながら終了条件を満たせないウロボロスループ（思考の無限堂々巡り）に陥る。

### 3.3 実務 CLI ツールとの適合性の乖離
- **Claude Code**:
  - システムプロンプトおよびツール定義等により、初回の入力コンテキストが約 2.4 万トークンに達する。
  - Strata における 2.4 万トークンの Prefill 処理は 70 秒以上の遅延（Prefill レイテンシ）を要し、インタラクティブな開発体験として非実用的である。
- **Aider**:
  - リポジトリの AST マップを活用することで初回コンテキストを約 1,000 トークン程度に軽量化でき、Prefill レイテンシの面はクリアできる。
  - しかし、Aider が要求する正確なコード編集・diff 適用・文脈把握には最低でも 4bit 以上の精度（Qwen 27B や GLM-4-9B 等）が必須であり、IQ2_XS の精度低下と Thinking ループにより実タスクを完遂できない。

## 4. 本番構成の決定（llama-cpp + Qwen3.8-27B の維持）

本番の `lm-server` では、単一 GPU (16GB VRAM) に全層を常駐させられる `llama-cpp` + `Qwen3.8-27B-UD-IQ4_XS` 構成を維持する。

4bit 量子化による高いコード理解力・正確な diff 編集能力、MTP（ドラフト推論）による 21〜27 tok/s の高速生成、HIP Graph 無効化による長文コンテキスト（64K）の安定動作が確認されており、コーディングエージェント用途として最も実用的である。

## 5. 再訪条件

以下のいずれかの条件が揃った場合に、本ディレクトリの資産を再訪・再活用する：

1. **メモリ増設**:
   - ホスト RAM を 64GB〜128GB へ増設し、3bit〜4bit（IQ3_XXS, IQ4_XS 等）の高ビット量子化 MoE モデルを全層常駐させられる環境が整った場合。
2. **新規モデルの登場**:
   - 2bit〜3bit 量子化でもコード理解力やアテンション精度を損なわない新アーキテクチャの MoE モデル、または Thinking ループに陥らない非 Thinking 型 MoE モデルが登場した場合。
3. **推論エンジンの進化**:
   - Prefill の更なる高速化、GPU / CPU 間の非同期オーバーラップ転送の最適化、または prompt caching / prefix caching の実装により、大規模コンテキストの Prefill 遅延が大幅に短縮された場合。
4. **ホスト CPU の PCIe 4.0 化**:
   - ホスト CPU を Vermeer（Ryzen 5 5600, Ryzen 9 5900XT 等）へ換装し、PCIe 帯域が 13〜14 GB/s へ倍増した場合。

## 6. 利用手順（再導入手順）

本ディレクトリに保管されているモジュールおよびパッケージ定義を用いて、Strata を NixOS 上で再稼働させる手順：

### 6.1 NixOS 設定への組み込み
本ディレクトリの `strata.nix` を NixOS 設定に取り込む：

```nix
imports = [
  ./docs/ideas/strata/strata.nix
];

services.strata = {
  enable = true;
  package = pkgs.callPackage ./docs/ideas/strata/pkgs/strata.nix { };
  port = 8085;
  resident = true;
  pleRowCache = 50000000;
  pleIo = "direct";
};
```

### 6.2 モデル GGUF のダウンロード
`/var/lib/strata/models/IQ2_XS` に Shard 1 および Shard 2 を配置する：

```bash
mkdir -p /var/lib/strata/models/IQ2_XS
cd /var/lib/strata/models/IQ2_XS

# Shard 1 (36.5 GiB / 39.2 GB)
aria2c -s 8 -x 8 -k 1M -c "https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF/resolve/main/IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf"

# Shard 2 (26.8 GiB / 28.8 GB)
aria2c -s 8 -x 8 -k 1M -c "https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF/resolve/main/IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00002-of-00002.gguf"
```

### 6.3 Pack の生成
`strata-pack` ツールを用いて、GGUF から pack (`dense.bin` および tokenizer) を作成する：

```bash
strata-pack \
  --gguf /var/lib/strata/models/IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf \
  --out /var/lib/strata/packs/iq2_xs
```

### 6.4 関連ドキュメント
- ハードウェアプロファイルや詳細なレイテンシ内訳、ボトルネック逆算モデルについては `docs/operations/strata-evaluation.md` を参照すること。
