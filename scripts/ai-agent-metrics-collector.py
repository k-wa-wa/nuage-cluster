#!/usr/bin/env python3
"""
AI Agent 使用量メトリクスの収集と VictoriaMetrics 連携スクリプト。

Orca および autopilot で稼働した AI Agent (Claude Code, Antigravity) の
使用量（トークン数、セッション時間、autopilot 実行実績）を集計し、
Prometheus exposition format で VictoriaMetrics へ送信する。
"""

import argparse
import glob
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

KNOWN_REPOS = [
    "nuage-cluster",
    "nuage-autopilot5",
    "pechka",
    "nuage-monitoring-stack",
    "nuage-usage-ledger",
]


def normalize_identifier(val: str, default: str = "unknown") -> str:
    """メトリクスラベル用文字列の正規化（英数字・ハイフン・アンダースコア以外を置換）"""
    if not val:
        return default
    val = val.strip().lower()
    val = re.sub(r"[^a-z0-9_\-]+", "-", val)
    val = val.strip("-")
    return val or default


def normalize_repo_name(raw: str) -> str:
    """ワークスペースパスやプロジェクト名からリポジトリ名を抽出して正規化"""
    if not raw:
        return "unknown"

    # パス形式: /orca/workspaces/<repo>/... または /workspaces/<repo>/...
    m = re.search(r"/(?:orca/)?workspaces/([^/\s\'\"]+)", raw)
    if m:
        candidate = m.group(1)
        if candidate not in ("repo", "workspace", "name"):
            for known in KNOWN_REPOS:
                if candidate.startswith(known):
                    return known
            return normalize_identifier(candidate)

    # プロジェクトディレクトリ名形式: -home-nixos-orca-workspaces-<repo>-... または -tmp
    m = re.search(r"-home-nixos-orca-workspaces-([a-zA-Z0-9_\-]+)", raw)
    if m:
        part = m.group(1)
        for known in KNOWN_REPOS:
            if part.startswith(known):
                return known
        return normalize_identifier(part.split("-")[0])

    if "/projects/-tmp/" in raw or raw.endswith("-tmp"):
        return "tmp"

    return normalize_identifier(raw)


def normalize_model_name(raw: str) -> str:
    """モデル名の正規化（例: Gemini 3.8 Flash (High) -> gemini-3.8-flash-high）"""
    if not raw:
        return "unknown"
    raw = raw.strip()
    m = re.match(r"^([^(]+?)(?:\s*\(([^)]+)\))?$", raw)
    if m:
        base = m.group(1).strip()
        level = m.group(2).strip() if m.group(2) else ""
        combined = f"{base}-{level}" if level else base
        return normalize_identifier(combined)
    return normalize_identifier(raw)


