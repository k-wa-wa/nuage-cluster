"""MVS をバッチ処理基盤として Linux 側から扱うための CLI。

サブコマンド:
  submit        JCL を投入し、終了を待って、出力と判定結果を返す
  apply-config  Git で管理している MVS 内の設定 (PDS メンバー) を反映する

ジョブの入口はカードリーダ (127.0.0.1:3505)、出口は 1403 プリンタ (prt00e.txt) である。
JES2 はジョブごとに「START JOB n 名前」「END JOB n 名前」のバナー行を印字するため、
投入前のプリンタ出力の末尾位置を覚えておき、そこから先に自分の END 行が現れたら完了とみなす。
したがって MSGCLASS=A (プリンタ 1) のジョブだけを扱う。
"""

import argparse
import fcntl
import hashlib
import json
import os
import re
import signal
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

STATE_DIR = Path(os.environ.get("MVS_STATE_DIR", "/var/lib/mainframe"))
PRINTER = STATE_DIR / "printers" / "prt00e.txt"
CONSOLE_LOG = STATE_DIR / "mvslog.txt"
READER = ("127.0.0.1", 3505)

# JCL の 1 行は 80 桁で、72 桁目は継続記号、73 桁目以降は連番欄である
JCL_MAX_COLUMNS = 71
DATA_MAX_COLUMNS = 72

# 再 IPL しないと反映されないデータセット
REQUIRES_IPL = {"SYS1.PARMLIB"}
# 書き換えたあとにオペレータコマンドが要るデータセット。
# ZTIMER は起動時に予定表を読み、次の予定時刻に自分を起こす ($TA) ため、起動し直して読み直させる
REQUIRES_COMMAND = {"SYS2.CONTROL": "/S ZTIMER"}
HERCULES_CMD_URL = "http://127.0.0.1:8038/cgi-bin/tasks/cmd"


class JobResult:
    def __init__(self, jobname, output):
        self.jobname = jobname
        self.output = output
        self.cond_codes = [int(c) for c in re.findall(r"IEF142I .* COND CODE (\d{4})", output)]
        self.abends = re.findall(r"IEF450I .* ABEND (\S+)", output)
        self.jcl_error = bool(re.search(r"IEF452I .* JCL ERROR", output))

    @property
    def max_cc(self):
        return max(self.cond_codes, default=0)

    def ok(self, max_cc):
        return not self.abends and not self.jcl_error and bool(self.cond_codes) and self.max_cc <= max_cc

    def summary(self):
        if self.jcl_error:
            return f"{self.jobname}: JCL ERROR"
        if self.abends:
            return f"{self.jobname}: ABEND {' '.join(self.abends)}"
        return f"{self.jobname}: MAXCC={self.max_cc:04d}"


def jobname_of(jcl):
    m = re.match(r"//([A-Z@#$][A-Z0-9@#$]{0,7})\s+JOB\s", jcl)
    if not m:
        raise SystemExit("JCL の 1 行目が JOB 文ではない")
    return m.group(1)


def check_columns(lines, limit, what):
    for i, line in enumerate(lines, 1):
        if len(line) > limit:
            raise SystemExit(f"{what} の {i} 行目が {limit} 桁を超えている: {line!r}")


def wait_until_ready(timeout):
    """MVS の起動完了 (TSO がログオンを受け付け始めた = JES2 も動いている) を待つ。

    IPL 中にカードリーダへ接続すると、IPL 中のコンソールへの自動応答が取りこぼされ、
    IPL が止まることがあった。そのため起動が終わるまでリーダには触らない。
    mvslog.txt (コンソールの記録) は hercules.service の起動前に消されるため、前回の IPL の記録は見ない。
    """
    deadline = time.monotonic() + timeout
    while True:
        if CONSOLE_LOG.exists() and b"IKT007I TCAS ACCEPTING LOGONS" in CONSOLE_LOG.read_bytes():
            return
        if time.monotonic() > deadline:
            raise SystemExit(f"{timeout} 秒以内に MVS の起動が完了しなかった")
        time.sleep(2)


def send_to_reader(jcl, timeout):
    """カードリーダへ JCL を送る。Hercules がまだ待ち受けていないことがあるため再試行する"""
    deadline = time.monotonic() + timeout
    while True:
        try:
            with socket.create_connection(READER, timeout=10) as s:
                s.sendall(jcl.encode("ascii"))
            return
        except OSError:
            if time.monotonic() > deadline:
                raise
            time.sleep(2)


