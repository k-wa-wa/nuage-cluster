{ config, lib, pkgs, ... }:

let
  pechka-extract = pkgs.stdenv.mkDerivation rec {
    pname = "pechka-extract";
    version = "latest";

    src = pkgs.fetchurl {
      url = "https://github.com/k-wa-wa/pechka/releases/download/${version}/extract";
      hash = "sha256:d88a9874ecef40ae8081aa45c293de02cc78d422794e528fe9cc313666bcc966";
    };

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/extract
      chmod +x $out/bin/extract
    '';
  };
in
{
  sops = {
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.pechka_minio_secret_key = {
      sopsFile = ./secrets.yaml;
    };
  };

  # MakeMKV パッケージをシステムに自動インストール
  environment.systemPackages = [
    pkgs.makemkv
  ];

  # MakeMKV のみ例外的に unfree ライセンスを許可（グローバルな allowUnfree = true は不要）
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "makemkv"
  ];

  # 5分おきにディスク抽出を試みる Timer
  systemd.timers.pechka-extract = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "5m";
      Unit = "pechka-extract.service";
    };
  };

  systemd.services.pechka-extract = {
    description = "Pechka Bluray Extraction and Ingestion Job";
    # サービスの実行環境 of PATH に curl と makemkv, blkid (util-linux) をバインド
    path = [ pkgs.curl pkgs.makemkv pkgs.util-linux ];
    serviceConfig = {
      Type = "oneshot";
      # Nixでビルドした pechka-extract バイナリを直接指定
      ExecStart = "${pkgs.writeShellScript "pechka-extract-run" ''
        export DEVICE="/dev/sr0"
        export LOCAL_MKV_DIR="/tmp/mkv"
        export MINIO_URL="minio.cluster.wpc:9000"
        export MINIO_BUCKET="pechka"
        export MINIO_ACCESS_KEY="pechka"
        
        # Load MinIO secret key decrypted by sops-nix
        export MINIO_SECRET_KEY=$(cat ${config.sops.secrets.pechka_minio_secret_key.path})
        
        PECHKA_API_URL="http://pechka.cluster.wpc"

        # 1. Run extraction program from Nix store package
        echo "Starting disk extraction..."
        ${pechka-extract}/bin/extract
        
        # 2. Check output label and trigger Ingest API
        if [ -s "/tmp/bluray-label" ]; then
          DISC_LABEL=$(cat /tmp/bluray-label)
          echo "Extraction successful. Disc label: $DISC_LABEL. Triggering ingest API..."
          curl -f -s -X POST "$PECHKA_API_URL/api/v1/contents/ingest" \
            -H "Content-Type: application/json" \
            -d "{\"disc_label\": \"$DISC_LABEL\", \"content_title\": \"Auto Ingested from Bluray Extractor VM (Label: $DISC_LABEL)\"}"
        fi
      ''}";
      User = "root";
    };
  };
}
