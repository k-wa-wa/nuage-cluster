# nuage-cluster :sun_behind_small_cloud:

おうちクラスターのセットアップリポジトリ

## TODO :white_check_mark:

- [x] ラズパイの導入 & Intel NUC に Ubuntu Server を入れ、脱 VM
- [ ] Ingress or Ngrok 等の検討
- [ ] Argo CD / Dashboard の導入 (自動化)
- [ ] Ansible の実行をコンテナ内で行う (ホストマシンに依存せず実行可能にしたい)
- [ ] kube-vip 導入を自動化

## 構成図

wip

## 手順

1. VM のノードの準備

   1. 物理ホストに Vagrant(with VirtualBox) と ssh 可能な環境を整え、`.ssh-host`ディレクトリに鍵を配置、`config_template`に倣って`config`ファイルを作成する

   1. VM の各ノードに配置する ssh key を作成する

      ```sh
      mkdir .ssh
      ssh-keygen -f ./.ssh/id_rsa # その他のオプション
      ```

1. Raspberry Pi のノードの準備

   1. Raspberry Pi Imager を利用して Ubuntu Server 24.04 LTS を書き込み

   1. `./.ssh/id_rsa`を用いて ssh できるようにセットアップする

1. `02-create-env.sh`内の`xxx`でマスクされたネットワークアドレスを埋める

1. 以下を実行する
   ```sh
   bash setup-nuage-cluster.sh
   ```

## Tailscale で VPN 経由でアクセスする

```sh
# tailscaleのコンソールから以下のコマンドを発行し、nodeで実行する
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --auth-key=xxx
sudo tailscale up --advertise-routes=192.168.xxx.xxx/xx # なぜかlinuxでは他デバイスから接続できず

echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
```

## トラブルシューティング (wip)

- xxx
