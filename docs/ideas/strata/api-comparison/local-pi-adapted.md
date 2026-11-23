# GPU 2 枚での候補モデルの調査と Qwen3.8-27B-pi-adapted の手元比較 (2026-11-23)

## 1. 目的

server-2 に挿さっている 2 枚の GPU を使って、lm-server を速くするか賢くする余地があるかを調べた。

- Qwen3.8-27B を 2 枚の GPU で速くできるか
- 27B より賢いモデルに変える余地があるか (Project Maya の GLM-5.3-Flash を含む)
- 候補のうち、手元で試せる Qwen3.8-27B-pi-adapted が、今の 27B を上回るか

1〜2 は公開情報の調査、3 は lm-server での実測である。

## 2. 前提の機材

| 項目 | 内容 |
| :-- | :-- |
| GPU | RX 7600 XT (16GB) × 2 枚。2 枚とも同じ機種である (`docs/hardware-inventory.md`) |
| スロット | `0000:05:00` が直挿しで PCIe 3.0 x8 (実測 6.7GB/s)、`0000:06:00` がチップセット経由で 3.2GB/s |
| lm-server が使う GPU | `0000:06:00` の 1 枚だけ (`terraform/vpc/zone-private-k8s/lm-server.tf`)。`0000:05:00` はどの VM にも渡していない |
| lm-server に回せる RAM | server-2 の 64GB のうち、ほかの VM と LXC が terraform の定義で約 34GB を使うため、約 26GB まで |

## 3. 公開情報の調査

### 3.1 GPU 2 枚で 27B は速くなるか

速くならない。27B は全パラメータを毎回使う dense モデルで、llama.cpp で層を 2 枚に分けても、2 枚は順番に動くだけである。1 リクエストの速さは 1 枚の GPU のメモリ帯域で決まる。2 枚目の使いみちは、別のモデルを常駐させるか、量子化を上げるか、文脈を伸ばすことになる。

### 3.2 候補モデル

| モデル | 構造 | 大きさ (Q4 前後) | 評価 | 見送った理由 |
| :-- | :-- | :-- | :-- | :-- |
| Qwen3.8-Flash-Next (Strata 0.2.20) | MoE 125B (6B active) | IQ2_XS 63.4GiB 〜 IQ4_XS 93.7GB | Terminal-Bench 4.0 で 25.3% (27B は 5.6%) | RAM 約 26GB では 2bit 級のままで、精度は上がらない。2 枚の自動分割は NVIDIA か R9700 だけが対象で、gfx1102 は名前が無い |
| GLM-5.3-Flash (Project Maya v1.1.74) | MoE 321B (18B active) | 最小の Maya-XS で 73.4GB | Terminal-Bench 4.0 で 32.8% | VRAM と RAM を合わせても約 58GB で、残りは NVMe から読む。既定の Maya-S は IQ2_XXS で 2bit 級。AMD は実験的で、RX 7600 XT は名前が無い |
| Qwen3.6-35B-A3B | MoE 35B (3B active) | UD-Q4_K_M 22.1GB | llm-stats の Coding 18.5・Agents 10.8 (27B は 28.2・27.9) | 2 枚なら全部載って速いが、一世代前で 27B より明らかに弱い |
| Nanbeige4.3-33B | dense 33B | Q4_K_M 20.8GB | Terminal-Bench 4.0 で 30% と小型モデルで最上位。Intelligence Index は 27B と同じ 20 | dense なので lm-server では約 10 tok/s (推定) と遅く、出力トークンも 27B の約 1.4 倍。実地の試験で考えが止まらなくなる報告があり、公式のチャットテンプレートに誤りが報告されている |
| Inkling 2 Mini | MoE 26B (5.4B active、層を 3 回通す構造) | UD-Q4_K_XL 17.6GB | Intelligence Index は 27B と同じ 20 | llama.cpp の対応が取り込まれていない PR に頼っていて、ROCm では Flash Attention が使えない。AMD での実測は RX 7900 XTX で 30〜63 tok/s で、RX 7600 XT では 10〜20 tok/s と推定する |
| Qwen3.8-27B-pi-adapted | 27B に LoRA (rank 32、F16 で 319MB) を足す | 今の IQ4_XS + 319MB | 開発元の測定で、思考なしのまま SWE-bench Pro を 39.2% → 64.7% に上げ、出力トークンを減らした | 4 章で手元で比べた |

推定の速度は、メモリ帯域の比から割り引いた値で、実測ではない。

