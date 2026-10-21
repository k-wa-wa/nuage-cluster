{
  config,
  pkgs,
  lib,
  mainframeApps ? [ ],
  ...
}:

# MVS の中の設定 (PDS のメンバー) を Git で宣言的に管理する。
#
# mvs-config/<データセット名>/<メンバー名> のファイルが「あるべき姿」である (システムの設定)。
# これに業務アプリ (flake.nix の mainframeApps。nuage-usage-report など) の資材を合成する。
#   members/<データセット名>/<メンバー名>  そのまま加える
#   schedule                              ZTIMER の予定表 (SYS2.CONTROL(ZTIMER)) の末尾に足す
#   datasets.json                         無ければ作るデータセット
# IPL のたびと、この内容が変わったときに mvs-config.service が IEBUPDTE ジョブで書き込む。
#   - 毎回書き込むため、TSO から手で変えても次の IPL で Git の内容に戻る (自己修復)
#   - 再 IPL しないと効かないもの (SYS1.PARMLIB) が前回から変わっていれば、続けて再 IPL する
# 書き込みには管理者ユーザーの権限が要る (RAKF により、ユーザー指定なしのジョブは S913 で拒否される)

let
  mvsctl = pkgs.callPackage ./tools/mvsctl.nix { };
  adminUser = "IBMUSER";

  mvsConfig = pkgs.runCommand "mvs-config" { } ''
    cp -r ${./mvs-config} $out
    chmod -R u+w $out
    ${lib.concatMapStrings (app: ''
      cp -r ${app}/members/. $out/
      chmod -R u+w $out
      cat ${app}/schedule >> $out/SYS2.CONTROL/ZTIMER
    '') mainframeApps}
    # 予定表の末尾をコメント行で閉じる (MVS/CE の既定の形に合わせる)
    echo '*' >> $out/SYS2.CONTROL/ZTIMER
  '';

  # 各アプリが必要とするデータセットの定義をまとめる
  datasets = pkgs.runCommand "mvs-datasets.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq -s 'add // []' ${
      lib.concatMapStringsSep " " (app: "${app}/datasets.json") mainframeApps
    } /dev/null > $out
  '';
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
      ExecStart = "${mvsctl}/bin/mvsctl apply-config ${mvsConfig} --datasets ${datasets} --user ${adminUser} --password-file ${config.sops.secrets.mvs_admin_password.path}";
      TimeoutStartSec = 900;
    };
  };

  environment.systemPackages = [ mvsctl ];
}
