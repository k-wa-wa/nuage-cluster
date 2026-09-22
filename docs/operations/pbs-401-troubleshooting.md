# PBS (truenas-pbs) 401 Unauthorized 調査メモ

2026-09-21 に発生した、PVE から PBS への認証失敗 (401) の調査結果を記録する。根本対応は未実施であり、本書は調査結果と対応案の控えである。

## 1. 現状

- PVE の `truenas-pbs` ストレージが `inactive` で、`pvestatd` が `truenas-pbs: error fetching datastores - 401 Unauthorized` を 10 秒間隔で出し続けている
- PBS は TrueNAS 上 (192.168.5.30:8007) で動いている。PVE からは `root@pam` + `/etc/pve/priv/storage/truenas-pbs.pw` の組で認証している
- 調査は nuc-1 (192.168.5.21) から参照系コマンドのみで実施した。PBS 側 (TrueNAS) には入っていない
- **PBS 側のログは未確認のため、401 の原因は推定である** (4 参照)

## 2. 時系列 (nuc-1 の journal)

| 時刻 | 状態 |
| :-- | :-- |
| 2026-09-19 00:00〜00:02 | vzdump (211 / 271 / 241) が `truenas-pbs` に正常完了 |
| 2026-09-19 20:05〜20:06 | `Connection refused` → `timed out` → `No route to host`。TrueNAS が停止 (再起動) した |
| 2026-09-21 00:00 | 定期バックアップが `could not activate storage 'truenas-pbs'` (No route to host) で失敗 |
| 2026-09-21 16:35 | `Connection refused`。PBS が起動し始めた |
| 2026-09-21 16:36〜 | `401 Unauthorized` が継続 |

nuc-1 自身の再起動は 2026-09-21 18:18 で、401 の開始 (16:36) より後である。nuc-1 の再起動は原因ではなく、TrueNAS の再起動が引き金と判断する。

## 3. 切り分けできたこと

- 通信は成立している。PBS は応答し、認証段階で拒否している
- 証明書フィンガープリントは `/etc/pve/storage.cfg` の値と一致した (`EE:A0:5B:AD:...:72:3A`)。証明書の作成日は 2026-07-12 で、再起動後も変わっていない
- nuc-1 の時刻は NTP 同期済みで、時刻ずれは原因ではない
- `storage.cfg` の設定は次のとおり
  ```
  pbs: truenas-pbs
      datastore pbs
      server 192.168.5.30
      content backup
      fingerprint ee:a0:5b:ad:...
      username root@pam
  ```
- パスワードファイル `/etc/pve/priv/storage/truenas-pbs.pw` は 2026-07-12 18:15 から更新されていない (内容は確認していない)

## 4. 推定原因

- PBS の設定領域 (`/etc/proxmox-backup`) は永続化されており、証明書が再起動後も残っている
- `root@pam` は PBS 内の OS ユーザー (PAM) 認証であり、パスワードは `/etc/shadow` にある。これは永続領域に含まれず、再起動でリセットされた可能性が高い
- この場合、PBS の `root` パスワードだけが元に戻り、PVE に保存済みのパスワードと合わなくなる

PBS の稼働形態 (TrueNAS アプリのコンテナ / VM / LXC) は未確認である。

## 5. 確認手順 (PBS 側)

```bash
tail -n 20 /var/log/proxmox-backup/api/auth.log
```

`authentication failure; rhost=192.168.5.21 user=root@pam msg=...` の行があれば、`msg` で原因が確定する。

## 6. 対応案

### 6.1 暫定: パスワードを設定し直す

PBS のシェルで `passwd root` を実行する。以前と別の値にした場合は、PVE 側も更新する。

```bash
pvesm set truenas-pbs --password
```

`--password` の値はプロンプトで入力する。コマンドラインに直書きしない。復旧後は `pvesm status` で `truenas-pbs` が `active` になり、`journalctl -u pvestatd` の 401 が止まることを確認する。

再起動でパスワードが戻る仕組みなら、この対応は再発する。

### 6.2 恒久: `root@pam` の API トークンに切り替える

トークンは `/etc/proxmox-backup` 側に保存されるため、再起動で消えないと見込まれる (未検証)。

```bash
# PBS 側
proxmox-backup-manager user generate-token root@pam pve   # secret は 1 回しか表示されない
proxmox-backup-manager acl update /datastore/pbs DatastoreAdmin --auth-id 'root@pam!pve'

# PVE 側
pvesm set truenas-pbs --username 'root@pam!pve' --password
```

### 6.3 GitOps 上の扱い

- 6.1・6.2 はいずれも稼働環境への手動変更である
- `storage.cfg` の `truenas-pbs` が Terraform (`terraform/pve/` 配下) で管理されているかは未確認。リポジトリ内で PBS を参照している箇所も未調査
- 切り替え前に、Terraform 側に該当設定があるか確認し、あればソースを修正して反映する

## 7. 影響

- `truenas-pbs` 宛ての vzdump バックアップが失敗し続ける。2026-09-21 00:00 は接続不可で失敗済みであり、次回の定期バックアップ (2026-09-22 00:00 CEST) も、直らなければ失敗する
- 直近の成功バックアップは 2026-09-19 00:00 台である
