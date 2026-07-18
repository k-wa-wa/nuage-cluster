
## VM関連

### multipass

- ブリッジモードを使用する

```sh
multipass set local.bridged-network=en0
```

### GPU2つ目を追加するとproxmoxが落ちる

`find /sys/kernel/iommu_groups/ -type l`で確認するiommuグループが同じであることが原因？

echo "options vfio-pci ids=0000:07:00.0,0000:29:00.0" > /etc/modprobe.d/vfio.conf

echo "
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd" >> /etc/modules
echo "options vfio-pci ids=1002:7480" > /etc/modprobe.d/vfio.conf
update-grub


asrockのマザボ
iommu有効化・DMA Protectionは無効化
