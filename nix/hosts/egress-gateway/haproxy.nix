{ ... }:

{
  services.haproxy = {
    enable = true;
    config = builtins.readFile ./haproxy.cfg;
  };

  systemd.services.haproxy = {
    serviceConfig = {
      AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
    };
  };

  networking.firewall.allowedTCPPorts = [
    2049
    11434
    9100
    8404
  ];
}
