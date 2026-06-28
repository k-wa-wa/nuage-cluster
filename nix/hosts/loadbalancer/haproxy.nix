{ ... }:

{
  services.haproxy = {
    enable = true;
    config = builtins.readFile ./haproxy.cfg;
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
    6443
    50000
  ];
}