class MetricsCollector:
    def __init__(self, state_file: str, vm_url: str, dry_run: bool = False, verbose: bool = False):
        self.state_file = state_file
        self.vm_url = vm_url.rstrip("/")
        self.dry_run = dry_run
        self.verbose = verbose
        self.state = self._load_state()

    def log(self, msg: str):
        if self.verbose:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}", file=sys.stderr)

    def _load_state(self) -> dict:
        """状態ファイルの読み込み"""
        if os.path.exists(self.state_file):
            try:
                with open(self.state_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        return data
            except Exception as e:
                self.log(f"警告: 状態ファイル読み込み失敗: {e}")
        return {
            "version": 1,
            "claude_offsets": {},
            "agy_offsets": {},
            "last_orca_stats_timestamp": 0,
            "autopilot_runs": {},
            "counters": {
                "tokens": {},
                "sessions": {},
                "duration": {},
                "autopilot_runs": {},
            },
        }

    def _save_state(self):
        """状態ファイルのアトミック書き込み"""
        if self.dry_run:
            self.log("ドライランのため状態ファイルを更新しない")
            return
        os.makedirs(os.path.dirname(os.path.abspath(self.state_file)), exist_ok=True)
        tmp_path = f"{self.state_file}.tmp.{os.getpid()}"
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(self.state, f, indent=2, ensure_ascii=False)
        os.replace(tmp_path, self.state_file)
        self.log(f"状態ファイルを保存した: {self.state_file}")

    def collect_claude(self):
        """Claude Code のセッションログを差分パース"""
        home = os.path.expanduser("~")
        files = glob.glob(os.path.join(home, ".claude", "projects", "*", "*.jsonl"))
        offsets = self.state.setdefault("claude_offsets", {})
        counters = self.state.setdefault("counters", {}).setdefault("tokens", {})
        sessions = self.state.setdefault("counters", {}).setdefault("sessions", {})

        for path in files:
            try:
                file_size = os.path.getsize(path)
                prev_offset = offsets.get(path, 0)
                if prev_offset > file_size:
                    prev_offset = 0

                if file_size == prev_offset:
                    continue

                new_offset = prev_offset
                is_new_session = (prev_offset == 0)

                # パスから推測される既定 repo
                repo = normalize_repo_name(path)
                context = "portal"

                with open(path, "r", encoding="utf-8", errors="replace") as f:
                    f.seek(prev_offset)
                    while True:
                        line_start = f.tell()
                        line = f.readline()
                        if not line:
                            break
                        if not line.endswith("\n"):
                            # 不完全な行は次回に回す
                            f.seek(line_start)
                            break
                        new_offset = f.tell()

                        try:
                            record = json.loads(line)
                        except json.JSONDecodeError:
                            continue

                        # context 判定
                        entrypoint = record.get("entrypoint", "")
                        cwd = record.get("cwd", "")
                        if cwd:
                            extracted_repo = normalize_repo_name(cwd)
                            if extracted_repo != "unknown":
                                repo = extracted_repo

                        content_str = str(record.get("content", ""))
                        if (
                            entrypoint == "sdk-cli"
                            or "自律実行の担当" in content_str
                            or "コードレビュアー" in content_str
                            or ".autopilot/brief.md" in content_str
                        ):
                            context = "autopilot"

                        # トークン使用量のパース
                        msg = record.get("message") or {}
                        usage = msg.get("usage") or record.get("usage") or {}
                        if not usage or not isinstance(usage, dict):
                            continue

                        model = (
                            msg.get("model")
                            or record.get("requestedModel")
                            or record.get("advisorModel")
                            or "unknown"
                        )
                        model = normalize_identifier(model)

                        input_tokens = usage.get("input_tokens", 0) or 0
                        output_tokens = usage.get("output_tokens", 0) or 0
                        cache_read = usage.get("cache_read_input_tokens", 0) or 0
                        cache_creation = usage.get("cache_creation_input_tokens", 0) or 0

                        output_details = usage.get("output_tokens_details") or {}
                        thinking = output_details.get("thinking_tokens", 0) or 0

                        for token_type, count in [
                            ("input", input_tokens),
                            ("output", output_tokens),
                            ("cache_read", cache_read),
                            ("cache_creation", cache_creation),
                            ("thinking", thinking),
                        ]:
                            if count > 0 or token_type in ("input", "output"):
                                key = f'agent="claude",context="{context}",model="{model}",repo="{repo}",type="{token_type}"'
                                counters[key] = counters.get(key, 0) + count

                if is_new_session and new_offset > 0:
                    s_key = f'agent="claude",context="{context}",repo="{repo}"'
                    sessions[s_key] = sessions.get(s_key, 0) + 1

                offsets[path] = new_offset

            except Exception as e:
                self.log(f"エラー: Claude ログ処理失敗 ({path}): {e}")

    def collect_antigravity(self):
        """Antigravity のセッションログを差分パース"""
        home = os.path.expanduser("~")
        files = glob.glob(
            os.path.join(home, ".gemini", "antigravity-cli", "brain", "*", ".system_generated", "logs", "transcript.jsonl")
        )
        offsets = self.state.setdefault("agy_offsets", {})
        counters = self.state.setdefault("counters", {}).setdefault("tokens", {})
        sessions = self.state.setdefault("counters", {}).setdefault("sessions", {})

        for path in files:
            try:
                file_size = os.path.getsize(path)
                prev_offset = offsets.get(path, 0)
                if prev_offset > file_size:
                    prev_offset = 0

                if file_size == prev_offset:
                    continue

                new_offset = prev_offset
                is_new_session = (prev_offset == 0)
                session_counted = not is_new_session

                repo = "unknown"
                context = "portal"
                current_model = "unknown"

                with open(path, "r", encoding="utf-8", errors="replace") as f:
                    f.seek(prev_offset)
                    while True:
                        line_start = f.tell()
                        line = f.readline()
                        if not line:
                            break
                        if not line.endswith("\n"):
                            f.seek(line_start)
                            break
                        new_offset = f.tell()

                        try:
                            record = json.loads(line)
                        except json.JSONDecodeError:
                            continue

                        content = str(record.get("content", ""))

                        # モデル名の更新検出
                        m_model = re.search(r"The user changed setting `Model Selection` from .*? to ([^\n<]+?)\.(?:\s|<|$)", content)
                        if m_model:
                            current_model = normalize_model_name(m_model.group(1))

                        # repo 検出
                        m_repo = re.search(r"/home/nixos/orca/workspaces/([a-zA-Z0-9_\-]+)", content)
                        if m_repo:
                            candidate = m_repo.group(1)
                            if candidate not in ("repo", "workspace", "name"):
                                for known in KNOWN_REPOS:
                                    if candidate.startswith(known):
                                        repo = known
                                        break
                                else:
                                    repo = normalize_identifier(candidate)

                        # context 検出
                        if (
                            "自律実行の担当" in content
                            or "コードレビュアー" in content
                            or ".autopilot/brief.md" in content
                        ):
                            context = "autopilot"

                        # トークン取得
                        input_tokens = record.get("input_tokens", 0) or 0
                        output_tokens = record.get("output_tokens", 0) or 0
                        cache_read = record.get("cache_read_tokens", 0) or 0

                        if input_tokens > 0 or output_tokens > 0 or cache_read > 0:
                            for token_type, count in [
                                ("input", input_tokens),
                                ("output", output_tokens),
                                ("cache_read", cache_read),
                            ]:
                                key = f'agent="agy",context="{context}",model="{current_model}",repo="{repo}",type="{token_type}"'
                                counters[key] = counters.get(key, 0) + count

                if is_new_session and new_offset > 0:
                    s_key = f'agent="agy",context="{context}",repo="{repo}"'
                    sessions[s_key] = sessions.get(s_key, 0) + 1

                offsets[path] = new_offset

            except Exception as e:
                self.log(f"エラー: Antigravity ログ処理失敗 ({path}): {e}")

    def collect_orca_stats(self):
        """~/.config/orca/orca-stats.json をパースしてセッション時間等を集計"""
        home = os.path.expanduser("~")
        stats_path = os.path.join(home, ".config", "orca", "orca-stats.json")
        if not os.path.exists(stats_path):
            return

        last_ts = self.state.get("last_orca_stats_timestamp", 0)
        duration_counters = self.state.setdefault("counters", {}).setdefault("duration", {})

        # last-status.json から sessionKey -> agent のマッピングを取得
        agent_map = {}
        last_status_path = os.path.join(home, ".config", "orca", "agent-hooks", "last-status.json")
        if os.path.exists(last_status_path):
            try:
                with open(last_status_path, "r", encoding="utf-8") as f:
                    status_data = json.load(f)
                    entries = status_data.get("entries", {})
                    for pane_key, entry in entries.items():
                        raw_agent = (
                            entry.get("source")
                            or entry.get("agentPresence", {}).get("agent")
                            or entry.get("payload", {}).get("agentType")
                        )
                        if raw_agent:
                            agent_name = "agy" if "antigravity" in raw_agent.lower() else normalize_identifier(raw_agent)
                            agent_map[pane_key] = agent_name
            except Exception as e:
                self.log(f"last-status.json 読み取り警告: {e}")

        try:
            with open(stats_path, "r", encoding="utf-8") as f:
                data = json.load(f)

            events = data.get("events", [])
            max_ts = last_ts
            session_worktree = {}

            for ev in events:
                ev_type = ev.get("type")
                ev_at = ev.get("at", 0)

                # start イベントで worktree を保持
                if ev_type == "agent_start":
                    meta = ev.get("meta", {})
                    sk = meta.get("sessionKey", "")
                    wt = ev.get("worktreeId", "")
                    if sk and wt:
                        session_worktree[sk] = wt

                if ev_at <= last_ts:
                    continue

                if ev_at > max_ts:
                    max_ts = ev_at

                if ev_type == "agent_stop":
                    meta = ev.get("meta", {})
                    sk = meta.get("sessionKey", "")
                    duration_ms = meta.get("durationMs", 0)
                    if duration_ms <= 0:
                        continue

                    duration_sec = round(duration_ms / 1000.0, 3)
                    wt = session_worktree.get(sk, "")
                    repo = normalize_repo_name(wt) if wt else "unknown"
                    agent = agent_map.get(sk, "orca")
                    context = "portal"

                    key = f'agent="{agent}",context="{context}",repo="{repo}"'
                    duration_counters[key] = round(duration_counters.get(key, 0.0) + duration_sec, 3)

            self.state["last_orca_stats_timestamp"] = max_ts

        except Exception as e:
            self.log(f"エラー: orca-stats.json 処理失敗: {e}")

    def collect_autopilot_runs(self):
        """/home/nixos/orca/workspaces/*/*/.autopilot/ の実行結果を集計"""
        base_dir = "/home/nixos/orca/workspaces"
        if not os.path.exists(base_dir):
            return

        dirs = glob.glob(os.path.join(base_dir, "*", "*", ".autopilot"))
        recorded_runs = self.state.setdefault("autopilot_runs", {})
        runs_counter = self.state.setdefault("counters", {}).setdefault("autopilot_runs", {})

        for d in dirs:
            try:
                status_file = os.path.join(d, "status")
                run_log_file = os.path.join(d, "run.log")

                if not os.path.exists(status_file):
                    continue

                with open(status_file, "r", encoding="utf-8") as f:
                    result = f.read().strip()

                # 完了ステータスのみ集計対象とする
                if result not in ("done", "failed", "needs-human"):
                    continue

                status_mtime = os.path.getmtime(status_file)
                prev_record = recorded_runs.get(d)

                if prev_record and prev_record.get("status") == result and prev_record.get("mtime") == status_mtime:
                    continue

                # run.log から impl, level を抽出
                impl = "unknown"
                level = "unknown"
                if os.path.exists(run_log_file):
                    with open(run_log_file, "r", encoding="utf-8", errors="replace") as f:
                        for _ in range(20):
                            line = f.readline()
                            if not line:
                                break
                            m_start = re.search(r"start\s+impl=(\S+)\s+level=(\S+)", line)
                            if m_start:
                                impl = normalize_identifier(m_start.group(1))
                                level = normalize_identifier(m_start.group(2))
                                break

                # パスから repo を判定
                repo = normalize_repo_name(d)

                key = f'impl="{impl}",level="{level}",repo="{repo}",result="{result}"'
                runs_counter[key] = runs_counter.get(key, 0) + 1

                recorded_runs[d] = {
                    "status": result,
                    "mtime": status_mtime,
                }

            except Exception as e:
                self.log(f"エラー: autopilot ログ処理失敗 ({d}): {e}")

    def generate_prometheus_payload(self) -> str:
        """Prometheus Exposition Format のテキストを生成"""
        lines = []
        counters = self.state.get("counters", {})

        # 1. tokens
        token_data = counters.get("tokens", {})
        if token_data:
            lines.append("# HELP nuage_ai_agent_tokens_total Total tokens used by AI agents")
            lines.append("# TYPE nuage_ai_agent_tokens_total counter")
            for k in sorted(token_data.keys()):
                lines.append(f"nuage_ai_agent_tokens_total{{{k}}} {token_data[k]}")

        # 2. sessions
        session_data = counters.get("sessions", {})
        if session_data:
            lines.append("# HELP nuage_ai_agent_sessions_total Total sessions started by AI agents")
            lines.append("# TYPE nuage_ai_agent_sessions_total counter")
            for k in sorted(session_data.keys()):
                lines.append(f"nuage_ai_agent_sessions_total{{{k}}} {session_data[k]}")

        # 3. duration
        duration_data = counters.get("duration", {})
        if duration_data:
            lines.append("# HELP nuage_ai_agent_session_duration_seconds_total Total duration of AI agent sessions in seconds")
            lines.append("# TYPE nuage_ai_agent_session_duration_seconds_total counter")
            for k in sorted(duration_data.keys()):
                lines.append(f"nuage_ai_agent_session_duration_seconds_total{{{k}}} {duration_data[k]}")

        # 4. autopilot runs
        runs_data = counters.get("autopilot_runs", {})
        if runs_data:
            lines.append("# HELP nuage_ai_agent_autopilot_runs_total Total autopilot runs by result")
            lines.append("# TYPE nuage_ai_agent_autopilot_runs_total counter")
            for k in sorted(runs_data.keys()):
                lines.append(f"nuage_ai_agent_autopilot_runs_total{{{k}}} {runs_data[k]}")

        if lines:
            lines.append("")
        return "\n".join(lines)

    def send_to_victoriametrics(self, payload: str):
        """VictoriaMetrics へ HTTP POST で送信"""
        if not payload.strip():
            self.log("送信すべきメトリクスがありません")
            return

        url = f"{self.vm_url}/api/v1/import/prometheus"
        self.log(f"VictoriaMetrics へ送信中: {url}")

        req = urllib.request.Request(
            url,
            data=payload.encode("utf-8"),
            headers={"Content-Type": "text/plain"},
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                status = resp.status
                if status in (200, 204):
                    self.log(f"送信成功 (HTTP {status})")
                else:
                    raise RuntimeError(f"予期しないステータスコード: HTTP {status}")
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"HTTP エラー ({e.code}): {body}") from e
        except Exception as e:
            raise RuntimeError(f"VictoriaMetrics への接続失敗: {e}") from e

    def run(self):
        """集計処理を実行し、結果を送信または出力"""
        start_time = time.time()
        self.log("メトリクス集計開始")

        self.collect_claude()
        self.collect_antigravity()
        self.collect_orca_stats()
        self.collect_autopilot_runs()

        payload = self.generate_prometheus_payload()

        if self.dry_run:
            print(payload, end="")
            self.log(f"ドライラン完了 (処理時間: {time.time() - start_time:.3f}s)")
            return

        if payload.strip():
            self.send_to_victoriametrics(payload)
        else:
            self.log("メトリクスが空のため送信をスキップした")

        self._save_state()
        self.log(f"集計完了 (処理時間: {time.time() - start_time:.3f}s)")


def default_state_file() -> str:
    """利用可能な既定の状態ファイルパスを判定"""
    env_path = os.environ.get("AI_METRICS_STATE_FILE")
    if env_path:
        return env_path
    primary = "/var/lib/atelier/ai-agent-metrics-state.json"
    primary_dir = os.path.dirname(primary)
    if os.path.exists(primary_dir) and os.access(primary_dir, os.W_OK):
        return primary
    return os.path.expanduser("~/.config/orca/ai-metrics-state.json")


def main():
    parser = argparse.ArgumentParser(description="AI Agent 使用量メトリクスの収集と VictoriaMetrics 連携")
    parser.add_argument(
        "--vm-url",
        default=os.environ.get("VICTORIAMETRICS_URL", "http://10.20.1.20:8427"),
        help="VictoriaMetrics のベースURL (既定: http://10.20.1.20:8427)",
    )
    parser.add_argument(
        "--state-file",
        default=default_state_file(),
        help="状態ファイルの保存パス",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="VictoriaMetrics への送信を行わず、生成メトリクスを標準出力に表示する",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="詳細ログを出力する",
    )

    args = parser.parse_args()

    collector = MetricsCollector(
        state_file=args.state_file,
        vm_url=args.vm_url,
        dry_run=args.dry_run,
        verbose=args.verbose,
    )
    collector.run()


if __name__ == "__main__":
    main()
