# Intel NUCのセットアップ

## USBにISOイメージを焼く

```sh
hdiutil convert -format UDRW -o ./ubuntu.img ~/Downloads/ubuntu-24.04.1-live-server-amd64.iso

# usbメモリの確認
mount

# アンマウント
diskutil unmount /dev/xxx

# 書き込み
sudo dd if=./ubuntu.img.dmg of=/dev/disk4s1 bs=1m
```

## ブート

インストラクションに沿って進める。openSSHはインストールしておく

```sh
sudo systemctl enable ssh
sudo systemctl start ssh
```

## sshして設定

公開鍵を配置する

```sh
cd .ssh
vi authorized_keys
# chmod 600 .ssh/authorized_keys
```

パスワード認証を無効化する

```sh
sudo vi /etc/ssh/sshd_config
# PasswordAuthentication no
# # Include ...
```
