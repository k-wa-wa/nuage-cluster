{
  config,
  lib,
  pkgs,
  ...
}:

let
  pechka-etl = pkgs.stdenv.mkDerivation rec {
    pname = "pechka-etl";
    version = "v0.1.6";

    src = pkgs.fetchurl {
      url = "https://github.com/k-wa-wa/pechka/releases/download/${version}/pechka-etl";
      hash = "sha256:a19aaa145e418cf81184599d7ee9ea8720d083c2e9dc67a074ddd8b2fa0f8c56";
    };

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/pechka-etl
      chmod +x $out/bin/pechka-etl
    '';
  };
in
{
  sops = {
    age.keyFile = "/var/lib/nix-provisioning/sops-key";
    secrets.pechka_minio_url = {
      sopsFile = ./secrets.yaml;
    };
    secrets.pechka_minio_bucket = {
      sopsFile = ./secrets.yaml;
    };
    secrets.pechka_minio_access_key = {
      sopsFile = ./secrets.yaml;
    };
    secrets.pechka_minio_secret_key = {
      sopsFile = ./secrets.yaml;
    };
  };

  networking.nameservers = [ "192.168.5.200" ];

  # MakeMKV がドライブ列挙に使う SCSI generic デバイス(/dev/sg*)に必要
  boot.kernelModules = [ "sg" ];

  # MakeMKV パッケージをシステムに自動インストール
  environment.systemPackages = [
    pkgs.makemkv
  ];

  # MakeMKV のみ例外的に unfree ライセンスを許可（グローバルな allowUnfree = true は不要）
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "makemkv"
    ];

  # MakeMKVのベータキー（2026年7月末まで有効）を宣言的に配置する設定
  systemd.tmpfiles.rules = [
    "d /root/.MakeMKV 0750 root root - -"
    "f /root/.MakeMKV/settings.conf 0600 root root - app_Key = \"T-BSaJ6gwgMx4eIggWkVYXiVP_6zehm7WAO9dEydvzOHFHoZ6YQ82BL5cGpYDxvyRWnS\"\n"
  ];

  # 5分おきにディスク抽出を試みる Timer
  systemd.timers.pechka-extract = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";
      OnUnitActiveSec = "1m";
      Unit = "pechka-extract.service";
    };
  };

  systemd.services.pechka-extract = {
    description = "Pechka Bluray Extraction and Ingestion Job";
    # サービスの実行環境の PATH に makemkv、blkid(util-linuxのbinとsbin)をバインド
    path = [
      pkgs.makemkv
      pkgs.util-linux
      "${pkgs.util-linux}/sbin"
    ];
    serviceConfig = {
      Type = "oneshot";
      # Nixでビルドした pechka-extract バイナリを直接指定
      ExecStart = "${pkgs.writeShellScript "pechka-extract-run" ''
        export DEVICE="/dev/sr1"
        export LOCAL_MKV_DIR="/tmp/mkv"

        # sops-nixで復号されたMinIOの接続情報を読み込む
        export MINIO_URL=$(cat ${config.sops.secrets.pechka_minio_url.path})
        export MINIO_BUCKET=$(cat ${config.sops.secrets.pechka_minio_bucket.path})
        export MINIO_ACCESS_KEY=$(cat ${config.sops.secrets.pechka_minio_access_key.path})
        export MINIO_SECRET_KEY=$(cat ${config.sops.secrets.pechka_minio_secret_key.path})

        export PECHKA_API_URL="https://pechka.cluster.wpc"

        # Run extraction program from Nix store package
        echo "Starting disk extraction..."
        ${pechka-etl}/bin/pechka-etl extract
      ''}";
      User = "root";
    };
  };
}
