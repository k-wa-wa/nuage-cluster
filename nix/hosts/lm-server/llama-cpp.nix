{ llamaCppPkgs, ... }:

let
  # GPU (Radeon RX 7600 XT, gfx1102, VRAM 16GB) に全層を載せられるサイズを選ぶ。
  # Qwen3.8-27B は 64 層中 16 層のみ full attention のため KV キャッシュが小さく、
  # UD-Q3_K_XL (13.1GB) + 32K コンテキストで VRAM に収まる。
  # Qwen3.8-Flash-Next (125B MoE) は最小でも 75GB のメモリが必要なため載らない。
  modelName = "qwen3.8-27b";
  model = llamaCppPkgs.fetchurl {
    name = "Qwen3.8-27B-UD-Q3_K_XL.gguf";
    url = "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-Q3_K_XL.gguf";
    sha256 = "8c2a45ff85e7674ca185ec8eb6cdeab0e617ed9d8018caed0b64380eb2a67a5e";
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
      # GPU を認識できない場合に CPU で黙って動かず、起動失敗として検知できるようにする。
      # 初回ブートストラップ直後は amdgpu のファームウェアが未ロードのため再起動が必要になる。
      "--device"
      "ROCm0"
      "--n-gpu-layers"
      "999"
      "--ctx-size"
      "32768"
      # 利用者は holmesgpt のみのため、KV キャッシュをスロット分割せず 1 本に割り当てる
      "--parallel"
      "1"
      "--flash-attn"
      "on"
      "--metrics"
    ];
  };
}
