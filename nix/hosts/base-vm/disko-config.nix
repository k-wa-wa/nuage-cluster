{
  disko.devices = {
    disk = {
      main = {
        # ProxmoxでVirtIOを使用している場合は /dev/vda
        # SCSI/SATAを使用している場合は /dev/sda
        device = "/dev/vda"; 
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            # 1. EFIシステムパーティション
            boot = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            # 2. ルートパーティション (SSDに最適化)
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4"; # もしくは btrfs/zfs
                mountpoint = "/";
                # SSDの寿命とパフォーマンスのためのマウントオプション
                mountOptions = [ "noatime" "discard" ]; 
              };
            };
          };
        };
      };
    };
  };
}
