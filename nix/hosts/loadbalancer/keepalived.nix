{ ... }:

{
  services.keepalived = {
    enable = true;
    extraConfig = ''
      vrrp_instance VI_1 {
          state BACKUP
          interface eth0
          virtual_router_id 1 
          priority 100
          advert_int 1
          nopreempt

          authentication {
              auth_type PASS
              auth_pass sharedpassword
          }

          virtual_ipaddress {
              10.20.1.20/24
          }
      }

      vrrp_instance VI_2 {
          state BACKUP
          interface eth1
          virtual_router_id 2
          priority 100
          advert_int 1
          nopreempt

          authentication {
              auth_type PASS
              auth_pass sharedpassword
          }

          virtual_ipaddress {
              192.168.5.200/24
          }
      }
    '';
  };
}
