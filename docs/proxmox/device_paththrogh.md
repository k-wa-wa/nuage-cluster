# Proxmox VE PCIeパススルー設定手順 (AMD編)

## 手順1: BIOS/UEFIで仮想化支援機能を有効化

まず、ホストマシンを再起動し、BIOS/UEFI設定画面に入る。以下の項目を探して **有効 (Enabled)** に設定する。

- **IOMMU** または **AMD-Vi**
- **SVM** (Secure Virtual Machine)
- **ACS** (Access Control Services) ※利用可能な場合

---

## 手順2: ProxmoxホストOSの設定

Proxmox VEのコンソールまたはSSHでログインし、以下の設定を行う。

#### 1. GRUBブートローダーの編集

IOMMUを有効化し、IOMMUグループを分離するためのカーネルパラメータを設定する。

```bash
nano /etc/default/grub
```

`GRUB_CMDLINE_LINUX_DEFAULT` の行を以下のように編集する。

```diff
- GRUB_CMDLINE_LINUX_DEFAULT="quiet"
+ GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on pcie_acs_override=downstream,multifunction"
```

#### 2. VFIOモジュールのロード設定

パススルーに必要なモジュールを起動時に読み込むように設定する。

```bash
nano /etc/modules
```

以下の内容をファイルに追記（または存在しない場合は作成）する。

```
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
```

#### 3. GRUB設定の更新

編集したGRUBの設定をシステムに反映させる。

```bash
update-grub
```

#### 4. ホストの再起動

ここまでの設定を有効にするため、一度ホストマシンを再起動する。

```bash
reboot
```

-----

## 手順3: パススルー対象デバイスの指定

#### 1. デバイスIDの確認

パススルーしたいデバイス（今回はWiFiカード）のベンダーIDとデバイスIDを調べる。

```bash
lspci -nn
```

出力の中から対象デバイスを探し、`[xxxx:xxxx]` の形式で表示されるIDをメモする。(例: `[14e4:43a0]`)

#### 2. デバイスをVFIOドライバに割り当て

ホストOSが起動時に標準のドライバを読み込む代わりに、VFIOドライバがこのデバイスを確保するように設定する。

```bash
nano /etc/modprobe.d/vfio.conf
```

以下の行を追記する。`xxxx:xxxx` の部分を先ほど調べたIDに置き換える。

```
options vfio-pci ids=xxxx:xxxx
```

#### 3. initramfsの更新と再起動

設定をブートイメージに反映させ、再度ホストを再起動する。

```bash
update-initramfs -u -k all
reboot
```

-----

## 手順4: VMへのデバイス割り当て

最後に、Proxmox VEのWeb管理画面からVMにデバイスを割り当てる。

1.  対象のVMを選択し、**「ハードウェア」** タブを開く。
2.  **「追加」** をクリックし、**「PCIデバイス」** を選択する。
3.  **「デバイス」** のドロップダウンリストから、パススルーしたいデバイスを選択する。
4.  **「すべての機能を有効にする (All Functions)」** と **「PCI-Express」** にチェックを入れる。
5.  **「追加」** ボタンをクリックする。

以上で設定は完了する。VMを起動すると、ゲストOSがPCIeデバイスを直接認識・利用できるようになる。
