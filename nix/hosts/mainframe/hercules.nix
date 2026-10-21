{ pkgs, ... }:

# Hercules (メインフレームのエミュレータ) の上で MVS/CE を常駐させる。
#
# Linux 側から見た入口と出口:
#   - ジョブの投入: カードリーダ 127.0.0.1:3505 に JCL を流し込む (mvs-submit)
#   - ジョブの結果: 1403 プリンタ = /var/lib/mainframe/printers/prt00e.txt に追記される
#   - オペレータ操作: Hercules の HTTP サーバー (127.0.0.1:8038) にコマンドを POST する (mvs-console)
#   - コンソールの表示: journalctl -u hercules
#   - 対話操作 (TSO): TN3270 の 3270 番ポート

let
  mvsce = pkgs.callPackage ./mvsce.nix { };
  stateDir = "/var/lib/mainframe";

  # Hercules のコマンドを HTTP で送る。ファイアウォールで 8038 は閉じているため、LXC の中からしか届かない
  herculesCmd = pkgs.writeShellApplication {
    name = "hercules-cmd";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      curl -sf -o /dev/null --max-time 10 http://127.0.0.1:8038/cgi-bin/tasks/cmd --data-urlencode "cmd=$*"
    '';
  };

  # IPL の完了 (TSO がログオンを受け付け始めた) まで見届ける。hercules.service の ExecStartPost として動き、
  # これが終わるまで hercules.service は activating のままなので、後続 (mvs-config など) は MVS が使える状態で動く。
  #
  # MVS/CE の rc ファイルは、IPL 中の問い合わせ (IEA101A) に自動応答 (hao) で空の応答を返すが、
  # この応答がまれに取りこぼされ、IPL が止まる (応答を送り直すと進む)。
  # そこで出力が 20 秒止まったら、最後の問い合わせに対する応答を送り直す
  iplWatch = pkgs.writeShellApplication {
    name = "hercules-ipl-watch";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.systemd
      herculesCmd
    ];
    text = ''
      # INVOCATION_ID は systemd が渡す。今回の起動分のログだけを見る
      console_log() {
        journalctl -q -o cat _SYSTEMD_INVOCATION_ID="$INVOCATION_ID" 2>/dev/null || true
      }

      deadline=$((SECONDS + 600))
      last_count=-1
      stalled_since=$SECONDS
      while ((SECONDS < deadline)); do
        out=$(console_log)
        if grep -q "IKT007I TCAS ACCEPTING LOGONS" <<<"$out"; then
          echo "IPL が完了した"
          exit 0
        fi
        count=$(wc -l <<<"$out")
        if [ "$count" != "$last_count" ]; then
          last_count=$count
          stalled_since=$SECONDS
        elif ((SECONDS - stalled_since >= 20)); then
          # IPL 中の問い合わせは IEA101A (システムパラメータ) と $HASP426 (JES2 の起動方法) の 2 つ
          if grep -E 'IEA101A|HASP426' <<<"$out" | tail -1 | grep -q 'HASP426'; then
            reply='/r 0,noreq'
          else
            reply='/'
          fi
          echo "IPL が 20 秒止まっている。応答を送り直す: $reply"
          hercules-cmd "$reply" || true
          stalled_since=$SECONDS
        fi
        sleep 5
      done
      echo "600 秒以内に IPL が完了しなかった"
      exit 1
    '';
  };

  # JCL をカードリーダへ流し込む。引数のファイル (省略時は標準入力) を 1 デッキとして送る
  mvs-submit = pkgs.writeShellApplication {
    name = "mvs-submit";
    text = ''
      cat -- "$@" > /dev/tcp/127.0.0.1/3505
    '';
  };

  # Hercules のコンソールにコマンドを 1 行送る。先頭が / なら MVS のオペレータコマンドになる
  # 例: mvs-console /D A,L   (実行中のジョブ一覧)。結果は journalctl -u hercules に出る
  mvs-console = pkgs.writeShellApplication {
    name = "mvs-console";
    text = ''
      exec ${herculesCmd}/bin/hercules-cmd "$@"
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

      # mvsctl はこのファイルで起動完了を判定する。前回の IPL の記録を見ないよう消しておく
      rm -f mvslog.txt
    '';

    # 標準入力は /dev/null (systemd の既定) にし、コマンドは HTTP で受ける。
    # --NoUI は標準入力をコマンドとして読むが、FIFO をつなぐと IPL が止まったり終了時に
    # プロセスが残ったりした (標準入力の読み込み待ちと競合する)。MVS/CE の Docker イメージと同じ構成にしている
    script = ''
      exec ${pkgs.hercules}/bin/hercules --NoUI \
        -f ${./hercules.cnf} \
        -r ${mvsce}/conf/mvsce.rc
    '';

    # MVS を正規の手順で止める (イニシエータ停止 → JES2 停止 → QUIESCE → Hercules 終了)。
    # Hercules をいきなり kill すると、JES2 のスプールや DASD が壊れる可能性がある。
    # 標準入力が /dev/null のため、QUIESCE で CPU が止まると Hercules は自ら終了する (実測で約 30 秒)
    preStop = ''
      if kill -0 "$MAINPID" 2>/dev/null; then
        ${herculesCmd}/bin/hercules-cmd script SCRIPTS/SHUTDOWN.RC || true
        while kill -0 "$MAINPID" 2>/dev/null; do
          sleep 1
        done
      fi
    '';

    serviceConfig = {
      User = "hercules";
      Group = "mainframe";
      WorkingDirectory = stateDir;
      UMask = "0027";
      # Hercules の出力は MVS のコンソールメッセージそのものである
      StandardOutput = "journal";
      StandardError = "journal";
      # IPL の完了まで見届ける。journal を読むため root (+) で動かす
      ExecStartPost = "+${iplWatch}/bin/hercules-ipl-watch";
      TimeoutStartSec = 900;
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
