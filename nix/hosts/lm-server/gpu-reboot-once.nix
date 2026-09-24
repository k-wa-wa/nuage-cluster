{ pkgs, ... }:

# 初回ブートストラップ直後は base-vm イメージに amdgpu のファームウェアが無いため GPU の
# 初期化に失敗しており、構成を switch しただけでは復帰しない (再起動が必要)。
# ROCm から GPU が見えない場合に限り一度だけ自動で再起動し、それでも見えなければ
# 再起動を繰り返さずにユニットを失敗させて検知できるようにする。
{
  systemd.services.gpu-reboot-once = {
    description = "ROCm から GPU が見えない場合に一度だけ再起動する";
    path = with pkgs; [
      coreutils
      gnugrep
      systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "gpu-reboot-once";
    };
    script = ''
      marker=/var/lib/gpu-reboot-once/rebooted

      # kfd のトポロジに gfx_target_version が 0 以外のノードがあれば ROCm から GPU が見えている
      if grep -qsE '^gfx_target_version [1-9]' /sys/class/kfd/kfd/topology/nodes/*/properties; then
        echo "GPU is visible to ROCm."
        rm -f "$marker"
        exit 0
      fi

      # AMD の GPU (vendor 0x1002, class 0x03xxxx) 自体が無い場合は再起動しても直らない
      if ! grep -qs '^0x03' /dev/null $(grep -lsx '0x1002' /sys/bus/pci/devices/*/vendor | sed 's/vendor$/class/'); then
        echo "AMD GPU is not attached to this VM (check PCI passthrough)." >&2
        exit 1
      fi

      if [ -e "$marker" ]; then
        echo "GPU is still not visible after the automatic reboot. Not rebooting again." >&2
        exit 1
      fi

      # switch の途中で再起動しないよう、ブートストラップ・自動アップグレード中は次回に回す
      for unit in nixos-bootstrap.service nixos-upgrade.service bootstrap-second-switch.service; do
        if [ "$(systemctl show -p ActiveState --value "$unit")" = activating ]; then
          echo "$unit is running. Retry later."
          exit 0
        fi
      done

      echo "GPU is not visible to ROCm. Rebooting once." >&2
      touch "$marker"
      systemctl reboot
    '';
  };

  # OnBootSec は既に経過していても timer 開始時に即時発火するため、ブートストラップの
  # switch で初めて導入された場合も動く。以後は実行中の switch を避けて定期的に再判定する。
  systemd.timers.gpu-reboot-once = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "5min";
    };
  };
}
