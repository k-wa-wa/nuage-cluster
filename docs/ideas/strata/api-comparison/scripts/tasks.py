import os
# リポジトリのルート (このファイルは docs/ideas/strata/api-comparison/scripts/ にある)
REPO=os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../../.."))
AGENT_Q={
"A1":"egress-gateway と pg-cluster-2 の NixOS 自動更新 (nixos-upgrade) は、それぞれいつ走るか。どのファイルのどの設定で決まっているか。起動直後にも走るかどうかも答えよ。",
"A2":"LiteLLM のモデル名 auto に投げたリクエストは、lm-server が落ちているとき何に切り替わるか。切り替える前に lm-server へ再試行するか。lm-server と切り替え先のリクエストのタイムアウトはそれぞれ何秒か。",
"A3":"lm-server の llama.cpp を Claude Code から使うために入れている工夫を、設定ファイルから 3 つ以上挙げ、それぞれ何の問題を避けるためかを説明せよ。",
}
L1="""以下は k8s 上のアプリの障害の材料である。根本原因を 1 つに絞って答え、根拠となる行を引用し、確かめるべきことと直し方を示せ。日本語で簡潔に。

$ kubectl -n pechka get pods
NAME                            READY   STATUS             RESTARTS       AGE
techfeed-api-6d9f8c7b5-2mzqk    0/1     CrashLoopBackOff   14 (2m ago)    48m
techfeed-api-6d9f8c7b5-9wq4t    1/1     Running            0              3d
techfeed-batch-29371234-x7k2p   0/1     Error              0              52m

$ kubectl -n pechka get events --sort-by=.lastTimestamp | tail -8
55m   Normal    Sync          application/pechka   Sync operation to 4be1e07 succeeded (Secret/techfeed-db configured)
49m   Normal    Killing       pod/techfeed-api-6d9f8c7b5-hl8vd   Stopping container techfeed-api (node worker-03 drained)
48m   Normal    Scheduled     pod/techfeed-api-6d9f8c7b5-2mzqk   Successfully assigned pechka/techfeed-api-6d9f8c7b5-2mzqk to worker-02
48m   Normal    Pulled        pod/techfeed-api-6d9f8c7b5-2mzqk   Container image "ghcr.io/k-wa-wa/pechka-techfeed:3f9a1c2" already present on machine
2m    Warning   BackOff       pod/techfeed-api-6d9f8c7b5-2mzqk   Back-off restarting failed container techfeed-api

$ kubectl -n pechka get deploy techfeed-api -o jsonpath='{.spec.template.spec.containers[0].env}'
[{"name":"DATABASE_PASSWORD","valueFrom":{"secretKeyRef":{"name":"techfeed-db","key":"password"}}},{"name":"DATABASE_HOST","value":"pg-rw.database.svc.cluster.local"}]

$ kubectl -n pechka logs techfeed-api-6d9f8c7b5-2mzqk --previous
2026-11-08T05:12:01Z WARN  dns: slow lookup pg-rw.database.svc.cluster.local took 1203ms
2026-11-08T05:12:02Z INFO  loading config from /etc/techfeed/config.yaml
2026-11-08T05:12:02Z INFO  connecting to postgres host=pg-rw.database.svc.cluster.local db=techfeed user=techfeed
2026-11-08T05:12:12Z ERROR startup failed
Traceback (most recent call last):
  File "/app/techfeed/db.py", line 23, in open_pool
    pool.wait(timeout=10)
  File "/usr/lib/python3.12/site-packages/psycopg_pool/pool.py", line 212, in wait
    raise PoolTimeout(f"pool initialization incomplete after {timeout} sec") from None
psycopg_pool.PoolTimeout: pool initialization incomplete after 10.0 sec

2026-11-08T05:12:02Z WARNING psycopg.pool: error connecting in 'pool-1': connection failed: connection to server at "10.20.3.15", port 5432 failed: FATAL:  password authentication failed for user "techfeed"
2026-11-08T05:12:04Z WARNING psycopg.pool: error connecting in 'pool-1': connection failed: connection to server at "10.20.3.15", port 5432 failed: FATAL:  password authentication failed for user "techfeed"

$ kubectl -n pechka logs techfeed-api-6d9f8c7b5-9wq4t --tail=3
2026-11-08T05:59:40Z INFO  GET /api/feed 200 41ms
2026-11-08T05:59:52Z INFO  GET /api/feed 200 38ms
2026-11-08T06:00:03Z INFO  GET /healthz 200 1ms
"""
L2="""以下は NixOS LXC の自動更新ジョブのログである。(1) 何が失敗したか (ファイルと行)、(2) 今このホストの Patroni に影響はあるか、(3) 同じ構成の pg-cluster-1 (03:00 更新) と pg-cluster-3 (03:20 更新) はどうなるか、(4) どう直すか、を日本語で簡潔に答えよ。

Nov 08 03:10:02 pg-cluster-2 systemd[1]: Starting NixOS Upgrade...
Nov 08 03:10:02 pg-cluster-2 nixos-upgrade-pre-check[1201]: recorded /nix/store/9x2k...-nixos-system-pg-cluster-2-26.05.20261101 as pre-upgrade profile
Nov 08 03:10:41 pg-cluster-2 nixos-upgrade-start[1234]: building the system configuration...
Nov 08 03:11:58 pg-cluster-2 nixos-upgrade-start[1234]: error:
Nov 08 03:11:58 pg-cluster-2 nixos-upgrade-start[1234]:        … while evaluating the attribute 'config.system.build.toplevel'
Nov 08 03:11:58 pg-cluster-2 nixos-upgrade-start[1234]:        … while evaluating the option `systemd.services.patroni.serviceConfig.ExecStartPre':
Nov 08 03:11:58 pg-cluster-2 nixos-upgrade-start[1234]:        … while evaluating definitions from `/nix/store/7hq...-source/nix/hosts/postgres-cluster/patroni.nix':
Nov 08 03:11:58 pg-cluster-2 nixos-upgrade-start[1234]:        error: undefined variable 'pgBackrestConf'
Nov 08 03:11:58 pg-cluster-2 nixos-upgrade-start[1234]:        at /nix/store/7hq...-source/nix/hosts/postgres-cluster/patroni.nix:57:46:
Nov 08 03:11:58 pg-cluster-2 nixos-upgrade-start[1234]:            56|     ExecStartPre = [
Nov 08 03:11:58 pg-cluster-2 nixos-upgrade-start[1234]:            57|       "${pkgs.pgbackrest}/bin/pgbackrest --config=${pgBackrestConf} check"
Nov 08 03:11:58 pg-cluster-2 nixos-upgrade-start[1234]:              |                                              ^
Nov 08 03:11:58 pg-cluster-2 nixos-upgrade-start[1234]:            58|     ];
Nov 08 03:11:58 pg-cluster-2 systemd[1]: nixos-upgrade.service: Main process exited, code=exited, status=1/FAILURE
Nov 08 03:11:59 pg-cluster-2 nixos-upgrade-post-check[2301]: [2026-11-08T03:11:59+09:00] [pg-cluster-2] current profile equals pre-upgrade profile; skipping rollback
Nov 08 03:11:59 pg-cluster-2 nixos-upgrade-post-check[2301]: [2026-11-08T03:11:59+09:00] [pg-cluster-2] wrote nixos_upgrade_last_status 0
Nov 08 03:11:59 pg-cluster-2 systemd[1]: nixos-upgrade.service: Failed with result 'exit-code'.
Nov 08 03:11:59 pg-cluster-2 systemd[1]: Failed to start NixOS Upgrade.
Nov 08 03:12:30 pg-cluster-2 patroni[812]: 2026-11-08 03:12:30,114 INFO: no action. I am (pg-cluster-2), a secondary, and following a leader (pg-cluster-1)
"""
ARTICLES=[
(1,"Argo CD 3.2 で ApplicationSet の progressive sync が GA","段階的な同期を本番利用できるようになった。"),
(2,"新作スマホゲームの売上ランキング","今月のトップ 10。"),
(3,"NixOS 26.11 のリリースノート要約","systemd 259、nixos-rebuild-ng が既定に。"),
(4,"PostgreSQL 19 beta の論理レプリケーション改善","フェイルオーバー時のスロット引き継ぎが簡単に。"),
(5,"芸能ニュース: 人気俳優が結婚","詳細は記事で。"),
(6,"llama.cpp が ROCm で MTP 投機的デコードを高速化","RDNA3 で 1.3 倍。"),
(7,"Proxmox VE 9.2 で SDN の EVPN が改善","Fabric 設定の UI が刷新。"),
(8,"週末のおすすめレシピ 5 選","簡単な作り置き。"),
(9,"SeaweedFS 4.0 で Raft のリーダー選出が安定化","ネットワーク分断時の再選出が速くなった。"),
(10,"Talos Linux 1.12 で KubeSpan の性能改善","WireGuard の MTU 自動調整。"),
(11,"為替相場の見通し","円安が続くか。"),
(12,"VictoriaLogs 1.40 で LogsQL のパイプ処理追加","集計クエリが書きやすくなった。"),
]
J1="""あなたは自宅で Proxmox・Talos k8s・NixOS LXC・PostgreSQL(Patroni)・SeaweedFS・ローカル LLM を運用している技術者向けの、朝の技術ニュースラジオの台本作家である。
次の候補記事から、この聞き手に最も役立つ記事をちょうど 4 本選び、2 人 (A, B) の掛け合いの台本を作れ。

候補記事 (id, タイトル, 概要):
""" + "\n".join(f"{i}. {t} — {s}" for i,t,s in ARTICLES) + """

出力は次の JSON オブジェクトだけにする (コードフェンスや説明文を付けない):
{"selected":[{"id":<整数>,"reason":"<60 文字以内>"}], "script":[{"speaker":"A" または "B","ref":<話題にしている記事の id>,"text":"<80 文字以内>"}]}
制約:
- selected はちょうど 4 件、id は候補に存在し重複しない。
- script は 8〜12 行。speaker は A から始めて A, B を交互にする。
- script の ref は selected の id のいずれかで、selected の 4 本すべてが少なくとも 1 回は ref に現れる。
- reason は 60 文字以内、text は 80 文字以内 (文字数は Python の len で数える)。
"""
E1_FILE="nix/hosts/lm-server/llama-cpp.nix"
def e1_prompt():
    src=open(f"{REPO}/{E1_FILE}").read()
    return f"""次のファイル {E1_FILE} を修正する。
変更内容:
- コンテキスト長を 65536 から 32768 に下げる。
- KV キャッシュの型を K・V とも q4_0 から q8_0 に上げる。
- 上の 2 つの値に関するコメント (「64K 確保する」「q4_0 に量子化する」「q8_0 では 64K・48K ともに VRAM 不足」の箇所) を、新しい値と矛盾しない内容に書き換える。それ以外の行は変えない。
出力は `patch -p1` でそのまま当てられる unified diff だけにする (--- a/{E1_FILE} と +++ b/{E1_FILE} のヘッダを付け、コードフェンスや説明文を付けない)。

```nix
{src}```
"""
