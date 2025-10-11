# qdevice の追加

## pi-3

rootでパスワードでsshできるようにする
apt install corocync-qnetd

## nuc-1

apt install -y corosync-qdevice (全てのノード)
pvecm qdevice setup 192.168.5.13
