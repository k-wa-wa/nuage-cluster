{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.services.strata;
in
{
  options.services.strata = {
    enable = lib.mkEnableOption "Strata local AI inference engine";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./pkgs/strata.nix { };
      description = "Strata パッケージ。";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8085;
      description = "OpenAI 互換 API のリッスンポート。";
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
  };

  config = lib.mkIf cfg.enable {
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        rocmPackages.clr.icd
      ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    systemd.services.strata = {
      description = "Strata MoE Inference Engine (Qwen3.8-Flash-Next)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        # gfx1102 (Radeon RX 7600 XT) 向け最適化
        STRATA_HIP_PROMPT_F16 = "1";
        STRATA_WMMA_GEMM = "1";
        STRATA_PF_GEMM = "1";
      };

      serviceConfig = {
        Type = "simple";
        User = "agent";
        Group = "users";
        WorkingDirectory = "/var/lib/strata";
        ExecStart = ''
          ${cfg.package}/bin/strata --serve \
            --pack ${cfg.packDir} \
            --native ${cfg.modelDir}/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf \
            --ple-gguf ${cfg.modelDir}/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00002-of-00002.gguf \
            --expert-profile /var/lib/strata/data/expert-profile.bin \
            --expert-cache auto \
            --prefill 2048 \
            --spec 3 \
            --spec-min-p 0.9 \
            --max-context 32768 \
            --kv q4_0 \
            --kv-resident 20480 \
            --mmap-experts
        '';
        Restart = "always";
        RestartSec = "10s";
        LimitMEMLOCK = "infinity";
      };
    };
  };
}
