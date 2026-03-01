{ ... }:

{
  services.resolved.enable = false;
  services.coredns = {
    enable = true;
    config = ''
      . {
        bind 0.0.0.0
        log

        template ANY ANY nuage.cluster.wpc {
          answer "{{ .Name }} 60 IN A 192.168.5.200"
          fallthrough
        }

        forward . 8.8.8.8
      }
    '';
  };
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
