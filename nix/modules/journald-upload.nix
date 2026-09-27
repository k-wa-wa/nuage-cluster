# journald のログを VictoriaLogs (nuage-monitoring-stack) に送る。
# lb の HAProxy (VIP 10.20.1.20:8427) → vmauth → vlagent → VictoriaLogs レプリカ a/b の経路で届く。
# prvmain (10.20.1.0/24) に足を持たないホストは、各ホスト側で URL を上書きする。
{ lib, ... }:

{
  services.journald.upload = {
    enable = true;
    settings.Upload.URL = lib.mkDefault "http://10.20.1.20:8427/insert/journald";
  };
}
