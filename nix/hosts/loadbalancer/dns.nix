{ ... }:

{
  services.resolved.enable = false;
  services.coredns = {
    enable = true;
    # split-horizon: SDN (prvmain 10.20.1.0/24) のクライアントには SDN 側の VIP を返す。
    # autopilot-server 等は 192.168.5.0/24 に足を持たず、LAN 側の VIP に到達できないため。
    # view を持つブロックが先に評価され、view の無い 2 つ目のブロックが既定 (LAN 側 VIP) になる。
    config = ''
      . {
        view sdn {
          expr incidr(client_ip(), '10.20.1.0/24')
        }
        bind 0.0.0.0
        log

        template ANY ANY cluster.wpc {
          answer "{{ .Name }} 60 IN A 10.20.1.20"
          fallthrough
        }
        template ANY ANY wpcapp.net {
          answer "{{ .Name }} 60 IN A 10.20.1.20"
          fallthrough
        }

        forward . 8.8.8.8
      }

      . {
        bind 0.0.0.0
        log

        template ANY ANY cluster.wpc {
          answer "{{ .Name }} 60 IN A 192.168.5.200"
          fallthrough
        }
        template ANY ANY wpcapp.net {
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
