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

   1. VM の定義

   ```sh
   bash scripts/infra/cluster.sh
   bash scripts/infra/lm-server.sh
   bash scripts/infra/nfs.sh
   bash scripts/infra/proxy.sh
   bash scripts/infra/smb.sh
   ```

   1. Platform の定義

   ```sh
   bash scripts/platform/cluster.sh
   ```

   1. Application の定義

   ```sh
   bash scripts/apps/cluster.sh
   bash scripts/apps/lm-server.sh
   bash scripts/apps/nfs.sh
   bash scripts/apps/proxy.sh
   bash scripts/apps/smb.sh
   ```

### 各種スクリプトについて

`script`配下の極力スクリプトは冪等性を持つように作成しているが、レイヤーによって保証する範囲が異なる。

```
├── scripts
│   ├── apps
│   └── infra
```

- infra 層は前提となる VM・クラスター の構築を担う。基本的に再作成となるため、`定義したVMが存在する状態`のみを保証しており、上位のレイヤーの構成やデータ状態については保証しない。
- apps 層はアプリケーションの導入を担う。冪等性のある定義を行う。
