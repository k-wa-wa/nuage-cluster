#!/usr/bin/env python3
"""
AI Agent 使用量メトリクスの収集と VictoriaMetrics 連携スクリプト。

Orca および autopilot で稼働した AI Agent (Claude Code, Antigravity) の
使用量（トークン数、セッション時間、autopilot 実行実績）を集計し、
作業コンテキスト（branch, phase, task, pr）を付与して
Prometheus exposition format で VictoriaMetrics へ送信する。
"""

import argparse
import functools
import glob
import json
import os
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.request

KNOWN_REPOS = [
    "nuage-cluster",
    "nuage-autopilot5",
    "pechka",
    "nuage-monitoring-stack",
    "nuage-usage-ledger",
    "nuage-workspace",
]


@functools.lru_cache(maxsize=1)
def get_candidate_repos() -> list[str]:
    """ワークスペース実ディレクトリと KNOWN_REPOS を統合した候補一覧（名前の降順）"""
    repos = set(KNOWN_REPOS)
    base_dir = "/home/nixos/orca/workspaces"
    if os.path.exists(base_dir):
        try:
            for entry in os.listdir(base_dir):
                if entry and not entry.startswith("."):
                    repos.add(entry)
        except OSError:
            pass
    return sorted(repos, key=len, reverse=True)


def normalize_identifier(val: str, default: str = "unknown") -> str:
    """メトリクスラベル用文字列の正規化（英数字・ハイフン・アンダースコア以外を置換）"""
    if not val:
        return default
    val = val.strip().lower()
    val = re.sub(r"[^a-z0-9_\-]+", "-", val)
    val = val.strip("-")
    return val or default


def normalize_branch_name(val: str, default: str = "unknown") -> str:
    """ブランチ名用文字列の正規化（英数字・ハイフン・アンダースコア・スラッシュ・ドットを許可）"""
    if not val:
        return default
    val = val.strip()
    if val.startswith("refs/heads/"):
        val = val[len("refs/heads/") :]
    val = re.sub(r"[^a-zA-Z0-9_\-\./]+", "-", val)
    val = val.strip("-")
    if val in ("tmp", "/tmp"):
        return "tmp"
    if val == "HEAD":
        return default
    return val or default


def normalize_repo_name(raw: str) -> str:
    """ワークスペースパスやプロジェクト名からリポジトリ名を抽出して正規化"""
    if not raw:
        return "unknown"

    # URI 形式 file:///home/nixos/...
    if raw.startswith("file://"):
        raw = raw[len("file://") :]

    # パス形式: /orca/workspaces/<repo>/... または /workspaces/<repo>/...
    m = re.search(r"/(?:orca/)?workspaces/([^/\s\'\"]+)", raw)
    if m:
        candidate = m.group(1)
        if candidate not in ("repo", "workspace", "name"):
            for known in get_candidate_repos():
                if candidate.startswith(known):
                    return known
            return normalize_identifier(candidate)

    # プロジェクトディレクトリ名形式: -home-nixos-orca-workspaces-<repo>-... または -tmp
    m = re.search(r"-home-nixos-orca-workspaces-([a-zA-Z0-9_\-]+)", raw)
    if m:
        part = m.group(1)
        for known in get_candidate_repos():
            if part.startswith(known):
                return known
        return normalize_identifier(part)

    if "/projects/-tmp/" in raw or raw.endswith("-tmp") or raw == "/tmp" or raw.endswith("/tmp"):
        return "tmp"

    return normalize_identifier(raw)


def get_git_branch_from_worktree(path: str) -> str:
    """指定されたパス（worktree またはその配下）から git HEAD のブランチ名を取得"""
    if not path:
        return "unknown"
    if path.startswith("file://"):
        path = path[len("file://") :]
    if (
        "/projects/-tmp/" in path
        or path.endswith("-tmp")
        or path == "/tmp"
        or path == "tmp"
        or path.endswith("/tmp")
    ):
        return "tmp"

    curr = os.path.abspath(path)
    for _ in range(6):
        dot_git = os.path.join(curr, ".git")
        if os.path.exists(dot_git):
            try:
                head_path = None
                if os.path.isdir(dot_git):
                    head_path = os.path.join(dot_git, "HEAD")
                elif os.path.isfile(dot_git):
                    with open(dot_git, "r", encoding="utf-8") as f:
                        line = f.readline().strip()
                        if line.startswith("gitdir:"):
                            gitdir = line[len("gitdir:") :].strip()
                            if not os.path.isabs(gitdir):
                                gitdir = os.path.normpath(os.path.join(curr, gitdir))
                            head_path = os.path.join(gitdir, "HEAD")
                if head_path and os.path.exists(head_path):
                    with open(head_path, "r", encoding="utf-8") as f:
                        content = f.readline().strip()
                        if content.startswith("ref: refs/heads/"):
                            branch = content[len("ref: refs/heads/") :].strip()
                            return normalize_branch_name(branch)
                        elif content:
                            return normalize_branch_name(content[:8])
            except Exception:
                pass
            break
        parent = os.path.dirname(curr)
        if parent == curr:
            break
        curr = parent

    return "unknown"


