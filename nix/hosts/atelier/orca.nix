# Orca サーバー (orca serve) を常駐させる。
#
# 本体は setup.sh が ~/.local/share/orca-ide に入れ、~/.local/bin/orca-ide から呼ぶ。
# ここでは本体の更新で変わらないもの (ユニット・ライブラリ・ネットワーク) だけを定義する。
{ pkgs, ... }:

let
  user = "nixos";
  port = 6769;

  # 家の LAN (vmbr0)。Mac はここから直接つなぐ。
  lanAddress = "192.168.5.252";
  lanSubnet = "192.168.5.0/24";

  # クライアントが接続しに来る宛先の既定値。ペアリング情報に埋め込まれる。
  # 出先からは Tailscale で入るので、MagicDNS 名にしておく (LAN の Mac はペアリング時に LAN の宛先を渡す)。
  pairingAddress = "ws://atelier:${toString port}";
in
{
  # 配布バイナリ (Orca・claude・agy・copilot) を動かす。
  # Orca は Electron 製なので、headless (orca serve) でも GTK・X11 系のライブラリを要求する。
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc
      zlib
      openssl
      curl
      icu
      nss
      nspr
      expat
      fuse3

      # Electron
      glib
      at-spi2-core
      cups
      dbus
      cairo
      gtk3
      pango
      libx11
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxcb
      libxkbcommon
      libgbm
      libdrm
      mesa
      libglvnd
      alsa-lib
      systemd
    ];
  };

  # ログアウト中も user ユニット (orca serve と、そこから起動したエージェント) を動かし続ける。
  users.users.${user}.linger = true;

  systemd.user.services.orca-serve = {
    description = "Orca サーバー (orca serve)";
    wantedBy = [ "default.target" ];

    unitConfig = {
      ConditionUser = user;
      # setup.sh を実行するまでは本体が無い。
      ConditionPathExists = "%h/.local/bin/orca-ide";
      StartLimitIntervalSec = 900;
      StartLimitBurst = 5;
    };

    # Orca のターミナルから起動するエージェントもこの PATH を引き継ぐ。
    path = [
      "/home/${user}/.local"
      "/run/wrappers"
      "/run/current-system/sw"
    ];

    environment = {
      ORCA_USER_DATA_PATH = "%h/.config/orca";
      # user ユニットには /etc/profile の環境変数が渡らないため、nix-ld の参照先を明示する。
      NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
      NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
    };

    serviceConfig = {
      # --supervise は落ちても自分で再起動し、繰り返し落ちたときだけ終了する。
      # --no-pairing は起動のたびにペアリングコードを発行しない (ペアリングは手で行う)。
      ExecStart = "%h/.local/bin/orca-ide serve --supervise --no-pairing --port ${toString port} --pairing-address ${pairingAddress}";
      # GH_TOKEN (bot の token)。Orca のターミナルとエージェントがすべて bot として GitHub に書く。
      EnvironmentFile = "-/var/lib/atelier/secrets.env";
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStopSec = 90;
      # 再起動や更新で本体だけを止め、ターミナルとエージェントのセッションは残す。
      KillMode = "process";
    };
  };

  # Orca は全インターフェースで待ち受けるため、Tailscale と家の LAN に限って開ける。
  # SDN (10.20.1.0/24) には開けない。k8s 上のワークロードから届かないようにする
  # (認証はペアリングだけで、ペアリングされると任意のコマンドを実行できる)。
  services.tailscale = {
    enable = true;
    # MagicDNS に resolv.conf を書き換えさせない。上の nameservers (wpcapp.net の split-horizon) を保つ。
    extraSetFlags = [ "--accept-dns=false" ];
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
  # LAN 側の NIC 名は cloud-init が付けるので、インターフェース名ではなく宛先と送信元で絞る。
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp -d ${lanAddress} -s ${lanSubnet} --dport ${toString port} -j nixos-fw-accept
  '';
}
