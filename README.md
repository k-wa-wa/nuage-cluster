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

   1. ルーター側で物理ノードに固定 IP を振る（各ノードで設定するのが面倒なため、ルーターで一括設定する）

1. `playbooks/{k8s,vm}/hosts_template.yaml`から`playbooks/{k8s,vm}/hosts.yaml`を作成する

1. 以下を実行する
   ```sh
   bash scripts/setup-cluster.sh
   bash scripts/apply-apps.sh
   ```