def wait_for_job(jobname, offset, timeout):
    """プリンタ出力の offset 以降に、jobname の START から END までが揃うのを待つ"""
    start_re = re.compile(rf"\*\*\*\*A\s+START\s+JOB\s+(\d+)\s+{re.escape(jobname)}\s")
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        size = PRINTER.stat().st_size
        if size < offset:
            # 稼働中にプリンタ出力が空にされた
            offset = 0
        with PRINTER.open("rb") as f:
            f.seek(offset)
            text = f.read().decode("ascii", errors="replace").replace("\f", "\n")
        starts = list(start_re.finditer(text))
        if starts:
            jobno = starts[-1].group(1)
            end_re = re.compile(rf"\*\*\*\*A\s+END\s+JOB\s+{jobno}\s+{re.escape(jobname)}\s.*")
            end = end_re.search(text, starts[-1].end())
            if end:
                # 先頭のバナー (ジョブ名の大きな文字) から END 行までを返す
                return text[: end.end()] + "\n"
        time.sleep(2)
    raise SystemExit(f"{jobname}: {timeout} 秒以内に終了しなかった")


def submit(jcl, timeout):
    jcl = jcl if jcl.endswith("\n") else jcl + "\n"
    jobname = jobname_of(jcl)
    check_columns(
        [line for line in jcl.splitlines() if line.startswith("//")],
        JCL_MAX_COLUMNS,
        "JCL",
    )
    wait_until_ready(timeout)
    # 同時に投入すると出力の切り出しが混ざるため、mvsctl 同士は 1 本ずつ流す
    with PRINTER.open("rb") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        offset = PRINTER.stat().st_size
        send_to_reader(jcl, timeout)
        output = wait_for_job(jobname, offset, timeout)
    return JobResult(jobname, output)


# ---------------------------------------------------------------- apply-config


def job_card(jobname, description, user, password):
    return (
        f"//{jobname:<8} JOB (NUAGE),'{description}',CLASS=A,MSGCLASS=A,\n"
        f"//             MSGLEVEL=(1,1),USER={user},PASSWORD={password}\n"
    )


def load_members(config_dir):
    """<データセット名>/<メンバー名> のファイル群を {(dsn, member): 内容} にする"""
    members = {}
    for path in sorted(Path(config_dir).glob("*/*")):
        dsn, member = path.parent.name, path.name
        # エディタや OS が作る隠しファイルは対象外とする (メンバー名は . で始まれない)
        if member.startswith("."):
            continue
        if not re.fullmatch(r"[A-Z@#$][A-Z0-9@#$]{0,7}", member):
            raise SystemExit(f"メンバー名として不正: {path}")
        lines = path.read_text(encoding="ascii").splitlines()
        check_columns(lines, DATA_MAX_COLUMNS, str(path))
        # IEBUPDTE は ./ で始まる行を制御文とみなし、入力は $$ の行で終わる (DD DATA,DLM=$$)
        if any(line.startswith(("./", "$$")) for line in lines):
            raise SystemExit(f"./ または $$ で始まる行は書けない: {path}")
        members[(dsn, member)] = "\n".join(lines) + "\n"
    return members


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def build_update_job(members, datasets, user, password):
    """データセットごとに IEBUPDTE のステップを作る。ADD は既存メンバーを置き換える (冪等)。
    メンバーに JCL (// で始まる行) を含められるよう、入力は DD DATA で渡す。

    datasets (まだ無いデータセット) は、先に IEFBR14 で作る。
    DISP=MOD で「無ければ作る」とすると PDS のディレクトリが初期化されず開けなくなるため、
    存在の確認 (existing_datasets) と作成を分け、作成は DISP=NEW で行う"""
    jcl = job_card("MVSCONF", "NUAGE MVS-CONFIG", user, password)
    if datasets:
        jcl += "//ALLOC    EXEC PGM=IEFBR14\n"
        for i, ds in enumerate(datasets, 1):
            jcl += (
                f"//DS{i:<6} DD DSN={ds['dsn']},DISP=(NEW,CATLG),\n"
                f"//             UNIT={ds['unit']},VOL=SER={ds['volser']},\n"
                f"//             SPACE={ds['space']},\n"
                f"//             DCB={ds['dcb']}\n"
            )
    datasets = sorted({dsn for dsn, _ in members})
    for i, dsn in enumerate(datasets, 1):
        jcl += (
            f"//STEP{i:<4} EXEC PGM=IEBUPDTE,PARM=NEW\n"
            "//SYSPRINT DD SYSOUT=*\n"
            f"//SYSUT2   DD DSN={dsn},DISP=SHR\n"
            "//SYSIN    DD DATA,DLM=$$\n"
        )
        for (d, member), content in members.items():
            if d == dsn:
                jcl += f"./ ADD NAME={member},LIST=ALL\n{content}"
        jcl += "./ ENDUP\n$$\n"
    return jcl + "//\n"


