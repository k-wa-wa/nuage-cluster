"""MVS をバッチ処理基盤として Linux 側から扱うための CLI。

サブコマンド:
  submit         JCL を投入し、終了を待って、出力と判定結果を返す
  apply-config   Git で管理している MVS 内の設定 (PDS メンバー) を反映する。
                 KICKS の導入と、業務アプリのビルドジョブも流す
  install-kicks  KICKS を導入する (導入済みなら何もしない)
  build          業務アプリのビルドジョブのうち、前回から変わったものを流す

ジョブの入口はカードリーダ (127.0.0.1:3505)、出口は 1403 プリンタ (prt00e.txt) である。
JES2 はジョブの出力を「START JOB n 名前」「END JOB n 名前」のバナー行で挟んで印字するため、
投入前のプリンタ出力の末尾位置を覚えておき、そこから先に自分のジョブの出力が揃ったら完了とみなす。
したがって MSGCLASS=A (プリンタ 1) のジョブだけを扱う。
バイナリのデータ (KICKS の XMI) を含むジョブは、EBCDIC のカードリーダ (127.0.0.1:3506) に流す。
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
# 変換しない (EBCDIC の) カードリーダ。80 バイトのカードをそのまま読む (hercules.cnf の 001A)
EBCDIC_READER = ("127.0.0.1", 3506)

# JCL の 1 行は 80 桁で、72 桁目は継続記号、73 桁目以降は連番欄である
JCL_MAX_COLUMNS = 71
DATA_MAX_COLUMNS = 72

# 再 IPL しないと反映されないデータセット
REQUIRES_IPL = {"SYS1.PARMLIB"}
# 書き換えたあとにオペレータコマンドが要るデータセット。
# ZTIMER は起動時に予定表を読み、次の予定時刻に自分を起こす ($TA) ため、起動し直して読み直させる
# RAKF は権限表を起動時に読み込むため、RAKFPROF で読み直させる
REQUIRES_COMMAND = {"SYS2.CONTROL": "/S ZTIMER", "SYS1.SECURE.CNTL": "/S RAKFPROF"}
HERCULES_CMD_URL = "http://127.0.0.1:8038/cgi-bin/tasks/cmd"


class JobResult:
    def __init__(self, jobname, output):
        self.jobname = jobname
        self.output = output
        self.cond_codes = [int(c) for c in re.findall(r"IEF142I .* COND CODE (\d{4})", output)]
        self.abends = re.findall(r"IEF450I .* ABEND (\S+)", output)
        # IEF452I: ジョブ全体が JCL エラーで動かなかった / IEF453I: 途中のステップの JCL エラーでジョブが失敗した
        self.jcl_error = bool(re.search(r"IEF45[23]I .* JCL ERROR", output))

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


def send_to_reader(deck, reader, timeout):
    """カードリーダへデッキ (バイト列) を送る。Hercules がまだ待ち受けていないことがあるため再試行する"""
    deadline = time.monotonic() + timeout
    while True:
        try:
            with socket.create_connection(reader, timeout=10) as s:
                s.sendall(deck)
            return
        except OSError:
            if time.monotonic() > deadline:
                raise
            time.sleep(2)


def wait_for_job(jobname, offset, timeout):
    """プリンタ出力の offset 以降から、jobname のジョブの出力を全部受け取るまで待つ。

    動的に割り当てた SYSOUT (TSO の RECEIVE が呼ぶ IEBCOPY の出力など) は、ジョブの途中でも
    START と END のバナーに挟まれた別の区切りとして先に印字される。そのため最初の END では
    終わったと言えない。ジョブログ ($HASP395 ... ENDED、JCL エラーで動かなかったなら IEF452I) を
    含む区切りの END が出たところで完了とみなし、そこまでの区切りをまとめて返す
    """
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
        first = start_re.search(text)
        if first:
            jobno = first.group(1)
            name = re.escape(jobname)
            done = re.search(rf"JOB\s+{jobno}\s+(\$HASP395 {name}\s+ENDED|IEF452I {name}\s)", text)
            end = done and re.compile(rf"\*\*\*\*A\s+END\s+JOB\s+{jobno}\s+{name}\s.*").search(text, done.end())
            if end:
                # 先頭のバナー (ジョブ名の大きな文字) から、ジョブログを含む区切りの END 行までを返す
                return text[: end.end()] + "\n"
        time.sleep(2)
    raise SystemExit(f"{jobname}: {timeout} 秒以内に終了しなかった")


def submit(jcl, timeout):
    jcl = jcl if jcl.endswith("\n") else jcl + "\n"
    check_columns(
        [line for line in jcl.splitlines() if line.startswith("//")],
        JCL_MAX_COLUMNS,
        "JCL",
    )
    return submit_deck(jcl.encode("ascii"), jobname_of(jcl), READER, timeout)


def submit_deck(deck, jobname, reader, timeout):
    """デッキをカードリーダに流し、ジョブの出力を待って結果を返す"""
    wait_until_ready(timeout)
    # 同時に投入すると出力の切り出しが混ざるため、mvsctl 同士は 1 本ずつ流す
    with PRINTER.open("rb") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        offset = PRINTER.stat().st_size
        send_to_reader(deck, reader, timeout)
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


def build_update_job(members, datasets, user, password, migrations=""):
    """データセットごとに IEBUPDTE のステップを作る。ADD は既存メンバーを置き換える (冪等)。
    メンバーに JCL (// で始まる行) を含められるよう、入力は DD DATA で渡す。

    datasets (まだ無いデータセット) は、先に作る (create_steps)。
    DISP=MOD で「無ければ作る」とすると PDS のディレクトリが初期化されず開けなくなるため、
    存在の確認 (existing_datasets) と作成を分け、作成は DISP=NEW で行う"""
    jcl = job_card("MVSCONF", "NUAGE MVS-CONFIG", user, password) + migrations
    for i, ds in enumerate(datasets, 1):
        jcl += create_steps(f"C{i:02d}", ds)
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


def create_steps(step, ds):
    """データセットを作る JCL ステップ。type ごとに作り方を変える

    PO : IEFBR14 で割り当てる (PDS のディレクトリは割り当て時に作られる)
    ALIAS: 高位修飾子 (dsn) の別名をユーザーカタログ (catalog) に向ける。マスターカタログは
           既定のバッチ利用者が更新できないため、アプリのデータセットはユーザーカタログに入れる
    PS : IEBGENER で空のデータを書く。IEFBR14 で割り当てただけの順編成は EOF が無く、読むとごみが返るため
    GDG: IDCAMS で GDG ベースを定義し、空の初代 (+1) を作る。MVS 3.8j では世代の作成に
         型紙 (モデル DSCB) が要るため、model に挙げたカタログ済みデータセットを DCB=(model,...) で参照する
    """
    kind = ds.get("type", "PO")
    if kind == "ALIAS":
        return "\n".join([
            f"//{step:<8} EXEC PGM=IDCAMS",
            "//SYSPRINT DD SYSOUT=*",
            "//SYSIN    DD *",
            f"  DEFINE ALIAS (NAME({ds['dsn']}) RELATE({ds['catalog']}))",
            "/*",
        ]) + "\n"
    alloc = [
        f"//             UNIT={ds['unit']},VOL=SER={ds['volser']},",
        f"//             SPACE={ds['space']},",
    ]

    def empty_copy(name):
        return [
            f"//{name:<8} EXEC PGM=IEBGENER",
            "//SYSPRINT DD SYSOUT=*",
            "//SYSIN    DD DUMMY",
            f"//SYSUT1   DD DUMMY,DCB={ds['dcb']}",
        ]

    if kind == "PO":
        lines = [
            f"//{step:<8} EXEC PGM=IEFBR14",
            f"//DS       DD DSN={ds['dsn']},DISP=(NEW,CATLG),",
            *alloc,
            f"//             DCB={ds['dcb']}",
        ]
    elif kind == "PS":
        lines = [
            *empty_copy(step),
            f"//SYSUT2   DD DSN={ds['dsn']},DISP=(NEW,CATLG),",
            *alloc,
            f"//             DCB={ds['dcb']}",
        ]
    elif kind == "GDG":
        lines = [
            f"//{step + 'D':<8} EXEC PGM=IDCAMS",
            "//SYSPRINT DD SYSOUT=*",
            "//SYSIN    DD *",
            f"  DEFINE GDG (NAME({ds['dsn']}) LIMIT({ds['limit']}) -",
            "              SCRATCH NOEMPTY)",
            "/*",
            *empty_copy(step + "G"),
            f"//SYSUT2   DD DSN={ds['dsn']}(+1),DISP=(NEW,CATLG),",
            *alloc,
            f"//             DCB=({ds['model']},",
            f"//             {ds['dcb'].strip('()')})",
        ]
    else:
        raise SystemExit(f"不明なデータセットの種類: {kind} ({ds['dsn']})")
    return "\n".join(lines) + "\n"


def migrate_steps(alias, datasets):
    """別名を作る前に、その高位修飾子のデータセットがマスターカタログにあれば、ユーザーカタログへ移す。

    別名を作ると、その高位修飾子の名前はユーザーカタログで引かれるようになり、マスターカタログの
    登録は見えなくなる。そこで、登録だけを消し (DELETE NOSCRATCH。データは消えない)、別名を作り、
    宣言どおりの装置とボリュームでユーザーカタログに登録し直す (DEFINE NONVSAM)
    """
    lines = [
        "//MIGRATE  EXEC PGM=IDCAMS",
        "//SYSPRINT DD SYSOUT=*",
        "//SYSIN    DD *",
    ]
    lines += [f"  DELETE {ds['dsn']} NOSCRATCH" for ds in datasets]
    lines.append(f"  DEFINE ALIAS (NAME({alias['dsn']}) RELATE({alias['catalog']}))")
    for ds in datasets:
        lines += [
            f"  DEFINE NONVSAM (NAME({ds['dsn']}) -",
            f"         DEVICETYPES({ds['unit']}) VOLUMES({ds['volser']})) -",
            f"         CATALOG({alias['catalog']})",
        ]
    lines.append("/*")
    return "\n".join(lines) + "\n"


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
    return {dsn for dsn in dsns if re.search(rf"(NONVSAM|GDG BASE|ALIAS) -+ {re.escape(dsn)}\s", result.output)}


def apply_config(args):
    members = load_members(args.config_dir)
    datasets = json.loads(Path(args.datasets).read_text()) if args.datasets else []
    password = Path(args.password_file).read_text().strip()
    existing = existing_datasets([ds["dsn"] for ds in datasets], args.user, password, args.timeout)
    missing = [ds for ds in datasets if ds["dsn"] not in existing]
    # まだ無い別名の高位修飾子で、すでにあるデータセットはマスターカタログに登録されている
    migrations = ""
    for alias in [ds for ds in missing if ds.get("type") == "ALIAS"]:
        under = [ds for ds in datasets if ds["dsn"].startswith(alias["dsn"] + ".") and ds["dsn"] in existing]
        if any(ds.get("type") == "GDG" for ds in under):
            raise SystemExit(f"マスターカタログにある GDG は移せない。手で移してから再実行する: {alias['dsn']}")
        if under:
            for ds in under:
                print(f"ユーザーカタログ {alias['catalog']} へ移す: {ds['dsn']}", flush=True)
            migrations += migrate_steps(alias, [ds for ds in under if ds.get("type", "PO") in ("PO", "PS")])
            missing.remove(alias)
    for ds in missing:
        print(f"データセットを作る: {ds['dsn']}", flush=True)
    result = submit(build_update_job(members, missing, args.user, password, migrations), args.timeout)
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

    # KICKS の導入と業務アプリのビルドは、権限表 (RAKF) を読み直させた後に行う。
    # 失敗しても、再 IPL が必要な設定の反映は続ける
    failed = False
    installed = False
    if args.kicks_xmi:
        try:
            installed = install_kicks(args.kicks_xmi, args.user, password, args.timeout)
        except SystemExit as e:
            print(e, flush=True)
            failed = True
    if args.builds and not failed:
        # データセットを作った (DASD を初期化したなど) か KICKS を導入し直したときは、記録にかかわらず全部流す
        force = installed or bool(missing)
        failed = run_builds(args.builds, args.build_stamp, args.timeout, force=force) > 0

    needs_ipl = [k for k in changed if k.split("(")[0] in REQUIRES_IPL]
    if needs_ipl:
        print(f"再 IPL して反映する: {', '.join(needs_ipl)}", flush=True)
        # この unit は hercules.service に PartOf しているため、再起動の巻き添えで SIGTERM を受ける。
        # 反映は済んでいるので、そのときは正常終了として扱う
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
        subprocess.run(["systemctl", "--no-block", "restart", "hercules.service"], check=True)
    else:
        print("再 IPL は不要")
    return 1 if failed else 0


def hercules_command(command):
    """Hercules の HTTP サーバー経由でコンソールにコマンドを送る"""
    data = urllib.parse.urlencode({"cmd": command}).encode()
    with urllib.request.urlopen(HERCULES_CMD_URL, data=data, timeout=10):
        pass


# ---------------------------------------------------------------- KICKS


# 導入済みの印。導入ジョブの最後のステップが作る
KICKS_RECEIPT = "KICKS.V1R5M0.INSTALL"
KICKS_VOLUME = ("3380", "PUB000")

# 配布物の XMI の中身 (区分データセット BIGPDS) のメンバーと、それを受け取るデータセット。
# 高位修飾子 KICKS の下に、KICKS の流儀どおり利用者用 (KICKS.KICKS.V1R5M0.*) と
# システム用 (KICKS.KICKSSYS.V1R5M0.*) の 2 系統で置く
KICKS_MEMBERS = {
    "HCB2": "KICKS.KICKS.V1R5M0.CB2",
    "HCOB": "KICKS.KICKS.V1R5M0.COB",
    "HCOBCOPY": "KICKS.KICKS.V1R5M0.COBCOPY",
    "HGCC": "KICKS.KICKS.V1R5M0.GCC",
    "HGCCCOPY": "KICKS.KICKS.V1R5M0.GCCCOPY",
    "HINSTLIB": "KICKS.KICKS.V1R5M0.INSTLIB",
    "HKIKRPL": "KICKS.KICKS.V1R5M0.KIKRPL",
    "HMAPSRC": "KICKS.KICKS.V1R5M0.MAPSRC",
    "HOPIDS": "KICKS.KICKS.V1R5M0.OPIDS",
    "HSPUFI": "KICKS.KICKS.V1R5M0.SPUFI.IN",
    "SCMDPROC": "KICKS.KICKSSYS.V1R5M0.CLIST",
    "SCOB": "KICKS.KICKSSYS.V1R5M0.COB",
    "SCOBCOPY": "KICKS.KICKSSYS.V1R5M0.COBCOPY",
    "SDOC": "KICKS.KICKSSYS.V1R5M0.DOC",
    "SGCC": "KICKS.KICKSSYS.V1R5M0.GCC",
    "SGCCCOPY": "KICKS.KICKSSYS.V1R5M0.GCCCOPY",
    "SINSTLIB": "KICKS.KICKSSYS.V1R5M0.INSTLIB",
    "SKIKRPL": "KICKS.KICKSSYS.V1R5M0.KIKRPL",
    "SMACLIB": "KICKS.KICKSSYS.V1R5M0.MACLIB",
    "SMAPSRC": "KICKS.KICKSSYS.V1R5M0.MAPSRC",
    "SPROCLIB": "KICKS.KICKSSYS.V1R5M0.PROCLIB",
    "SPROCLIZ": "KICKS.KICKSSYS.V1R5M0.PROCLIBZ",
    "SSKIKLOD": "KICKS.KICKSSYS.V1R5M0.SKIKLOAD",
    "STESTCOB": "KICKS.KICKSSYS.V1R5M0.TESTCOB",
    "STESTGCC": "KICKS.KICKSSYS.V1R5M0.TESTGCC",
    "STESTFIL": "KICKS.KICKSSYS.V1R5M0.TESTFILE",
}

# 配布物の JCL・CLIST・PROC は、作者の環境の名前 (K.S. / K.U. / HERC01) で書かれている。
# 配布物の CLIST(KFIX) は、それを導入先の名前に置き換える (KICKS 付属の PDSUPDTE を呼ぶ)。
# KFIX は TSO で対話的に動くため、同じ置き換えをバッチで行う。置き換えの指定は KFIX と同じで、
# 高位修飾子 KICKS、Turnkey MVS (MVS 3.8j) 向け (端末制御を 2$ にする) を選んだものにあたる。
# 最後の行は MVS/CE 向けの追加である (COBOL のライブラリが SYS1.COBLIB ではなく SYSC.COBLIB)
KICKS_FIX_CARDS = [
    "HERC01<KICKS<",
    "K.S.<KICKS.S.<",
    "K.U.<KICKS.U.<",
    "'K.<'KICKS.<",
    "=K.<=KICKS.<",
    "(K.<(KICKS.<",
    ".S.<.KICKSSYS.<",
    ".U.<.KICKS.<",
    "TCP(1$)<TCP(2$)<",
    "SYS1.COBLIB<SYSC.COBLIB<",
]
# 置き換えるデータセット (PDSUPDTE は @ で始まる DD を順に処理する)。
# 置き換えの無いデータセットを渡すと RC 4 になるため、置き換えのあるものだけを渡す
KICKS_FIX_DDS = {
    "@UCB2": "KICKS.KICKS.V1R5M0.CB2",
    "@UCOB": "KICKS.KICKS.V1R5M0.COB",
    "@UCOBCPY": "KICKS.KICKS.V1R5M0.COBCOPY",
    "@UGCC": "KICKS.KICKS.V1R5M0.GCC",
    "@UINST": "KICKS.KICKS.V1R5M0.INSTLIB",
    "@UMAPS": "KICKS.KICKS.V1R5M0.MAPSRC",
    "@SCMD": "KICKS.KICKSSYS.V1R5M0.CLIST",
    "@SCOB": "KICKS.KICKSSYS.V1R5M0.COB",
    "@SGCC": "KICKS.KICKSSYS.V1R5M0.GCC",
    "@SINST": "KICKS.KICKSSYS.V1R5M0.INSTLIB",
    "@SMAPS": "KICKS.KICKSSYS.V1R5M0.MAPSRC",
    "@SPROC": "KICKS.KICKSSYS.V1R5M0.PROCLIB",
    "@SPROCZ": "KICKS.KICKSSYS.V1R5M0.PROCLIBZ",
    "@STESTC": "KICKS.KICKSSYS.V1R5M0.TESTCOB",
    "@STESTG": "KICKS.KICKSSYS.V1R5M0.TESTGCC",
    "@STESTF": "KICKS.KICKSSYS.V1R5M0.TESTFILE",
}

# KICKS 自身の VSAM (一時記憶域・一時データのキューと、デバッガのソース表示用)。
# 名前, キー長, レコード長 (最小 最大), 容量, SPANNED か。導入手順の LODTEMP・LODINTRA・LOADSDB にあたる
KICKS_VSAM = [
    ("KICKS.KICKSSYS.V1R5M0.KIKINTRA", 6, "19 32767", "TRACKS(15 15)", True),
    ("KICKS.KICKSSYS.V1R5M0.KIKTEMP", 18, "19 32767", "TRACKS(15 15)", True),
    ("KICKS.KICKS.V1R5M0.SDB", 14, "92 92", "CYLINDERS(10 10)", False),
]

# KICKS の CLIST は利用者用の SKIKLOAD (KICKS.KICKS.V1R5M0.SKIKLOAD) も連結するが、配布物には無く、
# 割り当てに失敗して KICKS が起動しない (既知の誤り)。CLIST は直さず、空のデータセットを置く
KICKS_EMPTY_LOADLIB = "KICKS.KICKS.V1R5M0.SKIKLOAD"


def kicks_install_jcl(user, password):
    """KICKS の導入ジョブの JCL を返す。"@@XMI@@" の行に配布物の XMI (バイナリ) を差し込み、
    "@DLM@" を XMI の中に現れない区切りに置き換えて使う (kicks_install_deck)

    1. 前回の途中までの導入の跡を消す
    2. XMI をカードとして読み、データセットにする (EBCDIC のカードリーダで、変換せずに読む)
    3. TSO の RECEIVE (NJE38) で XMI を受け取り、さらにその中の 26 個の XMIT を受け取る
       (配布物の手順の RECV370 は MVS/CE に無い)
    4. 受け取ったデータセットが揃っているかを確かめる
    5. 名前の置き換え (KFIX にあたる)、空の利用者用 SKIKLOAD、KICKS 自身の VSAM を作る
    6. 中間のデータセットを消し、導入済みの印 (KICKS.V1R5M0.INSTALL) を作る
    """
    unit, vol = KICKS_VOLUME
    temps = ["KICKS.V1R5M0.XMI", "KICKS.V1R5M0.BIGPDS"]
    lines = [
        "//KICKSINS JOB (NUAGE),'NUAGE KICKS INSTALL',CLASS=A,MSGCLASS=A,",
        f"//             MSGLEVEL=(1,1),USER={user},PASSWORD={password}",
        "//*",
        "//* INSTALL KICKS FOR TSO V1R5M0 (BY NUAGE-CLUSTER MVSCTL)",
        "//*",
        "//CLEAN    EXEC PGM=IDCAMS",
        "//SYSPRINT DD SYSOUT=*",
        "//SYSIN    DD *",
    ]
    lines += [f"  DELETE {dsn} NONVSAM" for dsn in [*temps, *KICKS_MEMBERS.values(), KICKS_EMPTY_LOADLIB, KICKS_RECEIPT]]
    lines += [f"  DELETE {name} CLUSTER" for name, *_ in KICKS_VSAM]
    lines += [
        "  SET MAXCC = 0",
        "/*",
        "//LOAD     EXEC PGM=IEBGENER,COND=(0,NE)",
        "//SYSPRINT DD SYSOUT=*",
        "//SYSIN    DD DUMMY",
        f"//SYSUT2   DD DSN={temps[0]},DISP=(NEW,CATLG),",
        f"//             UNIT={unit},VOL=SER={vol},SPACE=(TRK,(240,15),RLSE),",
        "//             DCB=(RECFM=FB,LRECL=80,BLKSIZE=3200)",
        "//SYSUT1   DD DATA,DLM=@DLM@",
        "@@XMI@@",
        "@DLM@",
        "//RECEIVE  EXEC PGM=IKJEFT01,REGION=4096K,COND=(0,NE)",
        "//SYSTSPRT DD SYSOUT=*",
        "//SYSTSIN  DD *",
        f"RECEIVE INDS('{temps[0]}') DSN('{temps[1]}') -",
        f"  VOLUME({vol})",
    ]
    for member, dsn in KICKS_MEMBERS.items():
        lines += [f"RECEIVE INDS('{temps[1]}({member})') -", f"  DSN('{dsn}') VOLUME({vol})"]
    lines += [
        "/*",
        "//* A FAILED RECEIVE MAY NOT SHOW IN THE RC OF THE TSO STEP",
        "//VERIFY   EXEC PGM=IDCAMS,COND=(0,NE)",
        "//SYSPRINT DD SYSOUT=*",
        "//SYSIN    DD *",
    ]
    lines += [f"  LISTCAT ENTRIES({dsn}) NAME" for dsn in KICKS_MEMBERS.values()]
    lines += [
        "/*",
        "//KFIX     EXEC PGM=PDSUPDTE,PARM='UPDATE',COND=(0,NE)",
        "//STEPLIB  DD DSN=KICKS.KICKSSYS.V1R5M0.SKIKLOAD,DISP=SHR",
        "//SYSTERM  DD SYSOUT=*",
        "//SYSPRINT DD SYSOUT=*",
    ]
    lines += [f"//{dd:<8} DD DSN={dsn},DISP=OLD" for dd, dsn in KICKS_FIX_DDS.items()]
    lines += ["//SYSIN    DD *", *KICKS_FIX_CARDS, "/*"]
    lines += [
        "//USKIKLOD EXEC PGM=IEFBR14,COND=(0,NE)",
        f"//DS       DD DSN={KICKS_EMPTY_LOADLIB},DISP=(NEW,CATLG),",
        f"//             UNIT={unit},VOL=SER={vol},SPACE=(TRK,(1,1,1)),",
        "//             DCB=(DSORG=PO,RECFM=U,BLKSIZE=6144)",
        "//VSAM     EXEC PGM=IDCAMS,COND=(0,NE)",
        "//SYSPRINT DD SYSOUT=*",
        "//DUMMYREC DD *",
        "99999999999999999999999999999999999",
        "/*",
        "//SYSIN    DD *",
    ]
    for name, keylen, recsize, space, spanned in KICKS_VSAM:
        lines += [
            f"  DEFINE CLUSTER (NAME({name}) INDEXED -",
            f"         VOLUMES({vol}) {space} SHAREOPTIONS(1 3) UNIQUE -",
            f"         RECORDSIZE({recsize}){' SPANNED' if spanned else ''} KEYS({keylen} 0)) -",
            f"    DATA (NAME({name}.DATA)) -",
            f"    INDEX (NAME({name}.INDEX))",
        ]
    # 空の KSDS は開けないため、導入手順どおりダミーのレコードを 1 件入れる
    lines += [f"  REPRO INFILE(DUMMYREC) OUTDATASET({name})" for name, *_ in KICKS_VSAM]
    lines += [
        "/*",
        "//TIDY     EXEC PGM=IDCAMS,COND=(0,NE)",
        "//SYSPRINT DD SYSOUT=*",
        "//SYSIN    DD *",
        *[f"  DELETE {dsn} NONVSAM" for dsn in temps],
        "/*",
        "//RECEIPT  EXEC PGM=IEBGENER,COND=(0,NE)",
        "//SYSPRINT DD SYSOUT=*",
        "//SYSIN    DD DUMMY",
        "//SYSUT1   DD *",
        "KICKS FOR TSO V1R5M0 INSTALLED BY NUAGE-CLUSTER (MVSCTL INSTALL-KICKS)",
        "/*",
        f"//SYSUT2   DD DSN={KICKS_RECEIPT},DISP=(NEW,CATLG),",
        f"//             UNIT={unit},VOL=SER={vol},SPACE=(TRK,(1)),",
        "//             DCB=(RECFM=FB,LRECL=80,BLKSIZE=800)",
        "//",
    ]
    return lines


def kicks_install_deck(xmi, user, password):
    """導入ジョブのデッキ (EBCDIC のカードの並び) を作る"""
    if len(xmi) % 80:
        raise SystemExit("XMI が 80 バイトのカードの並びになっていない")
    starts = {bytes(xmi[i:i + 2]) for i in range(0, len(xmi), 80)}
    # インラインのデータは区切り (DLM) で終わる。XMI のカードの先頭 2 桁に現れない文字を選ぶ
    dlm = next(c for c in ("$$", "##", "@@", "><", ")(", "%%") if c.encode("cp037") not in starts)
    lines = kicks_install_jcl(user, password)
    check_columns([line for line in lines if line.startswith("//")], JCL_MAX_COLUMNS, "KICKS の導入ジョブ")
    deck = bytearray()
    for line in lines:
        if line == "@@XMI@@":
            deck += xmi
        else:
            deck += line.replace("@DLM@", dlm).ljust(80).encode("cp037")
    return bytes(deck)


def install_kicks(xmi_path, user, password, timeout):
    """KICKS を導入する。導入済み (印のデータセットがある) なら何もしない。導入したら True を返す"""
    if existing_datasets([KICKS_RECEIPT], user, password, timeout):
        print("KICKS は導入済み", flush=True)
        return False
    print("KICKS を導入する", flush=True)
    deck = kicks_install_deck(Path(xmi_path).read_bytes(), user, password)
    result = submit_deck(deck, "KICKSINS", EBCDIC_READER, timeout)
    print(result.summary(), flush=True)
    if not result.ok(max_cc=0):
        sys.stdout.write(result.output)
        raise SystemExit("KICKS の導入に失敗した")
    return True


# ---------------------------------------------------------------- build

# ビルドジョブの成功とみなす最大の COND CODE (コンパイラの警告 4 までは成功)
BUILD_MAX_CC = 4
# 前回成功したビルドジョブの内容のハッシュ
BUILD_STAMP = STATE_DIR / "mvs-build.applied.json"


def run_builds(builds_dir, stamp, timeout, force=False):
    """業務アプリのビルドジョブ (<ディレクトリ>/<名前> の JCL) のうち、前回成功したときから
    内容が変わったものを流す。成功したものだけを記録する (失敗したものは次回また流す)。
    force なら記録にかかわらず全部流す (MVS 側の資材が作り直されたとき)。失敗の数を返す"""
    stamp = Path(stamp)
    applied = {} if force or not stamp.exists() else json.loads(stamp.read_text())
    failures = 0
    for path in sorted(Path(builds_dir).iterdir()):
        jcl = path.read_text(encoding="ascii")
        if applied.get(path.name) == digest(jcl):
            continue
        print(f"ビルドジョブを流す: {path.name}", flush=True)
        result = submit(jcl, timeout)
        print(result.summary(), flush=True)
        if result.ok(max_cc=BUILD_MAX_CC):
            applied[path.name] = digest(jcl)
            stamp.write_text(json.dumps(applied, indent=2, sort_keys=True) + "\n")
        else:
            sys.stdout.write(result.output)
            failures += 1
    return failures


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


def cmd_install_kicks(args):
    install_kicks(args.xmi, args.user, Path(args.password_file).read_text().strip(), args.timeout)
    return 0


def cmd_build(args):
    return 1 if run_builds(args.builds, args.stamp, args.timeout, force=args.force) else 0


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
    p.add_argument("--kicks-xmi", help="KICKS の配布物の XMI。未導入なら導入する")
    p.add_argument("--builds", help="業務アプリのビルドジョブ (JCL) のディレクトリ。変わったものを流す")
    p.add_argument("--build-stamp", default=str(BUILD_STAMP))
    p.add_argument("--timeout", type=int, default=600)
    p.set_defaults(func=apply_config)

    p = sub.add_parser("install-kicks", help="KICKS を導入する (導入済みなら何もしない)")
    p.add_argument("xmi", help="KICKS の配布物の XMI")
    p.add_argument("--user", required=True)
    p.add_argument("--password-file", required=True)
    p.add_argument("--timeout", type=int, default=1800)
    p.set_defaults(func=cmd_install_kicks)

    p = sub.add_parser("build", help="業務アプリのビルドジョブのうち、前回から変わったものを流す")
    p.add_argument("builds", help="ビルドジョブ (JCL) のディレクトリ")
    p.add_argument("--stamp", default=str(BUILD_STAMP))
    p.add_argument("--force", action="store_true", help="前回の記録にかかわらず全部流す")
    p.add_argument("--timeout", type=int, default=600)
    p.set_defaults(func=cmd_build)

    args = parser.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
