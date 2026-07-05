# proxmox-ve_9.0-1-auto-from-http.iso イメージの作成方法

任意の Debian 上で実行

```bash
echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
sha512sum /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
apt update
apt install proxmox-auto-install-assistant -y

wget https://enterprise.proxmox.com/iso/proxmox-ve_9.0-1.iso

proxmox-auto-install-assistant prepare-iso ./proxmox-ve_9.0-1.iso --fetch-from http
```
