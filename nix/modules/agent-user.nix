# atelier のエージェントが SSH で入って調査するためのユーザー。
#
# 権限は Mac の nixos ユーザー (wheel・パスワードなし sudo) より狭くし、k8s の read-only SA
# (manifests/apps/autopilot/) と同じ位置付けにする。できるのは読み取り (全ユニットの journalctl を含む) と、
# master の構成を反映するだけの nixos-upgrade の起動に限る。sops-nix の secrets は読めない。
#
# 鍵は Mac で scripts/setup-atelier-ssh-key.sh が作り、公開鍵を atelier-agent.pub に書き出す。
# ファイルが無ければ評価をエラーにする (既定値で黙って続けない)。
{ lib, ... }:

let
  systemctl = "/run/current-system/sw/bin/systemctl";
in
{
  users.users.agent = {
    isNormalUser = true;
    extraGroups = [ "systemd-journal" ];
    hashedPassword = "!";
    # 鍵は atelier の 2 本の足 (prvmain・LAN) からだけ使え、転送はすべて禁じる。
    openssh.authorizedKeys.keys = [
      ''restrict,pty,from="10.20.1.52,192.168.5.252" ${lib.trim (builtins.readFile ./atelier-agent.pub)}''
    ];
  };

  # 引数まで固定した完全一致で、root としての nixos-upgrade の起動だけを許す。
  # sudo は PATH から解決した systemctl (/run/current-system/sw/bin/systemctl) をこのパスと突き合わせる。
  security.sudo.extraRules = [
    {
      users = [ "agent" ];
      runAs = "root";
      commands = [
        {
          command = "${systemctl} start nixos-upgrade";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${systemctl} start nixos-upgrade.service";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
