# atelier の SPIRE Agent (sshpop) と spiffe-helper (bot 用 JWT-SVID ファイル出力) を定義する。
#
# - 本番用の aud (monitoring-pwa) は常に /run/monitoring-bot-token/monitoring-pwa.jwt へ書き出す。
# - PR preview 用に繋ぎたいときだけ nuage.atelier.spire.previewPrNumber を指定すると、
#   /run/monitoring-bot-token/monitoring-pwa-preview.jwt (aud=monitoring-pwa.nuage-monitoring-stack-pr-<N>) も併せて書き出す。
# - ホスト証明書 (./atelier-cert.pub) がまだ git に置かれていない間は /etc/spire/atelier-cert.pub を生成せず、
#   systemd の ConditionPathExists により起動だけ待機させる (nix build / CI は通る)。
{
  config,
  lib,
  ...
}:

let
  cfg = config.nuage.atelier.spire;
  certFile = ./atelier-cert.pub;
  hasCert = builtins.pathExists certFile;
  hostCertPath = "/etc/spire/atelier-cert.pub";
in
{
  imports = [
    ../../modules/spire-agent.nix
    ../../modules/spiffe-helper.nix
  ];

  options.nuage.atelier.spire = {
    previewPrNumber = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "nuage-monitoring-stack の PR preview 環境向け JWT-SVID を追加出力する場合の PR 番号";
    };
  };

  config = {
    environment.etc = lib.mkIf hasCert {
      "spire/atelier-cert.pub".source = certFile;
    };

    services.nuage.spireAgent = {
      enable = true;
      inherit hostCertPath;
    };

    services.nuage.spiffeHelpers.monitoring-bot-token = {
      user = "monitoring-bot-token";
      group = "monitoring-bot-token";
      outputDir = "/run/monitoring-bot-token";
      fileMode = "0640";
      conditionPathExists = [ hostCertPath ];
      jwtSvids = [
        {
          audience = "monitoring-pwa";
          fileName = "monitoring-pwa.jwt";
        }
      ]
      ++ lib.optional (cfg.previewPrNumber != null) {
        audience = "monitoring-pwa.nuage-monitoring-stack-pr-${toString cfg.previewPrNumber}";
        fileName = "monitoring-pwa-preview.jwt";
      };
    };

    # nuage-autopilot5 の bot を動かす nixos ユーザーだけに JWT ファイルの読み取りを許す。
    # nixos には spire-agent グループを付けないため、Workload API ソケットへの直接接続は防がれる。
    users.users.nixos.extraGroups = [ "monitoring-bot-token" ];
  };
}
