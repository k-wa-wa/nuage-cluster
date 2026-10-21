{ pkgs, ... }:

# Hercules (メインフレームのエミュレータ) の上で MVS/CE を常駐させる。
#
# Linux 側から見た入口と出口:
#   - ジョブの投入: カードリーダ 127.0.0.1:3505 に JCL を流し込む (mvs-submit)
#   - ジョブの結果: 1403 プリンタ = /var/lib/mainframe/printers/prt00e.txt に追記される
#   - オペレータ操作: /run/mainframe/console (FIFO) に 1 行書くと Hercules のコマンドになる (mvs-console)
#   - コンソールの表示: journalctl -u hercules
#   - 対話操作 (TSO): TN3270 の 3270 番ポート

let
  mvsce = pkgs.callPackage ./mvsce.nix { };
  stateDir = "/var/lib/mainframe";
  consoleFifo = "/run/mainframe/console";

  # JCL をカードリーダへ流し込む。引数のファイル (省略時は標準入力) を 1 デッキとして送る
  mvs-submit = pkgs.writeShellApplication {
    name = "mvs-submit";
    text = ''
      cat -- "$@" > /dev/tcp/127.0.0.1/3505
    '';
  };

  # Hercules のコンソールにコマンドを 1 行送る。先頭が / なら MVS のオペレータコマンドになる
  # 例: mvs-console /D A,L   (実行中のジョブ一覧)
  # Hercules が止まっているときは FIFO の読み手がおらず書き込みが固まるため、timeout を付ける
  mvs-console = pkgs.writeShellApplication {
    name = "mvs-console";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      echo "$*" | timeout 5 tee ${consoleFifo} > /dev/null
    '';
  };
in
{
  users.groups.mainframe = { };
  users.users.hercules = {
    isSystemUser = true;
    group = "mainframe";
    home = stateDir;
  };
  # nixos ユーザーが sudo なしでジョブ投入・コンソール操作・プリンタ出力の参照をできるようにする
  users.users.nixos.extraGroups = [ "mainframe" ];

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 hercules mainframe - -"
    "d ${stateDir}/DASD 0750 hercules mainframe - -"
    "d ${stateDir}/printers 0750 hercules mainframe - -"
    "d ${stateDir}/punchcards 0750 hercules mainframe - -"
    # SHUTDOWN.RC は SCRIPTS/ を WorkingDirectory からの相対パスで参照する
    "L+ ${stateDir}/SCRIPTS - - - - ${mvsce}/SCRIPTS"
    # TN3270 で接続したときに表示されるロゴ
    "L+ ${stateDir}/herclogo.txt - - - - ${mvsce}/herclogo.txt"
  ];

  systemd.services.hercules = {
    description = "Hercules S/370 emulator running MVS/CE";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "systemd-tmpfiles-setup.service"
    ];
    # DASD は MVS が書き換え続ける状態なので、存在しないものだけをリリースから初期配置する (冪等)
    preStart = ''
      for disk in ${mvsce}/DASD/*; do
        if [ ! -e "DASD/$(basename "$disk")" ]; then
          install -m 0640 "$disk" DASD/
        fi
      done

      rm -f ${consoleFifo}
      mkfifo -m 0660 ${consoleFifo}
    '';

    # FIFO を読み書き両用 (<>) で標準入力に開く。
    # 書き手がいなくても EOF にならないため、Hercules はコマンドを待ち続ける。
    # --NoUI では Hercules は標準入力をコマンドスクリプトとして読む
    script = ''
      exec ${pkgs.hercules}/bin/hercules --NoUI \
        -f ${./hercules.cnf} \
        -r ${mvsce}/conf/mvsce.rc \
        0<> ${consoleFifo}
    '';

    # MVS を正規の手順で止める (イニシエータ停止 → JES2 停止 → QUIESCE → Hercules 終了)。
    # Hercules をいきなり kill すると、JES2 のスプールや DASD が壊れる可能性がある。
    # 実測では約 45 秒で終わる
    preStop = ''
      if kill -0 "$MAINPID" 2>/dev/null; then
        echo "script SCRIPTS/SHUTDOWN.RC" | timeout 5 tee ${consoleFifo} > /dev/null || true
        while kill -0 "$MAINPID" 2>/dev/null; do
          sleep 1
        done
      fi
    '';

    serviceConfig = {
      User = "hercules";
      Group = "mainframe";
      WorkingDirectory = stateDir;
      RuntimeDirectory = "mainframe";
      RuntimeDirectoryMode = "0750";
      UMask = "0027";
      # Hercules の出力は MVS のコンソールメッセージそのものである
      StandardOutput = "journal";
      StandardError = "journal";
      TimeoutStopSec = 300;
      Restart = "on-failure";
      RestartSec = 30;
    };
  };

  environment.systemPackages = [
    mvs-submit
    mvs-console
    # dasdls (DASD 内のデータセット一覧) などのユーティリティを使えるようにする
    pkgs.hercules
  ];

  # 動作確認用のサンプルジョブ (例: mvs-submit /etc/mainframe/samples/hello-cobol.jcl)
  environment.etc."mainframe/samples".source = ./samples;

  # TN3270 (TSO へのログオン)。外からは LB の VIP (192.168.5.200:3270) 経由で入る
  networking.firewall.allowedTCPPorts = [ 3270 ];
}
