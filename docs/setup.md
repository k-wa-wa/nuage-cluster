# セットアップ手順

物理ノードの初期構築からクラスター作成までの手順。

## 1. 事前準備(鍵の作成)

### SSH キー

```sh
# 各ノードへ配置するキー
ssh-keygen -f ./.ssh/id_rsa # その他のオプション
ssh-keygen -t ed25519 -f ./.ssh/id_ed25519 -N ""
bash .ssh/gen-keys.sh
```

### SOPS (Age) キー

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
age-keygen -o ~/.config/sops/age/argocd_key.txt
age-keygen -o ~/.config/sops/age/lb_key.txt
```

## 2. 物理ノードのセットアップ

Intel NUC・自作 PC ノードとも手順は同じ。以下の例は Ubuntu の ISO だが、実際には Proxmox VE を入れる。

### USB に ISO イメージを焼く (macOS)

```sh
hdiutil convert -format UDRW -o ./ubuntu.img ~/Downloads/ubuntu-24.04.1-live-server-amd64.iso

# usbメモリの確認
diskutil list

# アンマウント
diskutil unmountDisk /dev/xxx

# 書き込み(パーティションは指定しない)
sudo dd if=./ubuntu.img.dmg of=/dev/xxx bs=1m
```

### ブート

インストラクションに沿って進める。openSSH はインストールしておく。

```sh
sudo systemctl enable ssh
sudo systemctl start ssh
```

### ssh して設定

公開鍵を配置する。

```sh
cd .ssh
vi authorized_keys
# chmod 600 .ssh/authorized_keys
```

パスワード認証を無効化する。

```sh
sudo vi /etc/ssh/sshd_config
# PasswordAuthentication no
# # Include ...
```

### 固定 IP の割り当て

ルーター側で物理ノードに固定 IP を振る(各ノードで設定するのが面倒なため、ルーターで一括設定する)。

## 3. Proxmox のセットアップ

- zfs
    - 各ノードで zfs を作成する(local-zfs)
    - zfs の thin provision を有効化する(datacenter > storage > local-zfs)

## 4. IaC 適用・クラスター作成

```bash
# TODO: 手順再作成
# NFS 等のセットアップ

terragrunt --terragrunt-working-dir terraform/ run-all apply

# クラスター作成
bash scripts/bootstrap-cluster.sh && bash scripts/apply-apps.sh
```

SDN Controller (EVPN) は Terraform 管理外のため、GUI で手動作成する必要あり。