def existing_datasets(dsns, user, password, timeout):
    """IDCAMS LISTCAT で、カタログ済みのデータセット名の集合を返す"""
    if not dsns:
        return set()
    jcl = job_card("MVSLCAT", "NUAGE MVS-CONFIG", user, password)
    jcl += "//LISTC    EXEC PGM=IDCAMS\n//SYSPRINT DD SYSOUT=*\n//SYSIN    DD *\n"
    jcl += "".join(f"  LISTCAT ENTRIES({dsn}) NAME\n" for dsn in dsns)
    jcl += "/*\n//\n"
    # 無いデータセットがあると COND CODE は 4 になるため、判定は出力の中身で行う
    result = submit(jcl, timeout)
    if result.abends or result.jcl_error:
        raise SystemExit(f"データセットの確認に失敗した: {result.summary()}")
    return {dsn for dsn in dsns if re.search(rf"NONVSAM -+ {re.escape(dsn)}\s", result.output)}


def apply_config(args):
    members = load_members(args.config_dir)
    datasets = json.loads(Path(args.datasets).read_text()) if args.datasets else []
    password = Path(args.password_file).read_text().strip()
    existing = existing_datasets([ds["dsn"] for ds in datasets], args.user, password, args.timeout)
    missing = [ds for ds in datasets if ds["dsn"] not in existing]
    for ds in missing:
        print(f"データセットを作る: {ds['dsn']}", flush=True)
    result = submit(build_update_job(members, missing, args.user, password), args.timeout)
    print(result.summary())
    if not result.ok(max_cc=0):
        sys.stdout.write(result.output)
        return 1

    # 前回反映した内容と比べ、再 IPL が必要なものが変わっていれば IPL し直す
    stamp = Path(args.stamp)
    desired = {f"{dsn}({member})": digest(c) for (dsn, member), c in members.items()}
    applied = json.loads(stamp.read_text()) if stamp.exists() else {}
    changed = sorted(k for k, v in desired.items() if applied.get(k) != v)
    stamp.write_text(json.dumps(desired, indent=2, sort_keys=True) + "\n")

    for dsn, command in REQUIRES_COMMAND.items():
        if any(k.split("(")[0] == dsn for k in changed):
            print(f"{dsn} を反映するためにコマンドを出す: {command}", flush=True)
            hercules_command(command)

    needs_ipl = [k for k in changed if k.split("(")[0] in REQUIRES_IPL]
    if needs_ipl:
        print(f"再 IPL して反映する: {', '.join(needs_ipl)}", flush=True)
        # この unit は hercules.service に PartOf しているため、再起動の巻き添えで SIGTERM を受ける。
        # 反映は済んでいるので、そのときは正常終了として扱う
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
        subprocess.run(["systemctl", "--no-block", "restart", "hercules.service"], check=True)
    else:
        print("再 IPL は不要")
    return 0


def hercules_command(command):
    """Hercules の HTTP サーバー経由でコンソールにコマンドを送る"""
    data = urllib.parse.urlencode({"cmd": command}).encode()
    with urllib.request.urlopen(HERCULES_CMD_URL, data=data, timeout=10):
        pass


# ---------------------------------------------------------------- CLI


def cmd_submit(args):
    jcl = Path(args.jcl).read_text(encoding="ascii") if args.jcl != "-" else sys.stdin.read()
    result = submit(jcl, args.timeout)
    if args.output:
        Path(args.output).write_text(result.output)
    else:
        sys.stdout.write(result.output)
    print(result.summary(), file=sys.stderr)
    return 0 if result.ok(args.max_cc) else 1


def main():
    parser = argparse.ArgumentParser(prog="mvsctl")
    sub = parser.add_subparsers(required=True)

    p = sub.add_parser("submit", help="JCL を投入して終了を待つ")
    p.add_argument("jcl", help="JCL ファイル (- で標準入力)")
    p.add_argument("--output", help="ジョブの出力を書き出すファイル (省略時は標準出力)")
    p.add_argument("--max-cc", type=int, default=0, help="成功とみなす最大の COND CODE")
    p.add_argument("--timeout", type=int, default=600)
    p.set_defaults(func=cmd_submit)

    p = sub.add_parser("apply-config", help="MVS 内の設定を Git の内容に揃える")
    p.add_argument("config_dir")
    p.add_argument("--user", required=True)
    p.add_argument("--password-file", required=True)
    p.add_argument("--datasets", help="無ければ作るデータセットの定義 (JSON)")
    p.add_argument("--stamp", default=str(STATE_DIR / "mvs-config.applied.json"))
    p.add_argument("--timeout", type=int, default=600)
    p.set_defaults(func=apply_config)

    args = parser.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
