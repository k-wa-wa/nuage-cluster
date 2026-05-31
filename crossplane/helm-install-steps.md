# Crossplane および PVE プロバイダーのインストール手順

本手順は、一時クラスター（または既存のKubernetesクラスター）に Crossplane と Proxmox VE プロバイダー (`provider-proxmox-bpg`) をインストールし、認証情報を設定する手順です。

---

## 1. Crossplane のインストール

まず、Helm を使用して Crossplane 本体を `crossplane-system` 名前空間にインストールします。

```bash
# Helmリポジトリの追加と更新
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

# Crossplaneのインストール
helm install crossplane \
  --namespace crossplane-system \
  --create-namespace \
  crossplane-stable/crossplane
```

インストールが成功したことを確認します。

```bash
kubectl get pods -n crossplane-system
```

---

## 2. Proxmox VE 接続用 Secret の作成

`provider-proxmox-bpg` は、Upjet を使用して `bpg/proxmox` Terraformプロバイダーのパラメータを JSON 形式で受け取る仕様になっています。
以下のテンプレートを元に、お使いの Proxmox VE の情報とクレデンシャルを入力した Secret マニフェストファイル（例: `secret.yaml`）を作成し、適用してください。

> [!NOTE]
> `endpoint` には Proxmox の API エンドポイント（ポート `8006` を含むURL）を指定してください。

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: proxmox-creds
  namespace: crossplane-system
type: Opaque
stringData:
  credentials: |
    {
      "endpoint": "https://<PROXMOX_IP>:8006/",
      "username": "<username>@<realm>",
      "password": "<password>",
      "insecure": "true"
    }
```

作成後、以下のコマンドでクラスターへ適用します。

```bash
kubectl apply -f secret.yaml
```

---

## 3. プロバイダーのインストールと設定 (ProviderConfig)

接続用 Secret が用意できたら、`provider.yaml` を適用して `Provider`（コントローラー本体）と `ProviderConfig`（接続設定の紐付け）を作成します。

```bash
kubectl apply -f provider.yaml
```

プロバイダーが正常にインストールされ、`Healthy=True` になることを確認します。

```bash
kubectl get providers
```

---

## 4. VM マニフェストの適用

プロバイダーのセットアップ完了後、VM を管理するためのマニフェスト（`vm-controlplane-01.yaml`）を適用します。

```bash
kubectl apply -f vm-controlplane-01.yaml
```
