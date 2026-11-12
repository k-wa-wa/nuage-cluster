# atelier: エージェントと一緒に開発する作業場。
#
# Orca サーバー (orca serve) を常駐させ、スマホや PC の Orca から同じワークスペースに入る。
# 窓口エージェント (claude / agy / codex) が人間と話し、任された仕事は autopilot5 の
# autopilot-run が裏で完走させる。
#
# nix では変わりにくいもの (ツール・ライブラリ・常駐ユニット) だけを定義する。
# 更新の速い Orca 本体とエージェント CLI は setup.sh が ~/.local に入れる。
{
  config,
  lib,
  agentRules,
  ...
}:

{
  imports = [
    ./ai-metrics.nix
    ./devtools.nix
    ./home.nix
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

  # エージェントは Mac と同じ `ssh <host>` で各ホストに入る。ホスト一覧はリポジトリの .ssh/ssh_config を Include して共有し、
  # 入る先のユーザーは agent (modules/agent-user.nix、権限は Mac の nixos と同じ)、鍵は atelier 用のもの (下の sops.secrets.agent_ed25519) にする。
  # ssh_config は先に得た値が勝つので、Include より前に書いて User・鍵・ProxyJump を上書きする。
  # agent の鍵は転送を禁じている (restrict) ため lb-1 を踏み台にできず、atelier は SDN にも LAN にも直接届くので ProxyJump は使わない。
  programs.ssh.extraConfig = ''
    Host *
        User agent
        IdentityFile ${config.sops.secrets.agent_ed25519.path}
        IdentitiesOnly yes
        ProxyJump none
    Include /home/nixos/ghq/github.com/k-wa-wa/nuage-cluster/.ssh/ssh_config
  '';

  # SSH のホスト鍵は Terraform の cloud-config (terraform/vpc/zone-dev/atelier.tf) が置く。中身は terraform/pve/hosts-secrets/host-keys.yaml の atelier。
  # 公開鍵は .ssh/known_hosts にある。sops-nix もこの鍵を Age 鍵として使う (sops.age.sshKeyPaths の既定値が hostKeys の ed25519 を拾う)。
  services.openssh.hostKeys = [
    {
      path = "/var/lib/nix-provisioning/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];

  # agent ユーザーで入る鍵。秘密鍵は scripts/gen-atelier-agent-key.sh が作り、atelier 自身のホスト鍵で開く。
  # ssh は nixos ユーザーで動くので、所有者を nixos にする。
  sops.secrets.agent_ed25519 = {
    sopsFile = ./secrets.yaml;
    owner = "nixos";
  };

  # setup.sh が入れる Orca・エージェント CLI と autopilot のスキルが呼ぶコマンドを通す。
  environment.localBinInPath = true;

  # 全エージェント共通のルールとスキルを置き、autopilot-run を入れる。
  programs.autopilot5 = {
    enable = true;
    user = "nixos";
    # 担当 CLI の優先順と段階ごとのモデル。担当・モデルの更新はこのファイルだけで行う。
    models = ./models.yaml;
    # Mac と共通の個人のルール (nix-config の rules.md)。Mac だけのルール (git は人間が扱う) は入れない。
    extraRules = [ agentRules ];
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
