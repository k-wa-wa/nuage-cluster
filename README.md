# nuage-cluster :sun_behind_small_cloud:

おうちクラスターのセットアップリポジトリ

## TODO :white_check_mark:

- [x] Ingress or Ngrok 等の検討
   - Istio IngressGateway で実装
- [ ] Argo CD / Dashboard の導入 (自動化)
- [ ] Ansible の実行をコンテナ内で行う (ホストマシンに依存せず実行可能にしたい)
- [x] kube-vip を導入して HA Cluster にするか検討
   - 一旦実装したものの、外部 haproxy によるロードバランスに変更
- [x] AZ を追加して VPN で繋ぐ
- [ ] リージョンを追加して VPN で繋ぐ
- [ ] Ansible のリファクタ (突貫実装を整理・実行時間も短縮したい)
- [ ] DB を外出し (VM 化) するか、Operator を使用するか検討する
- [ ] LMServer の再構築
- [ ] 監視・バックアップなど運用の効率化

## Architecture

### ハードウェア・ネットワーク構成

<img src="./docs/hardware.drawio.svg" style="background-color: white; padding: 8px;">

### Kubernetes 構成

<img src="./docs/k8s-arch.drawio.svg" style="background-color: white; padding: 8px;">

### PVE on PVE 構成

PVE (Proxmox Virtual Environment) をネストさせ、いつでも作成・削除・検証可能な環境を用意している。

IPアドレスの範囲等は任意に変更可能。

<img src="./docs/pve-on-pve.drawio.svg" style="background-color: white; padding: 8px;">

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
   # 前提となるライブラリ等導入
   bash scripts/prerequire.sh

   # NFS作成
   bash scripts/nfs.sh

   # VM と VM 上で動作するサービス等作成
   bash scripts/setup-infra.sh

   # クラスター作成
   bash scripts/setup-cluster.sh
   bash scripts/apply-apps.sh
   ```
