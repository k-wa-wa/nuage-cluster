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
      ]
      ++ lib.optionals (cfg.pleRowCache != null) [
        "--ple-row-cache"
        (toString cfg.pleRowCache)
      ]
      ++ lib.optionals (cfg.pleIo != "direct") [
        "--ple-io"
        cfg.pleIo
      ]
      ++ lib.optional (!cfg.resident) "--mmap-experts";
      cwd = "/var/lib/strata";
      tokenizer = "${toString cfg.packDir}/tokenizer";
      model_name = cfg.modelName;
      log = "/var/lib/strata/strata-engine.log";
      lib_dirs = [
        "${cfg.package}/lib/strata"
      ];
      allowed_hosts = cfg.allowedHosts;
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

    allowedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "*" ];
      description = "API サーバーが受け付ける Host ヘッダ一覧（DNS rebinding 対策）。クラスタ内通信（k8s サービス名や IP 経由）の 403 回避のため [*] を既定値とする。";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "API 認証キーを含む EnvironmentFile のパス (STRATA_API_KEY=... を記載)。null の場合は認証なし。Nix store やプロセス引数への漏洩を防ぐためファイル経由で渡す。";
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

    resident = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "全エキスパート（約 33GiB）を RAM に完全常駐させるかどうか。true の場合は --mmap-experts を外して物理メモリに常駐させ、ディスク I/O 待ちを 0 にして高速推論を行う。RAM が 48GB 未満などで不足する場合は false（mmap 有効）にする。なお、RAM 不足時はエンジンが警告を出して自動的に mmap フォールバックを行うため、常駐が正しく機能しているかは /var/lib/strata/strata-engine.log に `expert arena: resident` が出力されていることで確認できる。";
    };

    pleRowCache = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 50000000;
      description = "PLE 行キャッシュ数（90B/行）。既定値の 1048576（約 90MB）から 50,000,000（約 4.2GiB）に拡大することで、SSD ランダムリードを大幅に削減し初動を高速化する。";
    };

    pleIo = lib.mkOption {
      type = lib.types.enum [
        "direct"
        "mmap"
        "ram"
      ];
      default = "direct";
      description = "PLE N-gram テーブルの読み出し方式。direct（SSD 直接読み出し）、mmap（ページキャッシュ利用）、ram（完全 RAM 固定）。";
    };
  };

  config = lib.mkIf cfg.enable {
    # 同一 GPU (VRAM 16GB) を共有できないため、Strata 有効時は llama-cpp を自動で無効化する
    services.llama-cpp.enable = lib.mkForce false;

    environment.systemPackages = [ cfg.package ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    users.users.strata = {
      isSystemUser = true;
      group = "strata";
      extraGroups = [
        "render"
        "video"
      ];
      description = "Strata inference service user";
    };

    users.groups.strata = {
      members = [ "agent" ];
    };

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
        User = "strata";
        Group = "strata";
        SupplementaryGroups = [
          "render"
          "video"
        ];
        StateDirectory = "strata";
        StateDirectoryMode = "0775";
        WorkingDirectory = "/var/lib/strata";
        PrivateDevices = false; # GPU デバイス (/dev/kfd, /dev/dri/*) にアクセスするために必要
        EnvironmentFile = lib.optional (cfg.apiKeyFile != null) cfg.apiKeyFile;
        ExecStart = "${cfg.package}/bin/strata-server --engine strata --config ${configFile} --host ${cfg.host} --port ${toString cfg.port}";
        Restart = "always";
        RestartSec = "10s";
        LimitMEMLOCK = "infinity";
      };
    };
  };
}
