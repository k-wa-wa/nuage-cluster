# nuage-cluster :sun_behind_small_cloud:

おうちクラスターのセットアップリポジトリ

## TODO :white_check_mark:

- [ ] Ingress or Ngrok 等の検討
- [ ] Argo CD / Dashboard の導入 (自動化)
- [ ] Ansible の実行をコンテナ内で行う (ホストマシンに依存せず実行可能にしたい)
- [ ] kube-vip を導入して HA Cluster にするか検討
- [ ] リージョンを追加して VPN で繋ぐ

## Infrastructure

### ハードウェア・ネットワーク構成

![hardware.drawio.svg](./docs/hardware.drawio.svg)

### Kubernetes 構成

TODO

## 手順

1. 物理ノードのセットアップ

   1. 各ノードに配置する ssh key を作成する

      ```sh
      mkdir .ssh
      ssh-keygen -f ./.ssh/id_rsa # その他のオプション
      ```

   1. Raspberry Pi Imager を使用して Raspberry Pi ノードをセットアップする

   1. Intel NUC ノードをセットアップする（[参考](./docs/setup-nuc.md)）

1. `playbooks/hosts_template.yaml`から`playbooks/hosts.yaml`を作成する

1. 以下を実行する
   ```sh
   bash scripts/setup-cluster.sh
   bash scripts/apply-apps.sh
   ```
