# nuc-2 のクラスタからの除外と Qdevice の撤去 実施ログ

- **日時**: 2026-11-01
- **対象**: 2026-09-21 に故障で退役した nuc-2 (`192.168.5.22`)。退避の記録は [2026-09-21-nuc-2-migration-to-server-2.md](./2026-09-21-nuc-2-migration-to-server-2.md)
- **作業結果**: nuc-2 をクラスタから外し、Qdevice を撤去した。クラスタは 3 台 (nuc-1・server-1・server-2)・`Quorum: 2` になり、1 台落ちても動き続けられる

---

SSH 鍵と SOPS の鍵の整理の途中で、退役した nuc-2 が Proxmox のクラスタと Terraform に残っていることが分かったので、取り除いた。後継機を入れるときは、新しいノードとしてクラスタに加える。

## 1. 見つかったこと

| 項目 | 状態 | 影響 |
| :-- | :-- | :-- |
| `corosync.conf` | nuc-2 (nodeid 4, `192.168.5.22`) がメンバーのまま | 落ちた 1 台を数え続け、票が `Expected votes: 4` / `Total votes: 3` / `Quorum: 3` だった |
| Qdevice | `192.168.5.13` (qdevice 用に用意した Raspberry Pi。電源を入れていない) を `ffsplit`・1 票で設定していたが、票を入れていなかった (各ノードのフラグが `NV`) | 上と合わせ、あと 1 台落ちると過半数を割る状態だった |
| `/etc/pve/priv/authorized_keys` | nuc-2 の root の鍵 (`SHA256:mgW8yd0wXwbS6fmAJLFPh0qIG6nq8kNE2uWqj8tvySc root@nuc-2`) が残っていた | nuc-2 の起動用ディスクの秘密鍵で、3 台すべてに root で入れた |
| `/etc/pve/nodes/nuc-2` | `pve-ssl.key`・`pve-ssl.pem`・`lrm_status`・`ssh_known_hosts` が残っていた | nuc-2 の証明書の秘密鍵が残っていた |
| `terraform/pve/hosts-secrets/main.tf` | lb-2・chaos-monitor・pg-cluster-2 の書き先が nuc-2 (`192.168.5.22`) のまま | 鍵を配る apply が nuc-2 に届かず失敗した。server-2 (`192.168.5.26`) に直した (#69 の `bd9393c`) |

## 2. 実施した作業

いずれも nuc-1 (`192.168.5.21`) で行った。`/etc/pve` は 3 台で共有しているので、1 台で行えば全体に効く。

1. **nuc-2 の root の鍵を外す**
   ```bash
   cp /etc/pve/priv/authorized_keys /root/authorized_keys.bak-2026-11-01
   grep -v " root@nuc-2$" /etc/pve/priv/authorized_keys > /root/authorized_keys.new
   cat /root/authorized_keys.new > /etc/pve/priv/authorized_keys   # /etc/pve は置き換えではなく上書きで書く
   ```
   残りは server-1・server-2・nuc-1 の root の鍵と、Mac の `.ssh/id_rsa` の 4 本である。
2. **控えを取る**
   ```bash
   d=/root/nuc-2-retire-2026-11-01; mkdir -p $d
   cp /etc/pve/corosync.conf $d/
   cp -a /etc/pve/nodes/nuc-2 $d/nodes-nuc-2
   ```
3. **Qdevice を外そうとして止まる**
   `pvecm qdevice remove` は全ノードがつながっている必要があり、`All nodes must be online! Node nuc-2 is offline, aborting.` で止まった。順番を入れ替え、先に nuc-2 を外した。
4. **nuc-2 をクラスタから外す**
   ```bash
   pvecm delnode nuc-2
   ```
   `Could not kill node (error = CS_ERR_NOT_EXIST)` が出るが、外すノードが既に落ちているためで、`corosync.conf` から nuc-2 は消えた。票は `Expected votes: 4` (3 台 + Qdevice) / `Quorum: 3` のままだった。
5. **Qdevice を外す**
   ```bash
   pvecm qdevice remove
   ```
   3 台の `corosync-qdevice` が無効になり、`corosync.conf` の `quorum` は `provider: corosync_votequorum` だけになった。票は `Expected votes: 3` / `Total votes: 3` / `Quorum: 2` になり、1 台落ちても動き続けられる。3 台のクラスタで Qdevice を使うことは Proxmox が勧めていないので、作り直さない。
6. **`/etc/pve/nodes/nuc-2` を消す**
   ```bash
   rm -r /etc/pve/nodes/nuc-2
   ```
   `/etc/pve/nodes/` は nuc-1・server-1・server-2 の 3 つになった。

## 3. 残っていること

- `pvecm status` の `Flags` に `Qdevice` の表示が残っている。票は数えておらず (`Quorum: 2`)、`corosync-qdevice` も止まっている。corosync を再起動すれば消える見込みなので、次に Proxmox を再起動するときに確かめる
- nuc-1 の `/root/nuc-2-retire-2026-11-01/` (nuc-2 の証明書の秘密鍵を含む)・`/root/authorized_keys.bak-2026-11-01`・`/root/authorized_keys.new` は、しばらく様子を見て問題が無ければ消す
- `192.168.5.13` の Raspberry Pi の `corosync-qnetd` に、このクラスタ用の設定が残る。電源を入れるときに片付ける
- nuc-2 の起動用ディスクには nuc-2 の root の秘密鍵が残る。上の鍵を外したので 3 台には入れないが、手放すときはディスクを消去する
- `terraform/vpc/zone-private-persistent/postgres-cluster.tf` の pg-cluster-2 は `node_name = "nuc-2"` のまま (実物は server-2)。直すまで `zone-private-persistent` は apply しない
