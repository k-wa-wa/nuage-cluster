# SPIRE Agent (sshpop + unix workload attestor) を常駐させる NixOS モジュール。
#
# - サーバー側がメモリ CA + 作り捨てデータストア前提のため、data_dir は /run/spire/agent (揮発領域) に置き、
#   再起動時は ExecStartPre で掃除して insecure_bootstrap = true で再アテストする。
# - sshpop が読むホスト秘密鍵 (/var/lib/nix-provisioning/ssh_host_ed25519_key, 0600 root:root) は
#   systemd の LoadCredential で安全なクレデンシャル領域に読み込み、spire-agent ユーザーのまま参照する。
# - ホスト証明書がまだ git に置かれていない間もビルド・起動を落とさないよう ConditionPathExists で待つ。
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.nuage.spireAgent;
  dataDir = "/run/spire/agent";
  socketDir = builtins.dirOf cfg.socketPath;

  agentConf = pkgs.writeText "spire-agent.conf" ''
    agent {
      data_dir = "${dataDir}"
      log_level = "${cfg.logLevel}"
      server_address = "${cfg.serverAddress}"
      server_port = "${toString cfg.serverPort}"
      socket_path = "${cfg.socketPath}"
      trust_domain = "${cfg.trustDomain}"
      insecure_bootstrap = true
    }

    plugins {
      KeyManager "memory" {
        plugin_data {}
      }

      NodeAttestor "sshpop" {
        plugin_data {
          host_key_path = "$CREDENTIALS_DIRECTORY/ssh_host_ed25519_key"
          host_cert_path = "${cfg.hostCertPath}"
        }
      }

      WorkloadAttestor "unix" {
        plugin_data {}
      }
    }
  '';
in
{
  options.services.nuage.spireAgent = {
    enable = lib.mkEnableOption "SPIRE Agent (sshpop + unix)";

    package = lib.mkPackageOption pkgs "spire-agent" { };

    trustDomain = lib.mkOption {
      type = lib.types.str;
      default = "nuage";
      description = "SPIFFE trust domain";
    };

    serverAddress = lib.mkOption {
      type = lib.types.str;
      default = "spire.wpcapp.net";
      description = "接続先 SPIRE Server のホスト名または IP";
    };

    serverPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "接続先 SPIRE Server のポート";
    };

    socketPath = lib.mkOption {
      type = lib.types.path;
      default = "/run/spire/sockets/agent.sock";
      description = "Workload API ソケットのパス";
    };

    hostKeyPath = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/nix-provisioning/ssh_host_ed25519_key";
      description = "sshpop ノードアテステーションに使う SSH ホスト秘密鍵のパス";
    };

    hostCertPath = lib.mkOption {
      type = lib.types.path;
      description = "sshpop ノードアテステーションに使う署名済み SSH ホスト証明書のパス";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "debug"
        "info"
        "warn"
        "error"
      ];
      default = "info";
      description = "SPIRE Agent のログレベル";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.spire-agent = {
      isSystemUser = true;
      group = "spire-agent";
    };
    users.groups.spire-agent = { };

    systemd.tmpfiles.rules = [
      "d /run/spire 0755 root root - -"
      "d ${dataDir} 0700 spire-agent spire-agent - -"
      "d ${socketDir} 0750 spire-agent spire-agent - -"
    ];

    systemd.services.spire-agent = {
      description = "SPIRE Agent (sshpop + unix)";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "systemd-tmpfiles-setup.service"
      ];
      wants = [ "network-online.target" ];

      unitConfig = {
        ConditionPathExists = [
          cfg.hostKeyPath
          cfg.hostCertPath
        ];
      };

      serviceConfig = {
        User = "spire-agent";
        Group = "spire-agent";
        LoadCredential = [ "ssh_host_ed25519_key:${cfg.hostKeyPath}" ];
        ExecStartPre = "${pkgs.writeShellScript "spire-agent-prep" ''
          rm -rf ${lib.escapeShellArg dataDir}/*
          rm -f ${lib.escapeShellArg cfg.socketPath}
        ''}";
        ExecStart = "${lib.getExe' cfg.package "spire-agent"} run -expandEnv -config ${agentConf}";
        Restart = "always";
        RestartSec = "5s";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          dataDir
          socketDir
        ];
      };
    };
  };
}