## 4. Qwen3.8-27B-pi-adapted の手元比較

### 4.1 条件

| 項目 | 内容 |
| :-- | :-- |
| 実施日 | 2026-11-23 |
| サーバー | lm-server の llama-server (b10408)。今の起動引数に `--lora <アダプタ> --lora-init-without-apply` を足した一時ユニットで動かした |
| アダプタ | `harness-hub/Qwen3.8-27B-pi-adapted-GGUF` の `Qwen3.8-27B-pi-lora-F16.gguf` (sha256 `a64f9184…2d7b67`) |
| 文脈長 | 32K。64K のままでは、アダプタの計算用のメモリを VRAM に確保できずに落ちた |
| 比べた設定 | 素の 27B・思考あり / 素の 27B・思考なし / pi-adapted・思考なし。アダプタの効き具合 (scale 0 か 1) と `enable_thinking` を、リクエストごとに切り替えた |
| 課題と回数 | [README.md](./README.md) 3 章と同じ。A1〜A3・L1・L2 は 1 回、J1 は 3 回、E1 は 2 回 |
| 生成の設定 | temperature 0.6、max_tokens 16000。エージェントの手順の上限は 15 |

素の 27B・思考ありの A3 は、プロンプトが 34,047 トークンになって文脈 32K を超え、失敗した。そこで、アダプタを読み込まない正規の `llama-cpp.service` (文脈 64K) でやり直した。

### 4.2 正確さ

| 課題 | 素の 27B・思考あり | 素の 27B・思考なし | pi-adapted・思考なし |
| :-- | :-- | :-- | :-- |
| A1 | 正解。ただし「起動時にも最大 6 時間の遅れが乗る」と、根拠の無い推測を足した (実機の `nixos-upgrade.timer` は `RandomizedDelaySec=0`) | 正解 | 正解。egress-gateway の時刻を「毎日 (時刻指定なし)」とし、00:00 とまでは書かなかった |
| A2 | 正解 | 正解 | 正解 |
| A3 | 失敗。手順の上限 15 に達し、答えが出なかった | 正解 (6 項目)。15 手順目で答えた | 失敗。1 項目書いたところで途切れた |
| L1 | 原因を当て、Argo CD による Secret の同期と、古い Pod が起動時の値を持ち続けていることまで結びつけた | 原因は正解 | 原因は正解 |
| L2 | 正解 | 正解 | 正解 |
| J1 | 3/3 | 3/3 | 3/3 |
| E1 | 1/2。2 回目は思考に 1.4 万トークンを使い、壊れた diff を出した | 0/2 | 0/2。1 回は当たったが、V キャッシュの `q4_0` を書き換え忘れた |

- L1 は 3 つとも、直し方に `kubectl` での Secret の直接書き換えを挙げた。GitOps に反する。
- pi-adapted の A3 は、テンプレートの中身を引用する途中で終わりの特殊トークン `<|im_end|>` を書き、そこで生成が止まったとみられる。特殊トークンを含むファイルを引用すると起きうる。

### 4.3 トークンと時間

| | 素の 27B・思考あり | 素の 27B・思考なし | pi-adapted・思考なし |
| :-- | :-- | :-- | :-- |
| 出力トークン (10 回の合計) | 84,020 | 8,663 | 5,610 |
| 経過時間 (10 回の合計) | 3,503 秒 | 502 秒 | 365 秒 |
| A1 の手順数 | 11 | 7 | 4 |
| A3 の手順数 | 15 (上限) | 15 | 5 |

- 生成速度は、アダプタを合成しないまま足すと約 14% 落ちた (短い出力で 24.7 → 21.2 tok/s)。
- 約 2 万トークンのプロンプトの読み込みは、アダプタを効かせて 244 tok/s (82 秒) だった。

## 5. 結論

- pi-adapted の正確さは、素の 27B を思考なしで使ったときと同じ程度だった。手順とトークンは減るが、16GB の GPU 1 枚では文脈が 32K に縮み、速度も落ちる。今の 27B は置き換えない。
- 思考を切るだけで、出力トークンは約 10 分の 1、時間は約 7 分の 1 になった。リポジトリ調査・ログ読解・JSON 出力では、正確さはほぼ保たれた。原因を深く読む課題 (L1) と diff の出力 (E1) では、思考ありの方が上だった。
- 2 枚目の GPU で 27B を速くする道は無い。候補モデルも、今の機材では 27B を上回る見込みが立たない。
- 回数は各 1〜3 回なので、差が小さい部分は誤差の範囲である。

