{ pkgs, lib, ... }:

{
  imports = [
    ./dns.nix
    ./haproxy.nix
    ./keepalived.nix
  ];

  networking = {
    useDHCP = false;
    nameservers = [ "8.8.8.8" ];
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_nonlocal_bind" = 1;
  };

  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    extraFlags = [ "--collector.textfile.directory=/var/lib/prometheus/node-exporter" ];
  };
}
