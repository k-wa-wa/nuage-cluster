{ ... }:

{
  services.resolved.enable = false;
  services.coredns = {
    enable = true;
    config = ''
      . {
        bind 0.0.0.0
        
        # ワイルドカード設定
        template ANY ANY cluster.wpc {
          answer "{{ .Name }} 60 IN A 10.0.1.2"
          fallthrough
        }

        forward . 8.8.8.8
        log
        errors
      }
    '';
  };
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
