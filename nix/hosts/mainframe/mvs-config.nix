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
# これに業務アプリ (flake.nix の mainframeApps。nuage-usage-ledger など) の資材を合成する。
#   members/<データセット名>/<メンバー名>  そのまま加える
#   schedule                              ZTIMER の予定表 (SYS2.CONTROL(ZTIMER)) の末尾に足す
#   rakf                                  RAKF の権限表 (SYS1.SECURE.CNTL(PROFILES)) に足す行 (任意)
#   datasets.json                         無ければ作るデータセット
#   build/<ジョブ名>                       内容が変わったら流すビルドジョブ (任意。RC 4 まで成功)
# IPL のたびと、この内容が変わったときに mvs-config.service が IEBUPDTE ジョブで書き込む。
#   - 毎回書き込むため、TSO から手で変えても次の IPL で Git の内容に戻る (自己修復)
#   - 再 IPL しないと効かないもの (SYS1.PARMLIB) が前回から変わっていれば、続けて再 IPL する
# 書き込みには管理者ユーザーの権限が要る (RAKF により、ユーザー指定なしのジョブは S913 で拒否される)
#
# 続けて KICKS (CICS 互換のトランザクション処理。kicks.nix) が未導入なら導入し、
# 業務アプリのビルドジョブ (オンラインのプログラムのコンパイル・リンクなど) のうち、
# 前回成功したときから変わったものを流す。ビルドジョブはユーザー指定なし (業務アプリの権限) で動く

let
  mvsctl = pkgs.callPackage ./tools/mvsctl.nix { };
  kicks = pkgs.callPackage ./kicks.nix { };
  adminUser = "IBMUSER";

  mvsConfig = pkgs.runCommand "mvs-config" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 ${./tools/compose_mvs_config.py} $out ${./mvs-config} ${lib.concatStringsSep " " mainframeApps}
  '';

  # 各アプリのビルドジョブを 1 つのディレクトリに集める。ジョブ名 (ファイル名) が重なったら失敗させる
  builds = pkgs.runCommand "mvs-builds" { } ''
    mkdir $out
    for dir in ${lib.concatMapStringsSep " " (app: "${app}/build") mainframeApps}; do
      [ -d "$dir" ] || continue
      for job in "$dir"/*; do
        [ -e "$job" ] || continue
        if [ -e "$out/$(basename "$job")" ]; then
          echo "ビルドジョブの名前が重なっている: $(basename "$job")" >&2
          exit 1
        fi
        cp "$job" $out/
      done
    done
  '';

  # システム (mvs-datasets.json) と各アプリが必要とするデータセットの定義をまとめる。
  # システムの定義が先に来る (別名 NUAGE を、アプリのデータセットより先に作る)
  datasets = pkgs.runCommand "mvs-datasets.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq -s 'add // []' ${./mvs-datasets.json} ${
      lib.concatMapStringsSep " " (app: "${app}/datasets.json") mainframeApps
    } > $out
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
      ExecStart = lib.concatStringsSep " " [
        "${mvsctl}/bin/mvsctl apply-config ${mvsConfig}"
        "--datasets ${datasets}"
        "--kicks-xmi ${kicks}/kicks-tso-v1r5m0.xmi"
        "--builds ${builds}"
        "--user ${adminUser}"
        "--password-file ${config.sops.secrets.mvs_admin_password.path}"
      ];
      # KICKS の導入 (初回だけ) とビルドジョブの分だけ長めに取る
      TimeoutStartSec = 1800;
    };
  };

  environment.systemPackages = [ mvsctl ];
}
