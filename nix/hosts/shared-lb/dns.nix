{ ... }:

{
  services.resolved.enable = false;
  services.coredns = {
    enable = true;
    config = ''
      . {
        bind 0.0.0.0
        acl {
            allow net 10.20.1.0/24
            block
        }

        template ANY ANY nuage.cluster.wpc {
          answer "{{ .Name }} 60 IN A 10.20.1.20"
        }

        forward . 8.8.8.8
        log
      }

      . {
        bind 0.0.0.0
        acl {
            allow net 192.168.5.0/24
            block
        }

        template ANY ANY nuage.cluster.wpc {
          answer "{{ .Name }} 60 IN A 192.168.5.200"
        }

        forward . 8.8.8.8
        log
      }

      . {
        bind 0.0.0.0
        forward . 8.8.8.8
        log
      }
    '';
  };
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
