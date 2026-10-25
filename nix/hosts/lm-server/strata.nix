{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.services.strata;

  configFile = pkgs.writeText "strata.json" (
    builtins.toJSON {
      exe = "${cfg.package}/bin/strata";
      args = [
        "--pack"
        (toString cfg.packDir)
        "--native"
        "${toString cfg.modelDir}/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf"
        "--ple-gguf"
        "${toString cfg.modelDir}/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00002-of-00002.gguf"
      ]
      ++ lib.optionals (cfg.expertProfile != null) [
        "--expert-profile"
        (toString cfg.expertProfile)
      ]
      ++ [
        "--expert-cache"
        "auto"
        "--prefill"
        "2048"
        "--spec"
        "3"
        "--spec-min-p"
        "0.9"
        "--max-context"
        (toString cfg.maxContext)
        "--kv"
        "q4_0"
        "--kv-resident"
        "20480"
        "--mmap-experts"
      ];
      env = {
        STRATA_HIP_PROMPT_F16 = "1";
        STRATA_WMMA_GEMM = "1";
        STRATA_PF_GEMM = "1";
      };
      cwd = "/var/lib/strata";
      tokenizer = "${toString cfg.packDir}/tokenizer";
      model_name = cfg.modelName;
      log = "/var/lib/strata/strata-engine.log";
      lib_dirs = [
        "${cfg.package}/lib/strata"
      ];
      host = cfg.host;
      port = cfg.port;
    }
  );
in
{
  options.services.strata = {
    enable = lib.mkEnableOption "Strata local AI inference engine and OpenAI-compatible API server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./pkgs/strata.nix { };
      description = "Strata パッケージ。";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "リッスンするホストアドレス。";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8085;
      description = "OpenAI 互換 API のリッスンポート。";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "ポートをファイアウォールで開放するかどうか。認証なしの場合は信頼されたネットワーク内のみに限定すること。";
    };

    modelName = lib.mkOption {
      type = lib.types.str;
      default = "qwen3.8-flash-next";
      description = "API 上で提供するモデル識別名。";
    };

    modelDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/strata/models/IQ2_XS";
      description = "GGUF モデルシャードの配置ディレクトリ。";
    };

    packDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/strata/packs/iq2_xs";
      description = "展開済み pack ディレクトリ。";
    };

    expertProfile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = "${cfg.package}/share/strata/data/expert-profile.bin";
      description = "エキスパートプロファイルファイル。null の場合は未指定。";
    };

    maxContext = lib.mkOption {
      type = lib.types.int;
      default = 32768;
      description = "最大コンテキスト長（トークン数）。";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.strata = {
      description = "Strata MoE Inference Engine (Qwen3.8-Flash-Next)";
      after = [ "network.target" ];
      # llama-cpp と VRAM (15.5GB) を奪い合うため排他とする
      conflicts = [ "llama-cpp.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        # gfx1102 (Radeon RX 7600 XT) 向け最適化
        STRATA_HIP_PROMPT_F16 = "1";
        STRATA_WMMA_GEMM = "1";
        STRATA_PF_GEMM = "1";
      };

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        SupplementaryGroups = [
          "render"
          "video"
        ];
        StateDirectory = "strata";
        WorkingDirectory = "/var/lib/strata";
        PrivateDevices = false; # GPU デバイス (/dev/kfd, /dev/dri/*) にアクセスするために必要
        ExecStart = "${cfg.package}/bin/strata-server --engine strata --config ${configFile} --host ${cfg.host} --port ${toString cfg.port}";
        Restart = "always";
        RestartSec = "10s";
        LimitMEMLOCK = "infinity";
      };
    };
  };
}
