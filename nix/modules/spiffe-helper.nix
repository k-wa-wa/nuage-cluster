# spiffe-helper により Workload API から JWT-SVID を取得・更新してファイルへ書き出す NixOS モジュール。
#
# 呼び出し元アプリが Workload API ソケットへ直接触れて任意の aud を発行できないよう、
# 専用 OS ユーザーで spiffe-helper を動かし、書き出す JWT ファイルだけを制限付きグループで読めるようにする。
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.nuage.spiffeHelpers;
  defaultSpiffeHelperPkg = pkgs.callPackage ../pkgs/spiffe-helper { };
  escapeHclString = s: ''"${lib.escape [ "\\" "\"" ] s}"'';

  renderJwtSvid =
    entry:
    let
      extra = lib.concatMapStringsSep ", " escapeHclString entry.extraAudiences;
    in
    ''
      {
        jwt_audience = ${escapeHclString entry.audience}
        ${lib.optionalString (entry.extraAudiences != [ ]) "jwt_extra_audiences = [${extra}]"}
        jwt_svid_file_name = ${escapeHclString entry.fileName}
      }'';

  mkHelperConfig =
    name: inst:
    let
      jwtList = lib.concatMapStringsSep ",\n  " renderJwtSvid inst.jwtSvids;
    in
    pkgs.writeText "spiffe-helper-${name}.conf" ''
      agent_address = ${escapeHclString inst.agentAddress}
      cert_dir = ${escapeHclString inst.outputDir}
      jwt_svid_file_mode = ${inst.fileMode}
      daemon_mode = true

      jwt_svids = [
        ${jwtList}
      ]
    '';

  instanceOpts =
    { name, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "この spiffe-helper インスタンスを有効化する";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = defaultSpiffeHelperPkg;
          defaultText = lib.literalExpression "pkgs.callPackage ../pkgs/spiffe-helper { }";
          description = "使用する spiffe-helper パッケージ (v0.12.4 以上)";
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "spiffe-helper を実行する専用 OS ユーザー名";
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "出力ファイルの所有グループ (読み取りを許可するユーザーをこのグループに含める)";
        };

        createUser = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "専用システムユーザーおよびグループを自動作成する";
        };

        extraGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "spire-agent" ];
          description = "実行ユーザーに付与する補助グループ (Workload API ソケット参照用に spire-agent を含む)";
        };

        agentAddress = lib.mkOption {
          type = lib.types.path;
          default = "/run/spire/sockets/agent.sock";
          description = "SPIRE Agent Workload API ソケットのパス";
        };

        outputDir = lib.mkOption {
          type = lib.types.path;
          default = "/run/${name}";
          description = "JWT-SVID ファイルを書き出すディレクトリ";
        };

        dirMode = lib.mkOption {
          type = lib.types.str;
          default = "0750";
          description = "出力ディレクトリのパーミッション";
        };

        fileMode = lib.mkOption {
          type = lib.types.str;
          default = "0640";
          description = "書き出す JWT-SVID ファイルの 8 進数パーミッション (HCL 記述)";
        };

        conditionPathExists = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "systemd の ConditionPathExists に渡す前提ファイル群";
        };

        jwtSvids = lib.mkOption {
          description = "取得・更新する JWT-SVID の一覧";
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                audience = lib.mkOption {
                  type = lib.types.str;
                  description = "JWT-SVID の aud クレーム";
                };
                extraAudiences = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "追加の aud クレーム";
                };
                fileName = lib.mkOption {
                  type = lib.types.str;
                  description = "outputDir 配下に出力するファイル名";
                };
              };
            }
          );
          default = [ ];
        };
      };
    };

  enabledHelpers = lib.filterAttrs (_: inst: inst.enable && inst.jwtSvids != [ ]) cfg;
in
{
  options.services.nuage.spiffeHelpers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule instanceOpts);
    default = { };
    description = "インスタンスごとの spiffe-helper 設定";
  };

  config = lib.mkIf (enabledHelpers != { }) {
    users.users = lib.mkMerge (
      lib.mapAttrsToList (
        _: inst:
        lib.mkIf inst.createUser {
          ${inst.user} = {
            isSystemUser = true;
            group = inst.group;
            extraGroups = inst.extraGroups;
          };
        }
      ) enabledHelpers
    );

    users.groups = lib.mkMerge (
      lib.mapAttrsToList (
        _: inst:
        lib.mkIf inst.createUser {
          ${inst.group} = { };
        }
      ) enabledHelpers
    );

    systemd.tmpfiles.rules = lib.mapAttrsToList (
      _: inst: "d ${inst.outputDir} ${inst.dirMode} ${inst.user} ${inst.group} -"
    ) enabledHelpers;

    systemd.services = lib.mapAttrs' (
      name: inst:
      let
        conf = mkHelperConfig name inst;
        expectedFileNames = map (j: j.fileName) inst.jwtSvids;
        cleanupStaleScript = pkgs.writeShellScript "spiffe-helper-${name}-prep" ''
          set -euo pipefail
          dir=${lib.escapeShellArg inst.outputDir}
          [ -d "$dir" ] || exit 0
          for f in "$dir"/*.jwt; do
            [ -e "$f" ] || continue
            base=$(basename "$f")
            keep=false
            case "$base" in
              ${lib.concatMapStringsSep "\n              " (
                fn: "${lib.escapeShellArg fn}) keep=true ;;"
              ) expectedFileNames}
            esac
            if [ "$keep" = "false" ]; then
              rm -f "$f"
            fi
          done
        '';
      in
      lib.nameValuePair "spiffe-helper-${name}" {
        description = "SPIFFE Helper (${name})";
        wantedBy = [ "multi-user.target" ];
        after = [
          "spire-agent.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "spire-agent.service" ];

        unitConfig = lib.mkIf (inst.conditionPathExists != [ ]) {
          ConditionPathExists = inst.conditionPathExists;
        };

        serviceConfig = {
          User = inst.user;
          Group = inst.group;
          SupplementaryGroups = inst.extraGroups;
          # 0640 出力時にグループ読み取りビットが削られないよう UMask は 0027 とする
          UMask = "0027";
          ExecStartPre = cleanupStaleScript;
          ExecStart = "${lib.getExe inst.package} -config ${conf}";
          Restart = "always";
          RestartSec = "5s";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ inst.outputDir ];
        };
      }
    ) enabledHelpers;
  };
}
