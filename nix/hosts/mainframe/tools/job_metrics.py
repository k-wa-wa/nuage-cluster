"""MVS のバッチジョブの実行結果をコンソールログ (mvslog.txt) から読み取り、
node-exporter の textfile collector 用のメトリクス (mvs_jobs.prom) として書き出す。

Hercules の再起動で mvslog.txt が消えても直近の実行結果と最終成功時刻が失われないよう、
状態は /var/lib/mainframe/mvs-job-metrics.json に永続化する。
"""

import argparse
import json
import os
import re
import time
from pathlib import Path

STATE_DIR = Path(os.environ.get("MVS_STATE_DIR", "/var/lib/mainframe"))
CONSOLE_LOG = STATE_DIR / "mvslog.txt"

ABEND_OR_JCL_ERROR_RC = 9999

START_RE = re.compile(r"\bJOB\s+(\d+)\s+\$HASP(?:100|373)\s+(\S+)\b")
STEP_RE = re.compile(r"\bJOB\s+(\d+)\s+IEFACTRT\s+(\S+)\s*/\S+\s*/[^/]+/[^/]+/([^/]+)/(\S+)")
ABEND_RE = re.compile(r"\bJOB\s+(\d+)\s+IEF450I\s+(\S+)\s+.*ABEND")
JCL_ERR_RE = re.compile(r"\bJOB\s+(\d+)\s+IEF45[23]I\s+(\S+)\s+.*JCL ERROR")
END_RE = re.compile(r"\bJOB\s+(\d+)\s+\$HASP(?:395\s+(\S+)\s+ENDED|250\s+(\S+)\s+IS PURGED)")


def is_success(jobname, rc, steps, abend, jcl_error):
    if abend or jcl_error or not steps:
        return False
    if rc == 0:
        return True
    # LEDGER の GET ステップ (EXEC) の RC 4 は「締める日が無い (最新)」を表す正常終了
    if jobname == "LEDGER" and steps == [("EXEC", 4)]:
        return True
    # MVSLCAT (LISTCAT) の RC 4 は未作成データセットの存在確認時の正常な戻り値
    if jobname == "MVSLCAT" and rc == 4:
        return True
    return False


def parse_log(text, jobs, now):
    """text を走査して完了したジョブで jobs を更新し、次回読み始める文字位置を返す"""
    in_flight = {}
    finalized = set()
    pos = 0

    def ensure_job(jobno, jobname, line_pos):
        if jobno not in in_flight:
            in_flight[jobno] = {
                "jobname": jobname,
                "steps": [],
                "abend": False,
                "jcl_error": False,
                "start_pos": line_pos,
            }
        return in_flight[jobno]

    for line_match in re.finditer(r"[^\n]*\n", text):
        line_pos = line_match.start()
        pos = line_match.end()
        line = line_match.group(0).replace("\r", "").replace("\f", "")

        m = START_RE.search(line)
        if m:
            jobno, jobname = m.groups()
            finalized.discard(jobno)
            ensure_job(jobno, jobname, line_pos)
            continue

        m = STEP_RE.search(line)
        if m:
            jobno, step, rc_str, jobname = m.groups()
            j = ensure_job(jobno, jobname, line_pos)
            if rc_str == "NOXEC":
                pass
            elif rc_str.isdigit():
                j["steps"].append((step, int(rc_str)))
            else:
                j["abend"] = True
            continue

        m = ABEND_RE.search(line)
        if m:
            jobno, jobname = m.groups()
            j = ensure_job(jobno, jobname, line_pos)
            j["abend"] = True
            continue

        m = JCL_ERR_RE.search(line)
        if m:
            jobno, jobname = m.groups()
            j = ensure_job(jobno, jobname, line_pos)
            j["jcl_error"] = True
            continue

        m = END_RE.search(line)
        if m:
            jobno = m.group(1)
            jobname = m.group(2) or m.group(3)
            if jobno in finalized:
                continue
            j = in_flight.pop(jobno, None)
            if j is None:
                continue
            finalized.add(jobno)
            steps = j["steps"]
            abend = j["abend"]
            jcl_error = j["jcl_error"]
            if abend or jcl_error or not steps:
                rc = ABEND_OR_JCL_ERROR_RC
            else:
                rc = max(r for _, r in steps)
                # LEDGER で GET (EXEC) 以外のステップが RC 4 を返した場合は正常の RC 4 と区別する
                if jobname == "LEDGER" and rc == 4 and steps != [("EXEC", 4)]:
                    rc = ABEND_OR_JCL_ERROR_RC

            prev = jobs.get(jobname, {})
            entry = {
                "last_rc": rc,
                "last_end_timestamp_seconds": now,
            }
            if is_success(jobname, rc, steps, abend, jcl_error):
                entry["last_success_timestamp_seconds"] = now
            elif "last_success_timestamp_seconds" in prev:
                entry["last_success_timestamp_seconds"] = prev["last_success_timestamp_seconds"]
            jobs[jobname] = entry

    if in_flight:
        return min(j["start_pos"] for j in in_flight.values())
    return pos


