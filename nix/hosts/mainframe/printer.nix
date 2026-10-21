{ pkgs, ... }:

# 帳票プリンタ (プリンタ 2, 出力クラス M) の「紙」を PDF にする、Linux 側のプリンタ役。
#
# MVS が帳票を印字すると /var/lib/mainframe/printers/prt00f.txt が更新される。
# その更新を契機に (systemd.path)、揃った出力を PDF にする。Linux 側は時刻も業務ロジックも持たない。
# PDF は tmpfs の /run/mainframe-printer に置き、永続化しない (配信先は今後決める)。

let
  stateDir = "/var/lib/mainframe";
  outDir = "/run/mainframe-printer";

  mainframe-printer = pkgs.writers.writePython3Bin "mainframe-printer" {
    libraries = [ pkgs.python3Packages.reportlab ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./tools/printer.py);
in
{
  systemd.tmpfiles.rules = [
    "d ${outDir} 0750 hercules mainframe - -"
  ];

  systemd.paths.mainframe-printer = {
    description = "Watch the report printer of MVS";
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathModified = "${stateDir}/printers/prt00f.txt";
  };

  systemd.services.mainframe-printer = {
    description = "Convert the report printer output of MVS to PDF";
    serviceConfig = {
      Type = "oneshot";
      User = "hercules";
      Group = "mainframe";
      UMask = "0027";
      ExecStart = "${mainframe-printer}/bin/mainframe-printer --out-dir ${outDir}";
    };
  };
}
