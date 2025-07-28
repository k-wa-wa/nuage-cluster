# nuage-cluster :sun_behind_small_cloud:

おうちクラスターのセットアップリポジトリ

## TODO :white_check_mark:

- [ ] Ingress or Ngrok 等の検討
- [ ] Argo CD / Dashboard の導入 (自動化)
- [ ] Ansible の実行をコンテナ内で行う (ホストマシンに依存せず実行可能にしたい)
- [x] kube-vip を導入して HA Cluster にするか検討
- [x] AZ を追加して VPN で繋ぐ
- [ ] リージョンを追加して VPN で繋ぐ
- [ ] Ansible のリファクタ (結構ひどい・実行時間も短縮したい)

## Infrastructure

### ハードウェア・ネットワーク構成

<img src="./docs/hardware.drawio.svg" style="background-color: white; padding: 8px;">

### Kubernetes 構成

<img src="./docs/k8s-arch.drawio.svg" style="background-color: white; padding: 8px;">

## 手順

1. 物理ノードのセットアップ

   1. 各ノードに配置する ssh key を作成する

      ```sh
      mkdir .ssh
      ssh-keygen -f ./.ssh/id_rsa # その他のオプション
      ```

   1. Raspberry Pi Imager を使用して Raspberry Pi ノードをセットアップする

   1. Intel NUC ノードをセットアップする（[参考](./docs/setup-nuc.md)は Ubuntu だが、Proxmox を入れる）

   1. 自作 PC ノードをセットアップする(NUC と同様 Proxmox)

   1. ルーター側で物理ノードに固定 IP を振る（各ノードで設定するのが面倒なため、ルーターで一括設定する）

1. 各種スクリプトを実行する

   ```bash
   bash scripts/cluster/dns.sh
   bash scripts/cluster/proxy.sh
   bash scripts/cluster/nfs.sh

   bash scripts/cluster/setup.sh
   bash scripts/cluster/apply-apps.sh
   ```
