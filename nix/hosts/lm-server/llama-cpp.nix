{ llamaCppPkgs, ... }:

let
  # GPU (Radeon RX 7600 XT, gfx1102, VRAM 16GB) に全層を載せられるサイズを選ぶ。
  # Qwen3.8-27B は 64 層中 16 層のみ full attention のため KV キャッシュが小さく、
  # UD-IQ4_XS (14.3GB) + MTP + 64K コンテキスト (KV キャッシュ q4_0) で VRAM に収まる (実測 15.9GB)。
  # IQ4_XS は UD-Q3_K_XL (13.1GB) と生成速度が同等以上で、重みの精度が高い。
  # Qwen3.8-Flash-Next (125B MoE) は最小でも 75GB のメモリが必要なため載らない。
  modelName = "qwen3.8-27b";
  model = llamaCppPkgs.fetchurl {
    name = "Qwen3.8-27B-UD-IQ4_XS.gguf";
    url = "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-IQ4_XS.gguf";
    sha256 = "40fac4050e940397dbf13087afd50f4734a11805bf9d65ef8ddd7483470e6199";
  };
in
{
  services.llama-cpp = {
    enable = true;
    # ROCm の HIP カーネルは gfx1102 のみビルドしてビルド時間を抑える。
    # 自前ビルドのため Ollama 時代の HSA_OVERRIDE_GFX_VERSION は不要である。
    package = llamaCppPkgs.llama-cpp.override {
      rocmSupport = true;
      rocmGpuTargets = [ "gfx1102" ];
    };
    inherit model;
    host = "0.0.0.0";
    port = 8080;
    openFirewall = true;
    extraFlags = [
      "--alias"
      modelName
      # チャットテンプレート (思考/ツール呼び出しの区切り) を正しく扱うために必須
      "--jinja"
      # GGUF 同梱のテンプレートは先頭以外の system メッセージで例外を投げる。
      # Claude Code は会話の途中に system メッセージ (環境情報) を送るため、
      # その 1 箇所だけを system ブロックとして描画するよう変更したテンプレートを使う。
      "--chat-template-file"
      "${./qwen3.8-chat-template.jinja}"
      # GPU を認識できない場合に CPU で黙って動かず、起動失敗として検知できるようにする。
      # 初回ブートストラップ直後は amdgpu のファームウェアが未ロードのため再起動が必要になる。
      "--device"
      "ROCm0"
      "--n-gpu-layers"
      "999"
      # Claude Code は system prompt とツール定義だけで約 20K トークンを使うため 64K 確保する。
      # IQ4_XS + MTP と両立させるため KV キャッシュを q4_0 に量子化する
      # (q8_0 では 64K・48K ともに VRAM 不足で落ちることを確認済み)。
      "--ctx-size"
      "65536"
      "--cache-type-k"
      "q4_0"
      "--cache-type-v"
      "q4_0"
      # モデル同梱の MTP ヘッドで投機的デコードを行う。生成速度が約 1.6〜2 倍になる
      # (実測 14 → 21〜27 tok/s)。VRAM を約 1.2GB 追加で使う。
      "--spec-type"
      "draft-mtp"
      # VM の RAM は 8GB しかなく、プロンプトキャッシュ (既定 8GiB) とコンテキストチェックポイント
      # (既定 32 個) をホスト RAM に貯めると 60K 級のコンテキストで OOM kill される。
      "--cache-ram"
      "2048"
      "--ctx-checkpoints"
      "8"
      # 同時利用は想定しないため、KV キャッシュをスロット分割せず 1 本に割り当てる
      "--parallel"
      "1"
      "--flash-attn"
      "on"
      "--metrics"
    ];
  };

  # ROCm の HIP Graph を無効化する。MTP の投機的デコードと長いコンテキスト (60K 級) の組み合わせで、
  # 2 回目以降のリクエストの hipGraphExecUpdate 内で SEGV することを再現確認した
  # (llama-cpp b10408 / ROCm 7.2.3)。無効化しても生成速度の低下は見られない。
  systemd.services.llama-cpp.environment.GGML_CUDA_DISABLE_GRAPHS = "1";
}