## 6. 再実行の手順

lm-server で、正規のユニットの起動引数にアダプタを足した一時ユニットを立てる。

```bash
ssh lm-server 'sudo mkdir -p /var/lib/llama-lora && sudo curl -sSL --fail -o /var/lib/llama-lora/Qwen3.8-27B-pi-lora-F16.gguf https://huggingface.co/harness-hub/Qwen3.8-27B-pi-adapted-GGUF/resolve/main/Qwen3.8-27B-pi-lora-F16.gguf'
ssh lm-server 'EXEC=$(systemctl show llama-cpp -p ExecStart --value | sed -n "s/.*argv\[\]=\([^;]*\);.*/\1/p" | sed "s/--ctx-size 65536/--ctx-size 32768/")
sudo systemctl stop llama-cpp
sudo systemd-run --unit=llama-pi-test -p DynamicUser=yes -p StateDirectory=llama-pi-test -E GGML_CUDA_DISABLE_GRAPHS=1 -E LLAMA_CACHE=/var/lib/llama-pi-test $EXEC --lora /var/lib/llama-lora/Qwen3.8-27B-pi-lora-F16.gguf --lora-init-without-apply'
```

`--lora-init-without-apply` を付けても、サーバー全体の既定の効き具合が 1.0 になっていることがあった。ほかの利用者に素の 27B を返すため、0 に戻しておく。

```bash
ssh lm-server 'curl -s -XPOST localhost:8080/lora-adapters -H "Content-Type: application/json" -d "[{\"id\":0,\"scale\":0}]"'
```

課題を走らせる。引数は、比べる設定名をカンマで並べたもので、2 つ目に課題を絞ることもできる。

```bash
python3 -I docs/ideas/strata/api-comparison/scripts/run_local.py base-think,base-nothink,pi-nothink
```

終わったら一時ユニットを止めて正規のユニットに戻し、アダプタを消す。

```bash
ssh lm-server 'sudo systemctl stop llama-pi-test; sudo systemctl start llama-cpp; sudo rm -r /var/lib/llama-lora'
```

## 7. ファイル

| パス | 内容 |
| :-- | :-- |
| `results-local.jsonl` | 4 章の生の結果。1 行が 1 回の実行で、回答と機械検証の結果を含む。`base-think-nolora` は正規のユニットでやり直した A3 である |
| `calls-local.jsonl` | 4 章の API 呼び出しごとの記録 (トークン数・経過時間・投機的デコードの採択数・終了理由) |
| `scripts/run_local.py` | lm-server に対して課題を走らせるスクリプト |

## 8. 参考

- [Niko1221/Strata Releases](https://github.com/Niko1221/Strata/releases)
- [mw00/project-maya](https://github.com/mw00/project-maya)
- [vramcalculator: Project Maya GLM 5.3 Flash](https://vramcalculator.com/project-maya-glm-5-3-flash/)
- [gpuwerk: Best open-weight coding models, November 2026](https://gpuwerk.com/blog/best-open-weight-coding-models/)
- [Artificial Analysis: Small Open Source Models](https://artificialanalysis.ai/models/open-source/small)
- [Artificial Analysis: Nanbeige4.3-33B](https://artificialanalysis.ai/articles/nanbeige-has-released-nanbeige4-3-33b-scoring-20-on-the-intelligence-index)
- [Artificial Analysis: Inkling 2 Mini](https://artificialanalysis.ai/articles/inkling-2-mini)
- [llm-stats: Qwen3.6-35B-A3B vs Qwen3.8-27B](https://llm-stats.com/models/compare/qwen3.6-35b-a3b-vs-qwen3.8-27b)
- [vettedconsumer: Nanbeige 4.3 33B](https://vettedconsumer.com/nanbeige-4-3-33b-the-dense-model-that-says-it-beats-qwen3-8-27b-and-the-memory-bill-on-a-24gb-card/)
- [Hacker News: Inkling 2 Mini](https://news.ycombinator.com/item?id=50581260)
- [harness-hub/Qwen3.8-27B-pi-adapted-GGUF](https://huggingface.co/harness-hub/Qwen3.8-27B-pi-adapted-GGUF)
- [MindStudio: Qwen3.8-27B Pi Adapter vs Base Model](https://www.mindstudio.ai/blog/qwen3-8-27b-pi-adapter-coding-agent)
