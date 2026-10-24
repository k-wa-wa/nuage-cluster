# atelier: エージェントと一緒に開発する作業場。
#
# Orca サーバー (orca serve) を常駐させ、スマホや PC の Orca から同じワークスペースに入る。
# 窓口エージェント (claude / agy / copilot) が人間と話し、任された仕事は autopilot5 の
# autopilot-run が裏で完走させる。
#
# nix では変わりにくいもの (ツール・ライブラリ・常駐ユニット) だけを定義する。
# 更新の速い Orca 本体とエージェント CLI は setup.sh が ~/.local に入れる。
{ lib, ... }:

{
  imports = [
    ./devtools.nix
    ./orca.nix
  ];

  networking = {
    hostName = "atelier";
    useDHCP = false;

    # LB の CoreDNS は SDN 内のクライアントに *.wpcapp.net を SDN 側 VIP (10.20.1.20) で返す。
    # これにより PR プレビュー (bwproxy-pr-N.wpcapp.net 等) へ到達できる。
    # 8.8.8.8 は LB の DNS 停止時に外部名前解決だけを維持するためのフォールバックで、
    # wpcapp.net を引くと到達不能な 192.168.5.200 が返る。
    nameservers = [
      "10.20.1.20"
      "8.8.8.8"
    ];
  };

  # setup.sh が入れる Orca・エージェント CLI と autopilot のスキルが呼ぶコマンドを通す。
  environment.localBinInPath = true;

  # 全エージェント共通のルールとスキルを置き、autopilot-run を入れる。
  programs.autopilot5 = {
    enable = true;
    user = "nixos";
    # 作業ごとのモデルの並び。モデルの更新はこのファイルだけで行う。
    models = ./models.yaml;
  };

  # GitHub への書き込みはすべて bot (bot-wa-wa) として行う。git は gh 経由で GH_TOKEN を使う。
  # 名前とメールは token から引くため setup.sh が設定する。
  programs.git = {
    enable = true;
    config.credential."https://github.com".helper = "!gh auth git-credential";
  };

  # bot の token (GH_TOKEN) を置く。SOPS では配らず、VM 起動後に手で置く。
  # 万一の流出時の影響が大きいため、bluray-extractor のように cloud-config へは書かない。
  systemd.tmpfiles.rules = [
    "d /var/lib/atelier 0700 nixos users -"
  ];

  system.activationScripts.atelierSetupScript = lib.stringAfter [ "users" ] ''
    install -D -m 0755 -o nixos ${./setup.sh} /home/nixos/setup.sh
  '';
}
