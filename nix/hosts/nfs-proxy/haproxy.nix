{ ... }:

{
  services.haproxy = {
    enable = true;
    config = builtins.readFile ./haproxy.cfg;
  };

  networking.firewall.allowedTCPPorts = [
    2049
  ];
}