def extract_task_from_brief(ws_path: str) -> str:
    """ワークスペースの .autopilot/brief.md からタスク名（1行目見出し）を抽出"""
    if not ws_path:
        return "unknown"
    if ws_path.startswith("file://"):
        ws_path = ws_path[len("file://") :]

    auto_dir = ws_path if os.path.basename(ws_path) == ".autopilot" else os.path.join(ws_path, ".autopilot")
    brief_path = os.path.join(auto_dir, "brief.md")
    if not os.path.exists(brief_path):
        brief_path = os.path.join(ws_path, "brief.md")
        if not os.path.exists(brief_path):
            return "unknown"

    try:
        with open(brief_path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line.startswith("# "):
                    title = line[2:].strip()
                    title = re.sub(r"[\r\n\t]+", " ", title)
                    title = title.replace("\\", "\\\\").replace('"', '\\"')
                    return title or "unknown"
    except Exception:
        pass
    return "unknown"


def extract_pr_number(ws_path: str, repo: str | None = None) -> str:
    """ワークスペースの .autopilot/run.log または result.md から PR 番号を抽出"""
    if not ws_path:
        return "none"
    if ws_path.startswith("file://"):
        ws_path = ws_path[len("file://") :]

    auto_dir = ws_path if os.path.basename(ws_path) == ".autopilot" else os.path.join(ws_path, ".autopilot")
    if not os.path.exists(auto_dir):
        return "none"

    result_path = os.path.join(auto_dir, "result.md")
    run_log_path = os.path.join(auto_dir, "run.log")

    repo_url_pattern = None
    if repo and repo != "unknown":
        repo_url_pattern = re.compile(rf"https://github\.com/[^/\s]+/{re.escape(repo)}/pull/(\d+)")
    url_pattern = re.compile(r"https://github\.com/[^/\s]+/[^/\s]+/pull/(\d+)")
    pr_pattern = re.compile(r"(?:PR\s*#|pull/|pulls/)(\d+)")

    # 1. 該当リポジトリの URL があれば最優先
    if repo_url_pattern:
        for p in (result_path, run_log_path):
            if os.path.exists(p):
                try:
                    with open(p, "r", encoding="utf-8", errors="replace") as f:
                        content = f.read()
                        matches = repo_url_pattern.findall(content)
                        if matches:
                            return matches[-1]
                except Exception:
                    pass

    # 2. 一般的な gh pr create の出力 URL (https://github.com/.../pull/N) を優先
    for p in (result_path, run_log_path):
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8", errors="replace") as f:
                    content = f.read()
                    matches = url_pattern.findall(content)
                    if matches:
                        return matches[-1]
            except Exception:
                pass

    # 3. URL がない場合、PR #N などの表記を抽出
    for p in (result_path, run_log_path):
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8", errors="replace") as f:
                    content = f.read()
                    matches = pr_pattern.findall(content)
                    if matches:
                        return matches[-1]
            except Exception:
                pass

    return "none"


@functools.lru_cache(maxsize=32)
def _read_run_log_steps(run_log_path: str, mtime: float) -> list[str]:
    """run.log から記録されたフェーズ履歴を抽出（mtime でキャッシュ）"""
    steps = []
    try:
        with open(run_log_path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.search(r"^\[[^\]]*\]\s*==\s*(implementing|reviewing|fixing|summarizing)", line)
                if m:
                    step = m.group(1)
                    step_map = {
                        "implementing": "implement",
                        "reviewing": "review",
                        "fixing": "fix",
                        "summarizing": "summarize",
                    }
                    steps.append(step_map.get(step, "unknown"))
    except Exception:
        pass
    return steps


def get_phase_from_run_log(ws_path: str) -> str:
    """ワークスペースの .autopilot/run.log から最新ステップを取得"""
    if not ws_path:
        return "unknown"
    if ws_path.startswith("file://"):
        ws_path = ws_path[len("file://") :]

    auto_dir = ws_path if os.path.basename(ws_path) == ".autopilot" else os.path.join(ws_path, ".autopilot")
    run_log = os.path.join(auto_dir, "run.log")
    if not os.path.exists(run_log):
        return "unknown"

    try:
        mtime = os.path.getmtime(run_log)
        steps = _read_run_log_steps(run_log, mtime)
        if steps:
            return steps[-1]
    except Exception:
        pass
    return "unknown"


def detect_phase(content: str) -> str:
    """プロンプト内容から作業フェーズ (implement/review/fix/summarize) を判定"""
    if not content:
        content = ""

    # プロンプト文字列の特徴から判定（fix を review より先に判定し、追加指示内の「レビューする」等による誤判定を防止）
    if (
        "直すべきものを直す" in content
        or "レビュー結果:" in content
        or "レビューの must" in content
        or "直すものが無ければ" in content
    ):
        return "fix"
    if (
        "あなたはコードレビュアーである" in content
        or "コードレビュアー" in content
    ):
        return "review"
    if (
        "人間向けの要約" in content
        or ".autopilot/result.md に書く" in content
        or "要約を .autopilot/result.md" in content
        or "PR の本文も同じ内容で" in content
    ):
        return "summarize"
    if (
        ".autopilot/brief.md の仕様を実装" in content
        or "仕様を実装し、テストがあれば" in content
        or "自律実行の担当" in content
        or "brief の要点" in content
        or "あなたは自律実行の担当である" in content
    ):
        return "implement"

    return "unknown"


def get_antigravity_conversation_meta(cid: str, cached_map: dict | None = None) -> tuple[str, str, str]:
    """conversation_summaries.db およびキャッシュから (repo, branch, worktree) を取得"""
    if not cid:
        return "unknown", "unknown", ""
    if cached_map and cid in cached_map:
        cached = cached_map[cid]
        if isinstance(cached, dict):
            return (
                cached.get("repo", "unknown"),
                cached.get("branch", "unknown"),
                cached.get("worktree", ""),
            )
        elif isinstance(cached, str):
            return cached, "unknown", ""

    db_path = os.path.expanduser("~/.gemini/antigravity-cli/conversation_summaries.db")
    if not os.path.exists(db_path):
        return "unknown", "unknown", ""
    try:
        with sqlite3.connect(db_path) as conn:
            row = conn.execute(
                "SELECT workspace_uris FROM conversation_summaries WHERE conversation_id = ?",
                (cid,),
            ).fetchone()
            if row and row[0]:
                try:
                    uris = json.loads(row[0])
                    if isinstance(uris, list) and uris:
                        uri = uris[0]
                        ws_path = uri[len("file://") :] if uri.startswith("file://") else uri
                        repo = normalize_repo_name(uri)
                        branch = get_git_branch_from_worktree(ws_path)
                        return repo, branch, ws_path
                except json.JSONDecodeError:
                    pass
    except Exception:
        pass
    return "unknown", "unknown", ""


def get_antigravity_conversation_repo(cid: str, cached_map: dict | None = None) -> str:
    """conversation_summaries.db およびキャッシュから conversation_id に紐づくワークスペースの repo 名を取得"""
    repo, _, _ = get_antigravity_conversation_meta(cid, cached_map)
    return repo


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


CURRENT_STATE_VERSION = 3


class MetricsCollector:
    def __init__(self, state_file: str, vm_url: str, dry_run: bool = False, verbose: bool = False):
        self.state_file = state_file
        self.vm_url = vm_url.rstrip("/")
        self.dry_run = dry_run
        self.verbose = verbose
        self.has_errors = False
        self.state = self._load_state()

    def log(self, msg: str):
        if self.verbose:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}", file=sys.stderr)

    def warn(self, msg: str):
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 警告: {msg}", file=sys.stderr)

    def error(self, msg: str):
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] エラー: {msg}", file=sys.stderr)
        self.has_errors = True

    def _load_state(self) -> dict:
        """状態ファイルの読み込みとスキーママイグレーション"""
        if os.path.exists(self.state_file):
            try:
                with open(self.state_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        if data.get("version", 1) < CURRENT_STATE_VERSION:
                            self.log(f"状態ファイルをバージョン {CURRENT_STATE_VERSION} へマイグレーション")
                            data["version"] = CURRENT_STATE_VERSION
                            data["claude_offsets"] = {}
                            data["agy_offsets"] = {}
                            data["last_orca_stats_timestamp"] = 0
                            data["autopilot_runs"] = {}
                            data["counters"] = {
                                "tokens": {},
                                "sessions": {},
                                "duration": {},
                                "autopilot_runs": {},
                            }
                        return data
                    raise ValueError(f"状態ファイルの内容が辞書型ではない: {type(data)}")
            except Exception as e:
                raise RuntimeError(f"状態ファイル読み込み失敗 ({self.state_file}): {e}") from e
        return {
            "version": CURRENT_STATE_VERSION,
            "claude_offsets": {},
            "agy_offsets": {},
            "last_orca_stats_timestamp": 0,
            "orca_sessions": {},
            "portal_cids": {},
            "cid_to_repo": {},
            "cid_to_meta": {},
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

        # 辞書キャッシュの肥大化防止（直近 1000 件に制限）
        for key in ("orca_sessions", "portal_cids", "cid_to_repo", "cid_to_meta", "autopilot_runs"):
            d = self.state.get(key)
            if isinstance(d, dict) and len(d) > 1000:
                keys_to_remove = list(d.keys())[:-1000]
                for k in keys_to_remove:
                    del d[k]

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
                prev_data = offsets.get(path, {})
                if isinstance(prev_data, int):
                    prev_offset = prev_data
                    prev_meta = {}
                elif isinstance(prev_data, dict):
                    prev_offset = prev_data.get("offset", 0)
                    prev_meta = prev_data
                else:
                    prev_offset = 0
                    prev_meta = {}

                if prev_offset > file_size:
                    prev_offset = 0
                    prev_meta = {}

                if file_size == prev_offset:
                    continue

                new_offset = prev_offset
                is_new_session = (prev_offset == 0)

                # 前回のパース状態からメタデータを復元
                repo = prev_meta.get("repo") or normalize_repo_name(path)
                branch = prev_meta.get("branch") or get_git_branch_from_worktree(path)
                prev_entrypoint = prev_meta.get("entrypoint", "")
                is_cli = (prev_entrypoint == "cli")
                is_sdk = (prev_entrypoint == "sdk-cli")
                context = "portal" if is_cli else prev_meta.get("context", "portal")
                phase = "portal" if is_cli else (prev_meta.get("phase") or ("portal" if context == "portal" else "unknown"))
                phase_locked = (phase in ("implement", "review", "fix", "summarize") and context == "autopilot") or is_cli
                saved_model = prev_meta.get("model", "unknown")
                seen_ids = {mid: True for mid in prev_meta.get("seen_message_ids", [])}

                temp_counters = {}
                temp_sessions = {}

                with open(path, "rb") as f:
                    f.seek(prev_offset)
                    while True:
                        line_start = f.tell()
                        raw_line = f.readline()
                        if not raw_line:
                            break
                        # 不完全な行は次回に回す
                        if not raw_line.endswith(b"\n"):
                            f.seek(line_start)
                            break
                        new_offset = f.tell()

                        try:
                            line = raw_line.decode("utf-8", errors="replace")
                            record = json.loads(line)
                        except (json.JSONDecodeError, UnicodeDecodeError):
                            continue

                        # context 判定: Claude Code では autopilot 実行時は entrypoint が sdk-cli になる
                        entrypoint = record.get("entrypoint")
                        if entrypoint == "cli":
                            is_cli = True
                            context = "portal"
                            phase = "portal"
                            phase_locked = True
                        elif entrypoint == "sdk-cli":
                            is_sdk = True
                            context = "autopilot"
                            if phase == "portal":
                                phase = "unknown"
                                phase_locked = False

                        cwd = record.get("cwd", "")
                        if cwd:
                            extracted_repo = normalize_repo_name(cwd)
                            if extracted_repo != "unknown":
                                repo = extracted_repo
                            extracted_branch = get_git_branch_from_worktree(cwd)
                            if extracted_branch != "unknown":
                                branch = extracted_branch

                        # record 自体の gitBranch を利用（HEAD や無効値以外）
                        rec_branch = record.get("gitBranch", "")
                        if rec_branch and rec_branch != "HEAD":
                            norm_br = normalize_branch_name(rec_branch)
                            if norm_br != "unknown":
                                branch = norm_br

                        # ユーザープロンプトからフェーズを判定（autopilot の初回指示のみ）
                        # 窓口セッション (cli) は portal に固定し、上書きさせない
                        if not is_cli and not phase_locked:
                            prompt_content = ""
                            if record.get("type") == "user":
                                msg = record.get("message")
                                if isinstance(msg, dict):
                                    content_val = msg.get("content")
                                    # ツールの結果 (list) は無視し、文字列の指示のみを対象とする
                                    if isinstance(content_val, str):
                                        prompt_content = content_val
                                elif isinstance(msg, str):
                                    prompt_content = msg
                            elif record.get("type") == "queue-operation":
                                content_val = record.get("content")
                                if isinstance(content_val, str):
                                    prompt_content = content_val

                            if prompt_content:
                                detected = detect_phase(prompt_content)
                                if detected in ("implement", "review", "fix", "summarize"):
                                    context = "autopilot"
                                    phase = detected
                                    phase_locked = True
                                elif is_sdk:
                                    fb_phase = get_phase_from_run_log(cwd or path)
                                    if fb_phase in ("implement", "review", "fix", "summarize"):
                                        phase = fb_phase
                                        context = "autopilot"
                                        phase_locked = True

                        effective_phase = "portal" if (is_cli or context == "portal") else phase
                        effective_context = "portal" if (is_cli or context == "portal") else ("autopilot" if is_sdk else context)

                        # トークン使用量のパース
                        msg = record.get("message") or {}
                        usage = msg.get("usage") or record.get("usage") or {}
                        if not usage or not isinstance(usage, dict):
                            continue

                        # 重複カウント防止: 1 つの応答の複数行に同じ message.id / requestId と usage が付与される
                        mid = msg.get("id") or record.get("requestId")
                        if mid:
                            if mid in seen_ids:
                                continue
                            seen_ids[mid] = True

                        model = (
                            msg.get("model")
                            or record.get("requestedModel")
                            or record.get("advisorModel")
                            or saved_model
                        )
                        model = normalize_identifier(model)
                        saved_model = model

                        input_tokens = int(usage.get("input_tokens", 0) or 0)
                        output_tokens = int(usage.get("output_tokens", 0) or 0)
                        cache_read = int(usage.get("cache_read_input_tokens", 0) or 0)
                        cache_creation = int(usage.get("cache_creation_input_tokens", 0) or 0)

                        output_details = usage.get("output_tokens_details") or {}
                        thinking = int(output_details.get("thinking_tokens", 0) or 0)

                        for token_type, count in [
                            ("input", input_tokens),
                            ("output", output_tokens),
                            ("cache_read", cache_read),
                            ("cache_creation", cache_creation),
                            ("thinking", thinking),
                        ]:
                            if count > 0 or token_type in ("input", "output"):
                                key = f'agent="claude",branch="{branch}",model="{model}",phase="{effective_phase}",repo="{repo}",type="{token_type}"'
                                temp_counters[key] = temp_counters.get(key, 0) + count

                effective_phase = "portal" if (is_cli or context == "portal") else phase
                effective_context = "portal" if (is_cli or context == "portal") else ("autopilot" if is_sdk else context)

                # ファイル単位で正常に読み切れた場合のみ本番カウンタとオフセットに反映する
                if is_new_session and new_offset > 0:
                    s_key = f'agent="claude",branch="{branch}",phase="{effective_phase}",repo="{repo}"'
                    temp_sessions[s_key] = temp_sessions.get(s_key, 0) + 1

                for k, v in temp_counters.items():
                    counters[k] = counters.get(k, 0) + v
                for k, v in temp_sessions.items():
                    sessions[k] = sessions.get(k, 0) + v

                # seen_message_ids は直近 500 件に制限して肥大化を防止する（順序を保持）
                recent_ids = list(seen_ids.keys())[-500:]
                offsets[path] = {
                    "offset": new_offset,
                    "repo": repo,
                    "branch": branch,
                    "phase": effective_phase,
                    "context": effective_context,
                    "entrypoint": "cli" if is_cli else ("sdk-cli" if is_sdk else prev_entrypoint),
                    "model": saved_model,
                    "seen_message_ids": recent_ids,
                }

            except Exception as e:
                self.error(f"Claude ログ処理失敗 ({path}): {e}")

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
                prev_data = offsets.get(path, {})
                if isinstance(prev_data, int):
                    prev_offset = prev_data
                    prev_meta = {}
                elif isinstance(prev_data, dict):
                    prev_offset = prev_data.get("offset", 0)
                    prev_meta = prev_data
                else:
                    prev_offset = 0
                    prev_meta = {}

                if prev_offset > file_size:
                    prev_offset = 0
                    prev_meta = {}

                if file_size == prev_offset:
                    continue

                new_offset = prev_offset
                is_new_session = (prev_offset == 0)

                m_cid = re.search(r"/brain/([^/]+)/\.system_generated", path)
                cid = m_cid.group(1) if m_cid else ""
                cid_map = self.state.get("cid_to_meta") or self.state.get("cid_to_repo", {})
                portal_cids = self.state.get("portal_cids", {})

                # メタデータの復元
                repo = prev_meta.get("repo", "unknown")
                branch = prev_meta.get("branch", "unknown")
                ws_path = prev_meta.get("ws_path", "")
                if (repo == "unknown" or branch == "unknown" or not ws_path) and cid:
                    meta_repo, meta_branch, meta_ws = get_antigravity_conversation_meta(cid, cid_map)
                    if repo == "unknown":
                        repo = meta_repo
                    if branch == "unknown":
                        branch = meta_branch
                    if not ws_path and meta_ws:
                        ws_path = meta_ws

                context = prev_meta.get("context", "portal")
                if cid and cid in portal_cids:
                    context = "portal"
                phase = prev_meta.get("phase") or ("portal" if context == "portal" else "unknown")
                current_model = prev_meta.get("model", "unknown")

                temp_counters = {}
                temp_sessions = {}

                with open(path, "rb") as f:
                    f.seek(prev_offset)
                    while True:
                        line_start = f.tell()
                        raw_line = f.readline()
                        if not raw_line:
                            break
                        # 不完全な行は次回に回す
                        if not raw_line.endswith(b"\n"):
                            f.seek(line_start)
                            break
                        new_offset = f.tell()

                        try:
                            line = raw_line.decode("utf-8", errors="replace")
                            record = json.loads(line)
                        except (json.JSONDecodeError, UnicodeDecodeError):
                            continue

                        content = str(record.get("content", ""))

                        # モデル名の更新検出
                        m_model = re.search(r"The user changed setting `Model Selection` from .*? to ([^\n<]+?)\.(?:\s|<|$)", content)
                        if m_model:
                            current_model = normalize_model_name(m_model.group(1))

                        # context および phase 検出
                        # last-status.json の portal に載っている conversation は常に portal を維持
                        if cid and cid in portal_cids:
                            context = "portal"
                            phase = "portal"
                        else:
                            # context 検出: 初回ターン (step_index == 0) の USER_INPUT に autopilot 固有の定型文がある場合のみ autopilot とする
                            if record.get("step_index") == 0 and record.get("type") == "USER_INPUT":
                                if (
                                    "あなたは自律実行の担当である" in content
                                    or "あなたはコードレビュアーである" in content
                                ):
                                    context = "autopilot"
                                    detected = detect_phase(content)
                                    if detected in ("implement", "review", "fix", "summarize"):
                                        phase = detected
                                    else:
                                        fb = get_phase_from_run_log(ws_path)
                                        phase = fb if fb in ("implement", "review", "fix", "summarize") else "unknown"

                        # repo および branch 検出: 未特定の場合のみ content 中のワークスペースパスから抽出
                        if repo == "unknown" or branch == "unknown":
                            m_ws = re.search(r"((?:/[^/\s\'\"]+)*?/(?:orca/)?workspaces/([^/\s\'\"]+)(?:/([^/\s\'\"]+))?)", content)
                            if m_ws:
                                full_match_path = m_ws.group(1)
                                candidate = m_ws.group(2)
                                if candidate not in ("repo", "workspace", "name"):
                                    if repo == "unknown":
                                        for known in get_candidate_repos():
                                            if candidate.startswith(known):
                                                repo = known
                                                break
                                        else:
                                            repo = normalize_identifier(candidate)
                                    if branch == "unknown":
                                        extracted_br = get_git_branch_from_worktree(full_match_path)
                                        if extracted_br != "unknown":
                                            branch = extracted_br
                                if not ws_path:
                                    ws_path = full_match_path

                        # トークン取得
                        input_tokens = int(record.get("input_tokens", 0) or 0)
                        output_tokens = int(record.get("output_tokens", 0) or 0)
                        cache_read = int(record.get("cache_read_tokens", 0) or 0)

                        if input_tokens > 0 or output_tokens > 0 or cache_read > 0:
                            for token_type, count in [
                                ("input", input_tokens),
                                ("output", output_tokens),
                                ("cache_read", cache_read),
                            ]:
                                key = f'agent="agy",branch="{branch}",model="{current_model}",phase="{phase}",repo="{repo}",type="{token_type}"'
                                temp_counters[key] = temp_counters.get(key, 0) + count

                # ファイル単位で正常に読み切れた場合のみ本番カウンタとオフセットに反映する
                if is_new_session and new_offset > 0:
                    s_key = f'agent="agy",branch="{branch}",phase="{phase}",repo="{repo}"'
                    temp_sessions[s_key] = temp_sessions.get(s_key, 0) + 1

                for k, v in temp_counters.items():
                    counters[k] = counters.get(k, 0) + v
                for k, v in temp_sessions.items():
                    sessions[k] = sessions.get(k, 0) + v

                offsets[path] = {
                    "offset": new_offset,
                    "repo": repo,
                    "branch": branch,
                    "ws_path": ws_path,
                    "phase": phase,
                    "context": context,
                    "model": current_model,
                }

            except Exception as e:
                self.error(f"Antigravity ログ処理失敗 ({path}): {e}")

    def update_active_sessions(self):
        """last-status.json から稼働中ペインの情報を更新蓄積"""
        home = os.path.expanduser("~")
        last_status_path = os.path.join(home, ".config", "orca", "agent-hooks", "last-status.json")
        if not os.path.exists(last_status_path):
            return

        orca_sessions = self.state.setdefault("orca_sessions", {})
        portal_cids = self.state.setdefault("portal_cids", {})
        cid_to_repo = self.state.setdefault("cid_to_repo", {})
        cid_to_meta = self.state.setdefault("cid_to_meta", {})

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
                    agent_name = "unknown"
                    if raw_agent:
                        agent_name = "agy" if "antigravity" in raw_agent.lower() else normalize_identifier(raw_agent)

                    wt = entry.get("worktreeId", "")
                    wt_path = wt.split("::")[-1] if "::" in wt else wt
                    repo = normalize_repo_name(wt_path) if wt_path else "unknown"
                    branch = get_git_branch_from_worktree(wt_path) if wt_path else "unknown"

                    s_entry = orca_sessions.setdefault(pane_key, {})
                    if agent_name != "unknown":
                        s_entry["agent"] = agent_name
                    if repo != "unknown":
                        s_entry["repo"] = repo
                    if branch != "unknown":
                        s_entry["branch"] = branch
                    # Orca UI 上のペインは人間との対話窓口（portal）である
                    s_entry["context"] = "portal"
                    s_entry["phase"] = "portal"

                    # Antigravity の conversation_id との対応、および portal CID の記録
                    provider_session = entry.get("providerSession", {})
                    if provider_session.get("key") == "conversation_id":
                        cid = provider_session.get("id")
                        if cid:
                            portal_cids[cid] = True
                            if repo != "unknown":
                                cid_to_repo[cid] = repo
                            cid_to_meta[cid] = {
                                "repo": repo,
                                "branch": branch,
                                "worktree": wt_path,
                            }
        except Exception as e:
            self.warn(f"last-status.json 読み取り警告: {e}")

    def collect_orca_stats(self):
        """~/.config/orca/orca-stats.json をパースしてセッション時間等を集計"""
        self.update_active_sessions()

        home = os.path.expanduser("~")
        stats_path = os.path.join(home, ".config", "orca", "orca-stats.json")
        if not os.path.exists(stats_path):
            return

        last_ts = self.state.get("last_orca_stats_timestamp", 0)
        duration_counters = self.state.setdefault("counters", {}).setdefault("duration", {})
        orca_sessions = self.state.setdefault("orca_sessions", {})

        try:
            with open(stats_path, "r", encoding="utf-8") as f:
                data = json.load(f)

            events = data.get("events", [])
            max_ts = last_ts
            temp_duration = {}

            for ev in events:
                ev_type = ev.get("type")
                ev_at = ev.get("at", 0)

                # start イベントで sessionKey と worktree を記録
                if ev_type == "agent_start":
                    meta = ev.get("meta", {})
                    sk = meta.get("sessionKey", "")
                    wt = ev.get("worktreeId", "")
                    wt_path = wt.split("::")[-1] if "::" in wt else wt
                    if sk:
                        s_entry = orca_sessions.setdefault(sk, {})
                        if wt_path:
                            repo = normalize_repo_name(wt_path)
                            branch = get_git_branch_from_worktree(wt_path)
                            if repo != "unknown":
                                s_entry["repo"] = repo
                            if branch != "unknown":
                                s_entry["branch"] = branch
                        s_entry["context"] = "portal"
                        s_entry["phase"] = "portal"

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
                    session_info = orca_sessions.get(sk, {})
                    agent = session_info.get("agent", "unknown")
                    repo = session_info.get("repo", "unknown")
                    branch = session_info.get("branch", "unknown")
                    phase = "portal"

                    key = f'agent="{agent}",branch="{branch}",phase="{phase}",repo="{repo}"'
                    temp_duration[key] = round(temp_duration.get(key, 0.0) + duration_sec, 3)

            for k, v in temp_duration.items():
                duration_counters[k] = round(duration_counters.get(k, 0.0) + v, 3)

            self.state["last_orca_stats_timestamp"] = max_ts

        except Exception as e:
            self.error(f"orca-stats.json 処理失敗: {e}")

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
                    raw_status = f.read().strip()

                # status ファイルは "done", "failed: <理由>", "needs-human: <理由>" 形式で書かれる
                result_type = raw_status.split(":", 1)[0].strip()

                # 完了ステータスのみ集計対象とする
                if result_type not in ("done", "failed", "needs-human"):
                    continue

                status_mtime = os.path.getmtime(status_file)
                prev_record = recorded_runs.get(d)

                if prev_record and prev_record.get("status") == raw_status and prev_record.get("mtime") == status_mtime:
                    continue

                # run.log から impl, level を抽出（最新の start 行を採用）
                impl = "unknown"
                level = "unknown"
                if os.path.exists(run_log_file):
                    with open(run_log_file, "r", encoding="utf-8", errors="replace") as f:
                        for line in f:
                            m_start = re.search(r"start\s+impl=(\S+)\s+level=(\S+)", line)
                            if m_start:
                                impl = normalize_identifier(m_start.group(1))
                                level = normalize_identifier(m_start.group(2))

                # パスから repo を判定
                ws_dir = os.path.dirname(d)
                repo = normalize_repo_name(d)
                branch = get_git_branch_from_worktree(ws_dir)
                task = extract_task_from_brief(ws_dir)
                pr = extract_pr_number(ws_dir, repo=repo)

                key = f'branch="{branch}",impl="{impl}",level="{level}",pr="{pr}",repo="{repo}",result="{result_type}",task="{task}"'
                runs_counter[key] = runs_counter.get(key, 0) + 1

                recorded_runs[d] = {
                    "status": raw_status,
                    "result_type": result_type,
                    "mtime": status_mtime,
                }

            except Exception as e:
                self.error(f"autopilot ログ処理失敗 ({d}): {e}")

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

        self.update_active_sessions()
        self.collect_claude()
        self.collect_antigravity()
        self.collect_orca_stats()
        self.collect_autopilot_runs()

        payload = self.generate_prometheus_payload()

        if self.dry_run:
            print(payload, end="")
            self.log(f"ドライラン完了 (処理時間: {time.time() - start_time:.3f}s)")
            if self.has_errors:
                sys.exit(1)
            return

        if payload.strip():
            self.send_to_victoriametrics(payload)
        else:
            self.log("メトリクスが空のため送信をスキップした")

        self._save_state()
        self.log(f"集計完了 (処理時間: {time.time() - start_time:.3f}s)")

        if self.has_errors:
            sys.exit(1)


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