def write_prom(jobs, prom_path):
    lines = [
        "# HELP mvs_job_last_rc Last return code of MVS batch job (max step RC, or 9999 on ABEND/JCL error).",
        "# TYPE mvs_job_last_rc gauge",
    ]
    for jobname, entry in sorted(jobs.items()):
        lines.append(f'mvs_job_last_rc{{job_name="{jobname}"}} {entry["last_rc"]}')

    lines += [
        "# HELP mvs_job_last_end_timestamp_seconds Unix timestamp when the MVS batch job last ended.",
        "# TYPE mvs_job_last_end_timestamp_seconds gauge",
    ]
    for jobname, entry in sorted(jobs.items()):
        if "last_end_timestamp_seconds" in entry:
            lines.append(
                f'mvs_job_last_end_timestamp_seconds{{job_name="{jobname}"}} {entry["last_end_timestamp_seconds"]}'
            )

    lines += [
        "# HELP mvs_job_last_success_timestamp_seconds Unix timestamp when the MVS batch job last succeeded.",
        "# TYPE mvs_job_last_success_timestamp_seconds gauge",
    ]
    for jobname, entry in sorted(jobs.items()):
        if "last_success_timestamp_seconds" in entry:
            lines.append(
                f'mvs_job_last_success_timestamp_seconds{{job_name="{jobname}"}} {entry["last_success_timestamp_seconds"]}'
            )

    prom_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = prom_path.with_suffix(".prom.tmp")
    tmp_path.write_text("\n".join(lines) + "\n")
    os.chmod(tmp_path, 0o644)
    os.replace(tmp_path, prom_path)


def main():
    parser = argparse.ArgumentParser(prog="mainframe-job-metrics")
    parser.add_argument(
        "--prom-file",
        default="/var/lib/prometheus/node-exporter/mvs_jobs.prom",
    )
    parser.add_argument(
        "--state-file",
        default=str(STATE_DIR / "mvs-job-metrics.json"),
    )
    parser.add_argument(
        "--offset-file",
        default=str(STATE_DIR / ".mvslog.offset"),
    )
    args = parser.parse_args()

    state_file = Path(args.state_file)
    offset_file = Path(args.offset_file)
    prom_file = Path(args.prom_file)

    jobs = json.loads(state_file.read_text()) if state_file.exists() else {}

    if CONSOLE_LOG.exists():
        offset = int(offset_file.read_text()) if offset_file.exists() else 0
        size = CONSOLE_LOG.stat().st_size
        if size < offset:
            # Hercules の再起動で mvslog.txt が作り直された
            offset = 0
        with CONSOLE_LOG.open("rb") as f:
            f.seek(offset)
            text = f.read().decode("ascii", errors="replace")

        now = int(time.time())
        consumed = parse_log(text, jobs, now)
        offset_file.write_text(str(offset + consumed))
        state_file.write_text(json.dumps(jobs, indent=2, sort_keys=True) + "\n")

    write_prom(jobs, prom_file)


if __name__ == "__main__":
    main()
