{ config, pkgs, ... }:

# MVS の中の設定 (PDS のメンバー) を Git で宣言的に管理する。
#
# mvs-config/<データセット名>/<メンバー名> のファイルが「あるべき姿」である。
# IPL のたびと、この内容が変わったときに mvs-config.service が IEBUPDTE ジョブで書き込む。
#   - 毎回書き込むため、TSO から手で変えても次の IPL で Git の内容に戻る (自己修復)
#   - 再 IPL しないと効かないもの (SYS1.PARMLIB) が前回から変わっていれば、続けて再 IPL する
# 書き込みには管理者ユーザーの権限が要る (RAKF により、ユーザー指定なしのジョブは S913 で拒否される)

let
  mvsctl = pkgs.callPackage ./tools/mvsctl.nix { };
  adminUser = "IBMUSER";
in
{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/nix-provisioning/sops-key";
    secrets.mvs_admin_password = { };
  };

  systemd.services.mvs-config = {
    description = "Apply Git-managed MVS settings";
    # hercules の起動・再起動のたびに一緒に動かす。
    # multi-user.target にも紐付け、初回の switch で新規 unit として確実に起動させる
    wantedBy = [
      "hercules.service"
      "multi-user.target"
    ];
    partOf = [ "hercules.service" ];
    after = [ "hercules.service" ];
    serviceConfig = {
      Type = "oneshot";
      # 設定が変わった switch で再実行されるよう、完了後も active として残す
      RemainAfterExit = true;
      ExecStart = "${mvsctl}/bin/mvsctl apply-config ${./mvs-config} --user ${adminUser} --password-file ${config.sops.secrets.mvs_admin_password.path}";
      TimeoutStartSec = 900;
    };
  };

  environment.systemPackages = [ mvsctl ];
}
