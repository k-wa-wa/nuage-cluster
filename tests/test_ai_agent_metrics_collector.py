#!/usr/bin/env python3
"""
ai-agent-metrics-collector.py の単体テスト。
"""

import importlib
import json
import os
import shutil
import sqlite3
import sys
import tempfile
import unittest
from io import BytesIO
from unittest import mock

# テスト対象スクリプトのインポート
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
collector_mod = importlib.import_module("ai-agent-metrics-collector")

normalize_identifier = collector_mod.normalize_identifier
normalize_branch_name = collector_mod.normalize_branch_name
normalize_repo_name = collector_mod.normalize_repo_name
normalize_model_name = collector_mod.normalize_model_name
get_git_branch_from_worktree = collector_mod.get_git_branch_from_worktree
escape_prometheus_label = collector_mod.escape_prometheus_label
extract_task_from_brief = collector_mod.extract_task_from_brief
resolve_task_label = collector_mod.resolve_task_label
extract_pr_number = collector_mod.extract_pr_number
is_terminal_autopilot_status = collector_mod.is_terminal_autopilot_status
normalize_autopilot_phase = collector_mod.normalize_autopilot_phase
is_pid_running = collector_mod.is_pid_running
get_running_autopilot_pid = collector_mod.get_running_autopilot_pid
_read_run_log_steps = collector_mod._read_run_log_steps
detect_phase = collector_mod.detect_phase
get_antigravity_conversation_meta = collector_mod.get_antigravity_conversation_meta
get_antigravity_conversation_repo = collector_mod.get_antigravity_conversation_repo
parse_rates_yaml = collector_mod.parse_rates_yaml
load_rates = collector_mod.load_rates
match_model_rate_key = collector_mod.match_model_rate_key
format_usd = collector_mod.format_usd
MetricsCollector = collector_mod.MetricsCollector
CURRENT_STATE_VERSION = collector_mod.CURRENT_STATE_VERSION


class TestNormalizationAndExtraction(unittest.TestCase):
    def test_normalize_identifier(self):
        self.assertEqual(normalize_identifier("Claude-Opus-5.5"), "claude-opus-5-5")
        self.assertEqual(normalize_identifier("Gemini 3.8 Flash"), "gemini-3-8-flash")
        self.assertEqual(normalize_identifier(""), "unknown")
        self.assertEqual(normalize_identifier(None), "unknown")

    def test_normalize_branch_name(self):
        self.assertEqual(normalize_branch_name("refs/heads/bot-wa-wa/bobtail"), "bot-wa-wa/bobtail")
        self.assertEqual(normalize_branch_name("feature/ai-agent-metrics"), "feature/ai-agent-metrics")
        self.assertEqual(normalize_branch_name("feature/foo-tmp"), "feature/foo-tmp")
        self.assertEqual(normalize_branch_name("tmp"), "tmp")
        self.assertEqual(normalize_branch_name("/tmp"), "tmp")
        self.assertEqual(normalize_branch_name("HEAD"), "unknown")
        self.assertEqual(normalize_branch_name("invalid@branch#name"), "invalid-branch-name")
        self.assertEqual(normalize_branch_name(""), "unknown")
        self.assertEqual(normalize_branch_name(None), "unknown")

    def test_normalize_repo_name(self):
        self.assertEqual(
            normalize_repo_name("/home/nixos/orca/workspaces/nuage-cluster/feature-x"),
            "nuage-cluster",
        )
        self.assertEqual(
            normalize_repo_name("-home-nixos-orca-workspaces-nuage-cluster-anthias"),
            "nuage-cluster",
        )
        self.assertEqual(
            normalize_repo_name("-home-nixos-orca-workspaces-pechka-ui-guardrails"),
            "pechka",
        )
        self.assertEqual(
            normalize_repo_name("/home/nixos/.claude/projects/-tmp/xxx.jsonl"),
            "tmp",
        )
        self.assertEqual(
            normalize_repo_name("/home/nixos/orca/workspaces/nuage-workspace/main"),
            "nuage-workspace",
        )
        self.assertEqual(
            normalize_repo_name("-home-nixos-orca-workspaces-nuage-workspace-feature"),
            "nuage-workspace",
        )
        self.assertEqual(
            normalize_repo_name("file:///home/nixos/orca/workspaces/pechka/lanternfish"),
            "pechka",
        )
        self.assertEqual(
            normalize_repo_name("file:///tmp"),
            "tmp",
        )
        self.assertEqual(normalize_repo_name(""), "unknown")

    def test_normalize_model_name(self):
        self.assertEqual(
            normalize_model_name("Gemini 3.8 Flash (High)"),
            "gemini-3-8-flash-high",
        )
        self.assertEqual(
            normalize_model_name("Claude Opus 5.5 (Low)"),
            "claude-opus-5-5-low",
        )
        self.assertEqual(
            normalize_model_name("claude-opus-5-5"),
            "claude-opus-5-5",
        )
        self.assertEqual(normalize_model_name(""), "unknown")

    def test_extract_task_from_brief(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            auto_dir = os.path.join(tmp_dir, ".autopilot")
            os.makedirs(auto_dir, exist_ok=True)
            brief_file = os.path.join(auto_dir, "brief.md")
            with open(brief_file, "w", encoding="utf-8") as f:
                f.write("# メトリクス抽出機能の「拡張」と\"検証\"\n\n本文...")

            task = extract_task_from_brief(tmp_dir)
            self.assertEqual(task, 'メトリクス抽出機能の「拡張」と\\"検証\\"')

            # brief.md がない場合
            self.assertEqual(extract_task_from_brief("/nonexistent/path"), "unknown")

    def test_resolve_task_label_and_escaping(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            auto_dir = os.path.join(tmp_dir, ".autopilot")
            os.makedirs(auto_dir, exist_ok=True)
            brief_file = os.path.join(auto_dir, "brief.md")
            with open(brief_file, "w", encoding="utf-8") as f:
                f.write('# 日本語タスク名 "引用" と \\パス\\ 連携\n\n本文\n')
            brief_task = extract_task_from_brief(tmp_dir)

            # 1. phase == "portal" の場合は brief_task が存在しても "portal" となること
            self.assertEqual(
                resolve_task_label(phase="portal", branch="bot-wa-wa/feat", brief_task=brief_task),
                "portal",
            )

            # 2. phase != "portal" で確定済みの brief_task が存在する場合は日本語タスク名（エスケープ済み）となること
            self.assertEqual(
                resolve_task_label(phase="implement", branch="bot-wa-wa/feat", brief_task=brief_task),
                '日本語タスク名 \\"引用\\" と \\\\パス\\\\ 連携',
            )

            # 3. brief_task が未確定（"unknown"）の場合は branch にフォールバックされること
            self.assertEqual(
                resolve_task_label(phase="implement", branch="bot-wa-wa/fallback-branch", brief_task="unknown"),
                "bot-wa-wa/fallback-branch",
            )

            # 4. brief_task も未確定で branch も不明な場合は "unknown" となること
            self.assertEqual(
                resolve_task_label(phase="review", branch="unknown", brief_task="unknown"),
                "unknown",
            )
            self.assertEqual(
                resolve_task_label(phase="review", branch="", brief_task=""),
                "unknown",
            )

            # 5. 改行やタブ文字のエスケープ確認
            self.assertEqual(
                escape_prometheus_label('タスク\n改行\tタブ"クォート"\\バックスラッシュ'),
                'タスク 改行 タブ\\"クォート\\"\\\\バックスラッシュ',
            )

    def test_extract_pr_number(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            auto_dir = os.path.join(tmp_dir, ".autopilot")
            os.makedirs(auto_dir, exist_ok=True)

            # run.log に PR #57
            with open(os.path.join(auto_dir, "run.log"), "w", encoding="utf-8") as f:
                f.write("[10:00:00] PR #57\n[10:05:00] == done\n")
            self.assertEqual(extract_pr_number(tmp_dir), "57")

            # autopilot が記録した [HH:MM:SS] PR #N 行がある場合、エージェント出力内の別 PR URL より最優先される
            with open(os.path.join(auto_dir, "run.log"), "w", encoding="utf-8") as f:
                f.write(
                    "[10:00:00] start impl=agy level=high reviewers=claude base=abcdef from=implement\n"
                    "[10:05:00] PR #64\n"
                    "[10:10:00] == fixing (round 1)\n"
                    "直前 PR #63 (https://github.com/k-wa-wa/nuage-cluster/pull/63) の仕様に合わせて修正した。\n"
                )
            self.assertEqual(extract_pr_number(tmp_dir, repo="nuage-cluster"), "64")

            # [HH:MM:SS] PR #N 行が無い場合、result.md 等にある URL 形式から抽出する
            os.remove(os.path.join(auto_dir, "run.log"))
            with open(os.path.join(auto_dir, "result.md"), "w", encoding="utf-8") as f:
                f.write("PR: https://github.com/k-wa-wa/nuage-cluster/pull/123\n")
            self.assertEqual(extract_pr_number(tmp_dir), "123")

            # 複数リポジトリの URL が含まれる場合、指定した repo の URL を優先
            with open(os.path.join(auto_dir, "result.md"), "w", encoding="utf-8") as f:
                f.write(
                    "PR: https://github.com/k-wa-wa/nuage-cluster/pull/123\n"
                    "後作業: https://github.com/k-wa-wa/nuage-monitoring-stack/pull/999\n"
                )
            self.assertEqual(extract_pr_number(tmp_dir, repo="nuage-cluster"), "123")

            # ワークスペースを使い回した場合: 最後の start impl= 行より前の過去 run の PR は拾わない
            os.remove(os.path.join(auto_dir, "result.md"))
            with open(os.path.join(auto_dir, "run.log"), "w", encoding="utf-8") as f:
                f.write(
                    "[23:27:23] start impl=agy level=high reviewers=claude base=13e10339 from=implement\n"
                    "- PR: https://github.com/k-wa-wa/nuage-cluster/pull/60\n"
                    "[23:42:28] PR #60\n"
                    "[00:29:32] == needs-human: 修正ループが上限に達した\n"
                    "[00:14:24] start impl=agy level=high reviewers=claude base=1cfde718 from=implement\n"
                    "[00:14:24] == implementing (agy)\n"
                )
            self.assertEqual(extract_pr_number(tmp_dir, repo="nuage-cluster", default="unknown"), "unknown")
            self.assertEqual(extract_pr_number(tmp_dir, repo="nuage-cluster"), "none")

            # 新しい run で PR #65 が作成されたら、過去 run の URL (#60) ではなく #65 を返す
            with open(os.path.join(auto_dir, "run.log"), "a", encoding="utf-8") as f:
                f.write("[00:20:00] PR #65\n")
            self.assertEqual(extract_pr_number(tmp_dir, repo="nuage-cluster", default="unknown"), "65")

            # allow_fallback=False の場合、[HH:MM:SS] PR #N 行が無ければエージェント出力内の URL や PR #N を拾わず default を返す
            with open(os.path.join(auto_dir, "run.log"), "w", encoding="utf-8") as f:
                f.write(
                    "[10:00:00] start impl=agy level=high reviewers=claude base=abcdef from=implement\n"
                    "[10:00:01] == implementing (agy)\n"
                    "直前 PR #63 (https://github.com/k-wa-wa/nuage-cluster/pull/63) を確認した。\n"
                )
            self.assertEqual(
                extract_pr_number(tmp_dir, repo="nuage-cluster", default="unknown", allow_fallback=False),
                "unknown",
            )
            self.assertEqual(
                extract_pr_number(tmp_dir, repo="nuage-cluster", default="none", allow_fallback=True),
                "63",
            )

            # PR 記載なし
            with tempfile.TemporaryDirectory() as empty_dir:
                self.assertEqual(extract_pr_number(empty_dir), "none")

    def test_run_log_steps_prefix_matching(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            auto_dir = os.path.join(tmp_dir, ".autopilot")
            os.makedirs(auto_dir, exist_ok=True)
            log_path = os.path.join(auto_dir, "run.log")
            # 1. start 行が無い run.log では従来どおり全体を対象とする
            with open(log_path, "w", encoding="utf-8") as f:
                f.write(
                    "[10:00:00] == implementing (claude)\n"
                    "   - コメント内で `== summarizing` に言及した行\n"
                    "   - `== reviewing` というテキストを含む説明文\n"
                    "   - 本文中の `== gating` への言及\n"
                    "[10:03:00] == gating (round 1: claude)\n"
                    "[10:05:00] == fixing (round 1)\n"
                    "[10:08:00] == gating (round 2: agy)\n"
                )
            _read_run_log_steps.cache_clear()
            steps = _read_run_log_steps(log_path, 1.0)
            self.assertEqual(steps, ["implement", "gate", "fix", "gate"])
            self.assertEqual(collector_mod.get_phase_from_run_log(tmp_dir), "gate")

            # 2. 複数の start 行がある場合、最新の start 行より後のみを対象とする
            #    前回実行が == gating で終了し、最新 start 行の後が == specifying / == spec reviewing のみなら [] / "unknown"
            with open(log_path, "w", encoding="utf-8") as f:
                f.write(
                    "[10:00:00] start impl=agy level=high reviewers=claude base=aaaa1111 from=implement\n"
                    "[10:01:00] == implementing (agy)\n"
                    "[10:05:00] == gating (round 1: claude)\n"
                    "[10:10:00] == needs-human: ゲート失敗\n"
                    "[11:00:00] start impl=agy level=high reviewers=claude base=aaaa1111 from=spec\n"
                    "[11:00:01] == specifying (agy)\n"
                    "[11:05:00] == spec reviewing (round 1: claude)\n"
                )
            _read_run_log_steps.cache_clear()
            self.assertEqual(_read_run_log_steps(log_path, 2.0), [])
            self.assertEqual(collector_mod.get_phase_from_run_log(tmp_dir), "unknown")

            # 3. 最新 start 行の後に == implementing や == gating が進めばそれを返す
            with open(log_path, "a", encoding="utf-8") as f:
                f.write("[11:10:00] == implementing (agy)\n[11:15:00] == gating (round 1: codex)\n")
            _read_run_log_steps.cache_clear()
            self.assertEqual(_read_run_log_steps(log_path, 3.0), ["implement", "gate"])
            self.assertEqual(collector_mod.get_phase_from_run_log(tmp_dir), "gate")

    def test_detect_phase(self):
        self.assertEqual(
            detect_phase("あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。"),
            "implement",
        )
        self.assertEqual(
            detect_phase("あなたはコードレビュアーである。ファイルは一切変更しない。`git diff` をレビューする。"),
            "review",
        )
        # autopilot-run の gate() 準拠プロンプトおよび手順書実行条件
        self.assertEqual(
            detect_phase(
                "あなたはリポジトリのゲート検証担当である。ファイルは一切変更しない。\n"
                "以下のゲートの手順書に従ってチェックを実際に実行して確かめる。"
            ),
            "gate",
        )
        self.assertEqual(
            detect_phase("ゲートの手順書を読み、対象コマンドを実際に実行して確かめる。"),
            "gate",
        )
        self.assertEqual(
            detect_phase("次のファイルを読み、直すべきものを直す。\n- レビュー結果: .autopilot/review-1-agy.md"),
            "fix",
        )
        # ゲート不合格結果を含む fix() プロンプトは gate ではなく fix が優先される
        self.assertEqual(
            detect_phase(
                "あなたは自律実行の担当である。\n"
                "次のファイルを読み、直すべきものを直す。\n"
                "- ゲートの不合格結果: .autopilot/gate-1-claude.md\n"
                "ゲートの手順書にあるコマンドを実際に実行して確かめる必要はない。"
            ),
            "fix",
        )
        # 人間からの追加指示に「レビューする」が含まれていても fix が優先される
        self.assertEqual(
            detect_phase(
                "あなたは自律実行の担当である。\n"
                "次のファイルを読み、直すべきものを直す。\n"
                "- 人間からの追加指示: 指摘の箇所をレビューする（最優先）\n"
                "- レビュー結果: .autopilot/review-2-claude.md\n"
                "レビューの must は原則採用する。"
            ),
            "fix",
        )
        self.assertEqual(
            detect_phase("人間向けの要約を .autopilot/result.md に書く。PR #57 の本文も同じ内容で更新する。"),
            "summarize",
        )
        # gate-src-*.md や「ゲート結果について」を含む summarize() プロンプトも gate に誤判定されない
        self.assertEqual(
            detect_phase(
                "あなたは自律実行の担当である。\n"
                ".autopilot/brief.md・decisions.md・gate-src-*.md・review-*.md を元に、"
                "人間向けの要約を .autopilot/result.md に書く。ゲート結果について短くまとめる。"
            ),
            "summarize",
        )
        # 単なる会話や「レビューする」動詞・単語の「ゲート」「gate」のみでは判定されない
        self.assertEqual(detect_phase("このコードをレビューする計画を立てて"), "unknown")
        self.assertEqual(detect_phase("ゲート結果を確認したい"), "unknown")
        self.assertEqual(detect_phase("gate の仕組みを教えて"), "unknown")
        self.assertEqual(detect_phase("ゲートの手順書だけ読む"), "unknown")
        self.assertEqual(detect_phase("実際に実行して確かめるだけ"), "unknown")
        self.assertEqual(detect_phase("何気ない会話"), "unknown")

    def test_get_git_branch_from_worktree(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            # 1. 通常リポジトリ (.git がディレクトリ)
            repo_dir = os.path.join(tmp_dir, "repo")
            git_dir = os.path.join(repo_dir, ".git")
            os.makedirs(git_dir, exist_ok=True)
            with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
                f.write("ref: refs/heads/main\n")
            self.assertEqual(get_git_branch_from_worktree(repo_dir), "main")

            # 2. git worktree (.git がファイルで gitdir: 指示)
            main_gitdir = os.path.join(tmp_dir, "main-git", "worktrees", "wt-1")
            os.makedirs(main_gitdir, exist_ok=True)
            with open(os.path.join(main_gitdir, "HEAD"), "w", encoding="utf-8") as f:
                f.write("ref: refs/heads/bot-wa-wa/feature-test\n")

            wt_dir = os.path.join(tmp_dir, "wt-dir")
            os.makedirs(wt_dir, exist_ok=True)
            with open(os.path.join(wt_dir, ".git"), "w", encoding="utf-8") as f:
                f.write(f"gitdir: {main_gitdir}\n")

            self.assertEqual(get_git_branch_from_worktree(wt_dir), "bot-wa-wa/feature-test")

            # 3. /tmp パス
            self.assertEqual(get_git_branch_from_worktree("/tmp"), "tmp")
            self.assertEqual(get_git_branch_from_worktree("/home/nixos/.claude/projects/-tmp/session.jsonl"), "tmp")


class TestMetricsCollector(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.state_file = os.path.join(self.test_dir, "state.json")

    def tearDown(self):
        shutil.rmtree(self.test_dir)

    def test_claude_collection(self):
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-1.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "queue-operation",
                "content": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。",
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                "gitBranch": "bot-wa-wa/test-branch",
                "message": {
                    "id": "msg-001",
                    "model": "claude-opus-5-5",
                    "usage": {
                        "input_tokens": 100,
                        "output_tokens": 50,
                        "cache_read_input_tokens": 200,
                        "cache_creation_input_tokens": 300,
                        "output_tokens_details": {
                            "thinking_tokens": 10,
                        },
                    },
                },
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "claude" in p else []
        try:
            collector.collect_claude()
        finally:
            collector_mod.glob.glob = orig_glob

        counters = collector.state["counters"]
        tokens = counters["tokens"]
        sessions = counters["sessions"]

        expected_key = 'agent="claude",branch="bot-wa-wa/test-branch",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="bot-wa-wa/test-branch",type="input"'
        self.assertIn(expected_key, tokens)
        self.assertEqual(tokens[expected_key], 100)
        thinking_key = 'agent="claude",branch="bot-wa-wa/test-branch",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="bot-wa-wa/test-branch",type="thinking"'
        self.assertEqual(tokens[thinking_key], 10)
        session_key = 'agent="claude",branch="bot-wa-wa/test-branch",phase="implement",repo="nuage-cluster"'
        self.assertEqual(sessions[session_key], 1)

    def test_claude_phases(self):
        # review, fix, summarize, gate 各フェーズで正しくラベルが付与されることのテスト
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)

        orig_glob = collector_mod.glob.glob
        try:
            for idx, (prompt, expected_phase) in enumerate([
                ("あなたはコードレビュアーである。レビューする。", "review"),
                ("直すべきものを直す。レビュー結果: .autopilot/review-1-agy.md", "fix"),
                ("人間向けの要約を .autopilot/result.md に書く。", "summarize"),
                ("あなたはリポジトリのゲート検証担当である。ゲートの手順書に従って実際に実行して確かめる。", "gate"),
            ]):
                jsonl_path = os.path.join(project_dir, f"session-phase-{idx}.jsonl")
                with open(jsonl_path, "w", encoding="utf-8") as f:
                    f.write(json.dumps({
                        "type": "queue-operation",
                        "content": prompt,
                    }) + "\n")
                    f.write(json.dumps({
                        "type": "assistant",
                        "entrypoint": "sdk-cli",
                        "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                        "gitBranch": "bot-wa-wa/phase-branch",
                        "message": {
                            "id": f"msg-phase-{idx}",
                            "model": "claude-opus-5-5",
                            "usage": {"input_tokens": 10, "output_tokens": 5},
                        },
                    }) + "\n")

                collector = MetricsCollector(
                    state_file=self.state_file,
                    vm_url="http://localhost:8427",
                    dry_run=True,
                )

                collector_mod.glob.glob = lambda p, jp=jsonl_path: [jp] if "claude" in p else []
                collector.collect_claude()

                tokens = collector.state["counters"]["tokens"]
                expected_key = f'agent="claude",branch="bot-wa-wa/phase-branch",model="claude-opus-5-5",phase="{expected_phase}",repo="nuage-cluster",task="bot-wa-wa/phase-branch",type="input"'
                self.assertIn(expected_key, tokens)
                self.assertEqual(tokens[expected_key], 10)
        finally:
            collector_mod.glob.glob = orig_glob

    def test_claude_sdk_unknown_phase(self):
        # sdk-cli だがプロンプトが定型外（動作確認等の ok）で run.log も無い場合、phase="unknown" になること
        project_dir = os.path.join(self.test_dir, "projects", "-tmp")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-test-ok.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "user",
                "entrypoint": "sdk-cli",
                "message": {"content": "Reply with exactly: ok"},
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": "/tmp",
                "gitBranch": "tmp",
                "message": {
                    "id": "msg-ok-1",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 15, "output_tokens": 2},
                },
            }) + "\n")

        orig_glob = collector_mod.glob.glob
        try:
            collector = MetricsCollector(
                state_file=self.state_file,
                vm_url="http://localhost:8427",
                dry_run=True,
            )
            collector_mod.glob.glob = lambda p: [jsonl_path] if "claude" in p else []
            collector.collect_claude()

            tokens = collector.state["counters"]["tokens"]
            sessions = collector.state["counters"]["sessions"]

            expected_token_key = 'agent="claude",branch="tmp",model="claude-opus-5-5",phase="unknown",repo="tmp",task="tmp",type="input"'
            self.assertIn(expected_token_key, tokens)
            self.assertEqual(tokens[expected_token_key], 15)

            # phase="implement" に紛れ込んでいないこと
            for k in tokens:
                self.assertNotIn('phase="implement"', k)

            expected_session_key = 'agent="claude",branch="tmp",phase="unknown",repo="tmp"'
            self.assertIn(expected_session_key, sessions)
            self.assertEqual(sessions[expected_session_key], 1)
        finally:
            collector_mod.glob.glob = orig_glob

    def test_claude_tool_result_does_not_change_phase(self):
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-tool-result.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            # 1. 初回の autopilot 実装指示
            f.write(json.dumps({
                "type": "user",
                "entrypoint": "sdk-cli",
                "message": {"content": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。"},
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                "gitBranch": "bot-wa-wa/feat-tool",
                "message": {
                    "id": "msg-tool-1",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 50, "output_tokens": 20},
                },
            }) + "\n")
            # 2. ツールの実行結果 (type=user, content=list) に別フェーズの文言が含まれる
            f.write(json.dumps({
                "type": "user",
                "entrypoint": "sdk-cli",
                "message": {
                    "content": [
                        {
                            "type": "tool_result",
                            "content": "あなたはコードレビュアーである。レビューする。人間向けの要約を .autopilot/result.md に書く。",
                        }
                    ]
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                "gitBranch": "bot-wa-wa/feat-tool",
                "message": {
                    "id": "msg-tool-2",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 60, "output_tokens": 30},
                },
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "claude" in p else []
        try:
            collector.collect_claude()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector.state["counters"]["tokens"]
        # すべて implement として集計され、review や summarize に化けないこと
        impl_key_input = 'agent="claude",branch="bot-wa-wa/feat-tool",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="bot-wa-wa/feat-tool",type="input"'
        impl_key_output = 'agent="claude",branch="bot-wa-wa/feat-tool",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="bot-wa-wa/feat-tool",type="output"'
        self.assertIn(impl_key_input, tokens)
        self.assertEqual(tokens[impl_key_input], 110)
        self.assertIn(impl_key_output, tokens)
        self.assertEqual(tokens[impl_key_output], 50)

        for k in tokens:
            self.assertNotIn('phase="review"', k)
            self.assertNotIn('phase="summarize"', k)

    def test_claude_cli_session_portal_fixed(self):
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-cli.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "attachment",
                "entrypoint": "cli",
            }) + "\n")
            # 窓口セッションでユーザーが「レビューする」と発言
            f.write(json.dumps({
                "type": "user",
                "entrypoint": "cli",
                "message": {"content": "あなたはコードレビュアーである。レビューする。"},
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                "gitBranch": "bot-wa-wa/feat-cli",
                "message": {
                    "id": "msg-cli-1",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 40, "output_tokens": 10},
                },
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "claude" in p else []
        try:
            collector.collect_claude()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector.state["counters"]["tokens"]
        portal_key_input = 'agent="claude",branch="bot-wa-wa/feat-cli",model="claude-opus-5-5",phase="portal",repo="nuage-cluster",task="portal",type="input"'
        self.assertIn(portal_key_input, tokens)
        self.assertEqual(tokens[portal_key_input], 40)
        # offset メタデータの context, phase, task も portal に固定されること
        meta = collector.state["claude_offsets"][jsonl_path]
        self.assertEqual(meta["context"], "portal")
        self.assertEqual(meta["phase"], "portal")
        self.assertEqual(meta["task"], "portal")

    def test_claude_cli_with_run_log_remains_portal(self):
        ws_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "test-runlog")
        auto_dir = os.path.join(ws_dir, ".autopilot")
        os.makedirs(auto_dir, exist_ok=True)
        with open(os.path.join(auto_dir, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] == reviewing (round 1: claude)\n")

        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test-runlog")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-cli-runlog.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "attachment",
                "entrypoint": "cli",
            }) + "\n")
            f.write(json.dumps({
                "type": "user",
                "entrypoint": "cli",
                "message": {"content": "進捗どう？"},
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "cli",
                "cwd": ws_dir,
                "gitBranch": "bot-wa-wa/feat-runlog",
                "message": {
                    "id": "msg-cli-runlog-1",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 30, "output_tokens": 15},
                },
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "claude" in p else []
        try:
            collector.collect_claude()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector.state["counters"]["tokens"]
        portal_key_input = 'agent="claude",branch="bot-wa-wa/feat-runlog",model="claude-opus-5-5",phase="portal",repo="nuage-cluster",task="portal",type="input"'
        self.assertIn(portal_key_input, tokens)
        self.assertEqual(tokens[portal_key_input], 30)
        # run.log の review に引っ張られないこと
        for k in tokens:
            self.assertNotIn('phase="review"', k)

    def test_claude_duplicate_message_id_dedup(self):
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-dup.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "user",
                "entrypoint": "sdk-cli",
                "message": {"content": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。"},
            }) + "\n")
            for _ in range(3):
                f.write(json.dumps({
                    "type": "assistant",
                    "entrypoint": "sdk-cli",
                    "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                    "gitBranch": "bot-wa-wa/test-branch",
                    "message": {
                        "id": "msg-dup-123",
                        "model": "claude-opus-5-5",
                        "usage": {
                            "input_tokens": 100,
                            "output_tokens": 50,
                        },
                    },
                }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "claude" in p else []
        try:
            collector.collect_claude()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector.state["counters"]["tokens"]
        key_input = 'agent="claude",branch="bot-wa-wa/test-branch",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="bot-wa-wa/test-branch",type="input"'
        key_output = 'agent="claude",branch="bot-wa-wa/test-branch",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="bot-wa-wa/test-branch",type="output"'
        self.assertEqual(tokens[key_input], 100)
        self.assertEqual(tokens[key_output], 50)

    def test_antigravity_collection(self):
        brain_dir = os.path.join(self.test_dir, "brain", "conv-1", ".system_generated", "logs")
        os.makedirs(brain_dir, exist_ok=True)
        transcript_path = os.path.join(brain_dir, "transcript.jsonl")

        # mock git worktree
        wt_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "feat")
        git_dir = os.path.join(wt_dir, ".git")
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/feat-branch\n")

        with open(transcript_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>あなたは自律実行の担当である。</USER_REQUEST><USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Gemini 3.8 Flash (High).</USER_SETTINGS_CHANGE>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 1200,
                "output_tokens": 80,
                "cache_read_tokens": 500,
                "content": f"ワークスペース {wt_dir} で作業する。",
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [transcript_path] if "antigravity" in p else []
        try:
            collector.collect_antigravity()
        finally:
            collector_mod.glob.glob = orig_glob

        counters = collector.state["counters"]
        tokens = counters["tokens"]
        sessions = counters["sessions"]

        expected_key = 'agent="agy",branch="bot-wa-wa/feat-branch",model="gemini-3-8-flash-high",phase="implement",repo="nuage-cluster",task="bot-wa-wa/feat-branch",type="input"'
        self.assertIn(expected_key, tokens)
        self.assertEqual(tokens[expected_key], 1200)
        out_key = 'agent="agy",branch="bot-wa-wa/feat-branch",model="gemini-3-8-flash-high",phase="implement",repo="nuage-cluster",task="bot-wa-wa/feat-branch",type="output"'
        self.assertEqual(tokens[out_key], 80)
        s_key = 'agent="agy",branch="bot-wa-wa/feat-branch",phase="implement",repo="nuage-cluster"'
        self.assertEqual(sessions[s_key], 1)

    def test_antigravity_incremental_preserves_labels(self):
        brain_dir = os.path.join(self.test_dir, "brain", "conv-inc", ".system_generated", "logs")
        os.makedirs(brain_dir, exist_ok=True)
        transcript_path = os.path.join(brain_dir, "transcript.jsonl")

        wt_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "feat")
        git_dir = os.path.join(wt_dir, ".git")
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/feat-branch\n")

        with open(transcript_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>あなたは自律実行の担当である。</USER_REQUEST><USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Gemini 3.8 Flash (High).</USER_SETTINGS_CHANGE>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 10,
                "output_tokens": 5,
                "content": f"ワークスペース {wt_dir} で作業する。",
            }) + "\n")

        collector1 = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=False,
        )

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [transcript_path] if "antigravity" in p else []
        try:
            collector1.collect_antigravity()
            collector1._save_state()
        finally:
            collector_mod.glob.glob = orig_glob

        # 追記
        with open(transcript_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 2,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 20,
                "output_tokens": 15,
                "content": "追加の思考ログ",
            }) + "\n")

        collector2 = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=False,
        )

        collector_mod.glob.glob = lambda p: [transcript_path] if "antigravity" in p else []
        try:
            collector2.collect_antigravity()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector2.state["counters"]["tokens"]
        expected_key = 'agent="agy",branch="bot-wa-wa/feat-branch",model="gemini-3-8-flash-high",phase="implement",repo="nuage-cluster",task="bot-wa-wa/feat-branch",type="input"'
        self.assertIn(expected_key, tokens)
        self.assertEqual(tokens[expected_key], 30)

    def test_file_error_rollback(self):
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-err.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                "message": {
                    "id": "msg-err-1",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 100, "output_tokens": 50},
                },
            }) + "\n")
            f.write('{"type": "assistant", "message": {"id": "msg-err-2", "usage": {"input_tokens": "INVALID_NOT_INT"}}}\n')

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "claude" in p else []
        try:
            collector.collect_claude()
        finally:
            collector_mod.glob.glob = orig_glob

        self.assertTrue(collector.has_errors)
        self.assertEqual(len(collector.state["counters"]["tokens"]), 0)
        self.assertEqual(len(collector.state["counters"]["cost_usd"]), 0)
        self.assertNotIn(jsonl_path, collector.state["claude_offsets"])

    def test_autopilot_runs_collection(self):
        # モックの worktree と .autopilot ディレクトリを作成
        auto_dir_done = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-done", ".autopilot")
        os.makedirs(auto_dir_done, exist_ok=True)
        with open(os.path.join(auto_dir_done, "status"), "w", encoding="utf-8") as f:
            f.write("done\n")
        with open(os.path.join(auto_dir_done, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] start impl=claude level=high reviewers=agy base=abcdef from=implement\n[10:05:00] PR #57\n")
        with open(os.path.join(auto_dir_done, "brief.md"), "w", encoding="utf-8") as f:
            f.write("# 完了したタスクのタイトル\n")
        git_done = os.path.join(os.path.dirname(auto_dir_done), ".git")
        os.makedirs(git_done, exist_ok=True)
        with open(os.path.join(git_done, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/ws-done-branch\n")

        auto_dir_failed = os.path.join(self.test_dir, "workspaces", "pechka", "ws-failed", ".autopilot")
        os.makedirs(auto_dir_failed, exist_ok=True)
        with open(os.path.join(auto_dir_failed, "status"), "w", encoding="utf-8") as f:
            f.write("failed: test execution timed out\n")
        with open(os.path.join(auto_dir_failed, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] start impl=agy level=medium reviewers=claude base=123456\n")
        with open(os.path.join(auto_dir_failed, "brief.md"), "w", encoding="utf-8") as f:
            f.write("# 失敗したタスク\n")

        auto_dir_human = os.path.join(self.test_dir, "workspaces", "nuage-autopilot5", "ws-human", ".autopilot")
        os.makedirs(auto_dir_human, exist_ok=True)
        with open(os.path.join(auto_dir_human, "status"), "w", encoding="utf-8") as f:
            f.write("needs-human: merge conflicts require user intervention\n")
        with open(os.path.join(auto_dir_human, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] start impl=claude level=low\n")
        with open(os.path.join(auto_dir_human, "brief.md"), "w", encoding="utf-8") as f:
            f.write("# 人間の判断が必要なタスク\n")

        auto_dir_running = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-running", ".autopilot")
        os.makedirs(auto_dir_running, exist_ok=True)
        with open(os.path.join(auto_dir_running, "status"), "w", encoding="utf-8") as f:
            f.write("fixing (round 2)\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        all_dirs = [auto_dir_done, auto_dir_failed, auto_dir_human, auto_dir_running]
        orig_glob = collector_mod.glob.glob
        orig_exists = os.path.exists
        collector_mod.glob.glob = lambda p: all_dirs if "autopilot" in p else []
        os.path.exists = lambda p: True if p == "/home/nixos/orca/workspaces" else orig_exists(p)
        try:
            collector.collect_autopilot_runs()
        finally:
            collector_mod.glob.glob = orig_glob
            os.path.exists = orig_exists

        runs = collector.state["counters"]["autopilot_runs"]
        expected_done = 'branch="bot-wa-wa/ws-done-branch",impl="claude",level="high",pr="57",repo="nuage-cluster",result="done",task="完了したタスクのタイトル"'
        self.assertEqual(runs.get(expected_done), 1)

        expected_failed = 'branch="unknown",impl="agy",level="medium",pr="none",repo="pechka",result="failed",task="失敗したタスク"'
        self.assertEqual(runs.get(expected_failed), 1)

        expected_human = 'branch="unknown",impl="claude",level="low",pr="none",repo="nuage-autopilot5",result="needs-human",task="人間の判断が必要なタスク"'
        self.assertEqual(runs.get(expected_human), 1)

        self.assertEqual(len(runs), 3)

    def test_state_file_corruption_raises_error(self):
        with open(self.state_file, "w", encoding="utf-8") as f:
            f.write("{invalid_json: true, broken")

        with self.assertRaises(RuntimeError):
            MetricsCollector(
                state_file=self.state_file,
                vm_url="http://localhost:8427",
                dry_run=True,
            )

    def test_state_migration_to_v4(self):
        # v1, v2, v3 形式の状態ファイルが読み込まれたとき v4 にマイグレーションされ、古いカウンタやオフセットがリセットされること
        v1_data = {
            "version": 1,
            "claude_offsets": {"/old/path": 100},
            "agy_offsets": {"/old/agy": 200},
            "last_orca_stats_timestamp": 5000,
            "counters": {
                "tokens": {'agent="claude",context="autopilot",repo="nuage-cluster"': 1000},
                "sessions": {},
                "duration": {},
                "autopilot_runs": {'impl="claude",level="high",repo="nuage-cluster",result="done"': 1},
            },
        }
        with open(self.state_file, "w", encoding="utf-8") as f:
            json.dump(v1_data, f)

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        self.assertEqual(collector.state["version"], CURRENT_STATE_VERSION)
        self.assertEqual(collector.state["version"], 4)
        self.assertEqual(len(collector.state["counters"]["tokens"]), 0)
        self.assertEqual(len(collector.state["counters"]["autopilot_runs"]), 0)
        self.assertEqual(len(collector.state["claude_offsets"]), 0)

        # v3 形式（task ラベル導入前のキーを含む）からの移行
        v3_data = {
            "version": 3,
            "claude_offsets": {"/old/path": {"offset": 100, "repo": "nuage-cluster"}},
            "agy_offsets": {
                "/home/nixos/.gemini/antigravity-cli/brain/cid-v3-agy/.system_generated/logs/transcript.jsonl": {
                    "offset": 200,
                    "repo": "nuage-cluster",
                    "branch": "feature/v3-branch",
                    "ws_path": "/home/nixos/orca/workspaces/nuage-cluster/v3-ws",
                }
            },
            "last_orca_stats_timestamp": 5000,
            "counters": {
                "tokens": {'agent="claude",branch="main",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",type="input"': 1000},
                "cost_usd": {'agent="claude",branch="main",model="claude-opus-5-5",phase="implement",repo="nuage-cluster"': 1.5},
                "sessions": {'agent="claude",branch="main",phase="portal",repo="nuage-cluster"': 1},
                "duration": {'agent="claude",branch="main",phase="portal",repo="nuage-cluster"': 10.5},
                "autopilot_runs": {},
            },
        }
        with open(self.state_file, "w", encoding="utf-8") as f:
            json.dump(v3_data, f)

        collector2 = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )
        self.assertEqual(collector2.state["version"], 4)
        self.assertEqual(len(collector2.state["counters"]["tokens"]), 0)
        self.assertEqual(len(collector2.state["counters"]["cost_usd"]), 0)
        self.assertEqual(len(collector2.state["counters"]["sessions"]), 0)
        self.assertEqual(len(collector2.state["counters"]["duration"]), 0)
        self.assertEqual(len(collector2.state["claude_offsets"]), 0)
        self.assertEqual(len(collector2.state["agy_offsets"]), 0)
        self.assertEqual(
            collector2.state["cid_to_meta"].get("cid-v3-agy"),
            {
                "repo": "nuage-cluster",
                "branch": "feature/v3-branch",
                "worktree": "/home/nixos/orca/workspaces/nuage-cluster/v3-ws",
            },
        )

    def test_orca_stats_portal_context(self):
        auto_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "feature-x", ".autopilot")
        os.makedirs(auto_dir, exist_ok=True)
        wt_path = os.path.dirname(auto_dir)
        git_dir = os.path.join(wt_path, ".git")
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/feature-x-branch\n")

        orca_stats_file = os.path.join(self.test_dir, "orca-stats.json")
        last_status_file = os.path.join(self.test_dir, "last-status.json")

        sk = "test-tab:test-pane"

        with open(last_status_file, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "version": 2,
                "entries": {
                    sk: {
                        "paneKey": sk,
                        "source": "claude",
                        "worktreeId": f"uuid::{wt_path}",
                    }
                }
            }))

        with open(orca_stats_file, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "schemaVersion": 1,
                "events": [
                    {
                        "type": "agent_start",
                        "at": 1000,
                        "worktreeId": f"uuid::{wt_path}",
                        "meta": {"sessionKey": sk},
                    },
                    {
                        "type": "agent_stop",
                        "at": 2000,
                        "meta": {"sessionKey": sk, "durationMs": 50000},
                    }
                ]
            }))

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_exists = os.path.exists
        def mock_exists(p):
            if p.endswith("orca-stats.json"):
                return True
            if p.endswith("last-status.json"):
                return True
            return orig_exists(p)

        orig_open = open
        def mock_open(p, *args, **kwargs):
            if str(p).endswith("orca-stats.json"):
                return orig_open(orca_stats_file, *args, **kwargs)
            if str(p).endswith("last-status.json"):
                return orig_open(last_status_file, *args, **kwargs)
            return orig_open(p, *args, **kwargs)

        import builtins
        os.path.exists = mock_exists
        builtins.open = mock_open
        try:
            collector.collect_orca_stats()
        finally:
            os.path.exists = orig_exists
            builtins.open = orig_open

        duration = collector.state["counters"]["duration"]
        expected_key = 'agent="claude",branch="feature-x-branch",phase="portal",repo="nuage-cluster"'
        self.assertIn(expected_key, duration)
        self.assertEqual(duration[expected_key], 50.0)

    def test_generate_prometheus_payload(self):
        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )
        collector.state["counters"]["tokens"] = {
            'agent="claude",branch="main",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="日本語タスク名",type="input"': 100,
        }
        collector.state["counters"]["sessions"] = {
            'agent="claude",branch="main",phase="implement",repo="nuage-cluster"': 1,
        }

        payload = collector.generate_prometheus_payload()
        self.assertIn("# TYPE nuage_ai_agent_tokens_total counter", payload)
        self.assertIn('nuage_ai_agent_tokens_total{agent="claude",branch="main",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="日本語タスク名",type="input"} 100', payload)
        self.assertIn("# TYPE nuage_ai_agent_sessions_total counter", payload)
        self.assertIn('nuage_ai_agent_sessions_total{agent="claude",branch="main",phase="implement",repo="nuage-cluster"} 1', payload)

    def test_state_persistence_and_incremental(self):
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-inc.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "user",
                "entrypoint": "sdk-cli",
                "message": {"content": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。"},
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                "gitBranch": "bot-wa-wa/inc-branch",
                "message": {
                    "id": "msg-inc-1",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 50, "output_tokens": 10},
                },
            }) + "\n")

        collector1 = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=False,
        )

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "claude" in p else []
        try:
            collector1.collect_claude()
            collector1._save_state()
        finally:
            collector_mod.glob.glob = orig_glob

        self.assertTrue(os.path.exists(self.state_file))

        # 2行目を追記
        with open(jsonl_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                "gitBranch": "bot-wa-wa/inc-branch",
                "message": {
                    "id": "msg-inc-2",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 30, "output_tokens": 5},
                },
            }) + "\n")

        collector2 = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=False,
        )
        collector_mod.glob.glob = lambda p: [jsonl_path] if "claude" in p else []
        try:
            collector2.collect_claude()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector2.state["counters"]["tokens"]
        key_input = 'agent="claude",branch="bot-wa-wa/inc-branch",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="bot-wa-wa/inc-branch",type="input"'
        self.assertEqual(tokens[key_input], 80)
        sessions = collector2.state["counters"]["sessions"]
        self.assertEqual(sessions['agent="claude",branch="bot-wa-wa/inc-branch",phase="implement",repo="nuage-cluster"'], 1)

    def test_claude_seen_message_ids_order(self):
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-order.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            for i in range(550):
                f.write(json.dumps({
                    "type": "assistant",
                    "entrypoint": "sdk-cli",
                    "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                    "gitBranch": "main",
                    "message": {
                        "id": f"msg-ord-{i:04d}",
                        "model": "claude-opus-5-5",
                        "usage": {"input_tokens": 1, "output_tokens": 1},
                    },
                }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "claude" in p else []
        try:
            collector.collect_claude()
        finally:
            collector_mod.glob.glob = orig_glob

        offset_info = collector.state["claude_offsets"][jsonl_path]
        seen_ids = offset_info["seen_message_ids"]
        self.assertEqual(len(seen_ids), 500)
        self.assertEqual(seen_ids[0], "msg-ord-0050")
        self.assertEqual(seen_ids[-1], "msg-ord-0549")

    def test_antigravity_conversation_repo_from_db(self):
        import sqlite3
        db_path = os.path.join(self.test_dir, "conversation_summaries.db")

        # mock worktree for test-1
        wt_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "my-branch")
        git_dir = os.path.join(wt_dir, ".git")
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/my-feature-branch\n")

        with sqlite3.connect(db_path) as conn:
            conn.execute("CREATE TABLE conversation_summaries (conversation_id TEXT PRIMARY KEY, workspace_uris TEXT)")
            conn.execute(
                "INSERT INTO conversation_summaries VALUES (?, ?)",
                ("cid-test-1", f'["file://{wt_dir}"]'),
            )
            conn.execute(
                "INSERT INTO conversation_summaries VALUES (?, ?)",
                ("cid-test-2", '["file:///tmp"]'),
            )

        orig_expanduser = os.path.expanduser
        os.path.expanduser = lambda p: db_path if "conversation_summaries.db" in p else orig_expanduser(p)
        try:
            repo1, branch1, ws1 = collector_mod.get_antigravity_conversation_meta("cid-test-1")
            self.assertEqual(repo1, "nuage-cluster")
            self.assertEqual(branch1, "my-feature-branch")
            self.assertEqual(ws1, wt_dir)

            repo2, branch2, ws2 = collector_mod.get_antigravity_conversation_meta("cid-test-2")
            self.assertEqual(repo2, "tmp")
            self.assertEqual(branch2, "tmp")

            repo_unknown, branch_unknown, _ = collector_mod.get_antigravity_conversation_meta("nonexistent")
            self.assertEqual(repo_unknown, "unknown")
            self.assertEqual(branch_unknown, "unknown")

            # 不完全なキャッシュ (branch="unknown", worktree="" やブランチ不明のパスA) でも DB からパス・ブランチを整合補完する
            partial_cache = {
                "cid-test-1": {"repo": "nuage-cluster", "branch": "unknown", "worktree": ""},
            }
            repo_rec, branch_rec, ws_rec = collector_mod.get_antigravity_conversation_meta("cid-test-1", partial_cache)
            self.assertEqual((repo_rec, branch_rec, ws_rec), ("nuage-cluster", "my-feature-branch", wt_dir))

            partial_path_cache = {
                "cid-test-1": {"repo": "tmp", "branch": "unknown", "worktree": "/nonexistent/partial/ws"},
            }
            repo_rec2, branch_rec2, ws_rec2 = collector_mod.get_antigravity_conversation_meta("cid-test-1", partial_path_cache)
            self.assertEqual((repo_rec2, branch_rec2, ws_rec2), ("nuage-cluster", "my-feature-branch", wt_dir))

            # 完全なキャッシュがある場合は DB で上書きしない
            complete_cache = {
                "cid-test-1": {"repo": "nuage-cluster", "branch": "pinned-branch", "worktree": "/pinned/ws"},
            }
            repo_pin, branch_pin, ws_pin = collector_mod.get_antigravity_conversation_meta("cid-test-1", complete_cache)
            self.assertEqual((repo_pin, branch_pin, ws_pin), ("nuage-cluster", "pinned-branch", "/pinned/ws"))
        finally:
            os.path.expanduser = orig_expanduser

    def test_send_failure_does_not_save_state(self):
        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=False,
        )
        collector.state["counters"]["tokens"]["test_token"] = 100
        collector.send_to_victoriametrics = mock.MagicMock(side_effect=RuntimeError("connection refused"))

        with self.assertRaises(RuntimeError):
            collector.run()

        self.assertFalse(os.path.exists(self.state_file))

    def test_send_to_victoriametrics_http_error(self):
        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=False,
        )

        with mock.patch("urllib.request.urlopen", side_effect=collector_mod.urllib.error.HTTPError(
            url="http://localhost:8427/api/v1/import/prometheus",
            code=403,
            msg="Forbidden",
            hdrs={},
            fp=BytesIO(b"unauthorized route"),
        )):
            with self.assertRaises(RuntimeError) as ctx:
                collector.send_to_victoriametrics("test_payload 1")
            self.assertIn("HTTP エラー (403)", str(ctx.exception))

        mock_resp = mock.MagicMock()
        mock_resp.status = 302
        mock_resp.__enter__.return_value = mock_resp
        with mock.patch("urllib.request.urlopen", return_value=mock_resp):
            with self.assertRaises(RuntimeError) as ctx:
                collector.send_to_victoriametrics("test_payload 1")
            self.assertIn("予期しないステータスコード: HTTP 302", str(ctx.exception))

    def test_antigravity_portal_not_overwritten_by_skill_reading(self):
        brain_dir = os.path.join(self.test_dir, "brain", "conv-portal-1", ".system_generated", "logs")
        os.makedirs(brain_dir, exist_ok=True)
        transcript_path = os.path.join(brain_dir, "transcript.jsonl")

        with open(transcript_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>アプリの状況を教えて</USER_REQUEST>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 100,
                "output_tokens": 20,
                "content": "ファイルを読みます .autopilot/brief.md を確認中",
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )
        collector.state["portal_cids"]["conv-portal-1"] = True

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [transcript_path] if "antigravity" in p else []
        try:
            collector.collect_antigravity()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector.state["counters"]["tokens"]
        expected_key = 'agent="agy",branch="unknown",model="unknown",phase="portal",repo="unknown",task="portal",type="input"'
        self.assertIn(expected_key, tokens)
        self.assertEqual(tokens[expected_key], 100)

    def test_antigravity_repo_not_overwritten_by_content_path(self):
        brain_dir = os.path.join(self.test_dir, "brain", "conv-repo-test", ".system_generated", "logs")
        os.makedirs(brain_dir, exist_ok=True)
        transcript_path = os.path.join(brain_dir, "transcript.jsonl")

        with open(transcript_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>作業開始</USER_REQUEST>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 50,
                "output_tokens": 10,
                "content": "別リポジトリのファイル /home/nixos/orca/workspaces/pechka/foo を参照した",
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )
        collector.state["cid_to_meta"]["conv-repo-test"] = {
            "repo": "nuage-cluster",
            "branch": "main",
            "worktree": "/path/to/nuage-cluster",
        }

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [transcript_path] if "antigravity" in p else []
        try:
            collector.collect_antigravity()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector.state["counters"]["tokens"]
        expected_key = 'agent="agy",branch="main",model="unknown",phase="portal",repo="nuage-cluster",task="portal",type="input"'
        self.assertIn(expected_key, tokens)
        self.assertNotIn('repo="pechka"', str(tokens))

    def test_antigravity_portal_not_mistaken_as_autopilot(self):
        # portal_cids にまだ載っていない窓口会話で「brief の要点を教えて」等の語があっても、
        # 定型文が無ければ autopilot に化けず portal のままとなること
        brain_dir = os.path.join(self.test_dir, "brain", "conv-portal-chat", ".system_generated", "logs")
        os.makedirs(brain_dir, exist_ok=True)
        transcript_path = os.path.join(brain_dir, "transcript.jsonl")

        with open(transcript_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>この PR の brief の要点を教えて。あとでレビューする予定です。</USER_REQUEST>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 120,
                "output_tokens": 40,
                "content": "承知いたしました。",
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )
        collector.state["cid_to_meta"]["conv-portal-chat"] = {
            "repo": "nuage-cluster",
            "branch": "main",
            "worktree": "/path/to/nuage-cluster",
        }

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [transcript_path] if "antigravity" in p else []
        try:
            collector.collect_antigravity()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector.state["counters"]["tokens"]
        expected_key = 'agent="agy",branch="main",model="unknown",phase="portal",repo="nuage-cluster",task="portal",type="input"'
        self.assertIn(expected_key, tokens)
        self.assertNotIn('phase="implement"', str(tokens))
        self.assertNotIn('phase="review"', str(tokens))

    def test_antigravity_run_log_fallback_with_ws_path(self):
        # 定型文があるがプロンプトからフェーズが特定できない場合、ws_path の run.log からフェーズが引けること
        wt_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "wt-fallback")
        auto_dir = os.path.join(wt_dir, ".autopilot")
        os.makedirs(auto_dir, exist_ok=True)
        with open(os.path.join(auto_dir, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] start\n== reviewing\n")

        brain_dir = os.path.join(self.test_dir, "brain", "conv-fallback-test", ".system_generated", "logs")
        os.makedirs(brain_dir, exist_ok=True)
        transcript_path = os.path.join(brain_dir, "transcript.jsonl")

        with open(transcript_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>あなたはコードレビュアーである。ファイルは一切変更しない。\n詳細な指示は別途与える。</USER_REQUEST>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 150,
                "output_tokens": 30,
                "content": "確認しました。",
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )
        collector.state["cid_to_meta"]["conv-fallback-test"] = {
            "repo": "nuage-cluster",
            "branch": "feature/test",
            "worktree": wt_dir,
        }

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [transcript_path] if "antigravity" in p else []
        try:
            collector.collect_antigravity()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector.state["counters"]["tokens"]
        expected_key = 'agent="agy",branch="feature/test",model="unknown",phase="review",repo="nuage-cluster",task="feature/test",type="input"'
        self.assertIn(expected_key, tokens)

    def test_state_cache_pruning(self):
        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=False,
        )
        for i in range(1050):
            collector.state["orca_sessions"][f"sk-{i:04d}"] = {"agent": "claude"}
            collector.state["portal_cids"][f"cid-{i:04d}"] = True

        collector._save_state()

        collector2 = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )
        self.assertEqual(len(collector2.state["orca_sessions"]), 1000)
        self.assertEqual(len(collector2.state["portal_cids"]), 1000)
        self.assertNotIn("sk-0000", collector2.state["orca_sessions"])
        self.assertIn("sk-0050", collector2.state["orca_sessions"])
        self.assertIn("sk-1049", collector2.state["orca_sessions"])

    def test_autopilot_run_latest_start(self):
        auto_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-multi-start", ".autopilot")
        os.makedirs(auto_dir, exist_ok=True)
        with open(os.path.join(auto_dir, "status"), "w", encoding="utf-8") as f:
            f.write("done\n")
        with open(os.path.join(auto_dir, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] start impl=claude level=standard reviewers=agy\n")
            f.write("[10:05:00] retry\n")
            f.write("[10:10:00] start impl=agy level=high reviewers=claude\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_glob = collector_mod.glob.glob
        orig_exists = os.path.exists
        collector_mod.glob.glob = lambda p: [auto_dir] if "autopilot" in p else []
        os.path.exists = lambda p: True if p == "/home/nixos/orca/workspaces" else orig_exists(p)
        try:
            collector.collect_autopilot_runs()
        finally:
            collector_mod.glob.glob = orig_glob
            os.path.exists = orig_exists

        runs = collector.state["counters"]["autopilot_runs"]
        expected_key = 'branch="unknown",impl="agy",level="high",pr="none",repo="nuage-cluster",result="done",task="unknown"'
        self.assertIn(expected_key, runs)
        self.assertNotIn('impl="claude"', str(runs))

    def test_parse_and_load_rates_yaml(self):
        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        rates = load_rates(repo_rates_path)

        self.assertIn("claude-opus-5-5", rates)
        self.assertEqual(rates["claude-opus-5-5"]["input"], 4.00)
        self.assertEqual(rates["claude-opus-5-5"]["output"], 20.00)
        self.assertEqual(rates["claude-opus-5-5"]["cache_read"], 0.20)
        self.assertEqual(rates["claude-opus-5-5"]["cache_creation"], 5.00)

        self.assertIn("claude-sonnet-5-5", rates)
        self.assertEqual(rates["claude-sonnet-5-5"]["input"], 2.00)
        self.assertEqual(rates["claude-sonnet-5-5"]["output"], 10.00)
        self.assertEqual(rates["claude-sonnet-5-5"]["cache_read"], 0.10)
        self.assertEqual(rates["claude-sonnet-5-5"]["cache_creation"], 2.50)

        self.assertIn("claude-haiku-5-5", rates)
        self.assertEqual(rates["claude-haiku-5-5"]["input"], 0.10)
        self.assertEqual(rates["claude-haiku-5-5"]["output"], 0.50)
        self.assertEqual(rates["claude-haiku-5-5"]["cache_read"], 0.01)
        self.assertEqual(rates["claude-haiku-5-5"]["cache_creation"], 0.125)

        self.assertIn("gemini-3.8-flash", rates)
        self.assertEqual(rates["gemini-3.8-flash"]["input"], 0.75)
        self.assertEqual(rates["gemini-3.8-flash"]["output"], 3.75)
        self.assertEqual(rates["gemini-3.8-flash"]["cache_read"], 0.075)

        self.assertIn("gemini-4-argon", rates)
        self.assertEqual(rates["gemini-4-argon"]["input"], 2.00)
        self.assertEqual(rates["gemini-4-argon"]["output"], 10.00)
        self.assertEqual(rates["gemini-4-argon"]["cache_read"], 0.10)

        self.assertIn("gemini-4-hydrogen", rates)
        self.assertEqual(rates["gemini-4-hydrogen"]["input"], 1.50)
        self.assertEqual(rates["gemini-4-hydrogen"]["output"], 7.50)
        self.assertEqual(rates["gemini-4-hydrogen"]["cache_read"], 0.075)

        self.assertIn("gemini-4-neon", rates)
        self.assertEqual(rates["gemini-4-neon"]["input"], 3.00)
        self.assertEqual(rates["gemini-4-neon"]["output"], 15.00)
        self.assertEqual(rates["gemini-4-neon"]["cache_read"], 0.15)

        self.assertIn("orchestrator-neon", rates)
        self.assertEqual(rates["orchestrator-neon"]["input"], 3.00)
        self.assertEqual(rates["orchestrator-neon"]["output"], 15.00)
        self.assertEqual(rates["orchestrator-neon"]["cache_read"], 0.15)

        self.assertIn("gemini-pro-orchestrator-neon", rates)
        self.assertEqual(rates["gemini-pro-orchestrator-neon"]["input"], 3.00)
        self.assertEqual(rates["gemini-pro-orchestrator-neon"]["output"], 15.00)
        self.assertEqual(rates["gemini-pro-orchestrator-neon"]["cache_read"], 0.15)

        self.assertIn("orchestrator-argon", rates)
        self.assertEqual(rates["orchestrator-argon"]["input"], 2.00)
        self.assertEqual(rates["orchestrator-argon"]["output"], 10.00)
        self.assertEqual(rates["orchestrator-argon"]["cache_read"], 0.10)

        self.assertIn("gemini-pro-orchestrator-g1-pro", rates)
        self.assertEqual(rates["gemini-pro-orchestrator-g1-pro"]["input"], 2.00)
        self.assertEqual(rates["gemini-pro-orchestrator-g1-pro"]["output"], 10.00)
        self.assertEqual(rates["gemini-pro-orchestrator-g1-pro"]["cache_read"], 0.10)

        self.assertIn("gpt-oss-120b", rates)
        self.assertIn("gpt-6-astra", rates)
        self.assertEqual(rates["gpt-6-astra"]["input"], 10.00)
        self.assertEqual(rates["gpt-6-astra"]["output"], 50.00)
        self.assertEqual(rates["gpt-6-astra"]["cache_read"], 1.00)
        self.assertIn("gpt-6.2-astra", rates)
        self.assertEqual(rates["gpt-6.2-astra"]["input"], 8.00)
        self.assertEqual(rates["gpt-6.2-astra"]["output"], 40.00)
        self.assertEqual(rates["gpt-6.2-astra"]["cache_read"], 0.40)
        self.assertIn("gpt-6.1-sol", rates)
        self.assertEqual(rates["gpt-6.1-sol"]["input"], 2.00)
        self.assertEqual(rates["gpt-6.1-sol"]["output"], 10.00)
        self.assertEqual(rates["gpt-6.1-sol"]["cache_read"], 0.10)
        self.assertIn("gpt-6.2-sol", rates)
        self.assertEqual(rates["gpt-6.2-sol"]["input"], 2.00)
        self.assertEqual(rates["gpt-6.2-sol"]["output"], 10.00)
        self.assertEqual(rates["gpt-6.2-sol"]["cache_read"], 0.10)
        self.assertIn("gpt-6-luna", rates)
        self.assertEqual(rates["gpt-6-luna"]["input"], 0.10)
        self.assertEqual(rates["gpt-6-luna"]["output"], 0.50)
        self.assertEqual(rates["gpt-6-luna"]["cache_read"], 0.01)
        self.assertIn("gpt-6.1-terra", rates)
        self.assertEqual(rates["gpt-6.1-terra"]["input"], 1.00)
        self.assertEqual(rates["gpt-6.1-terra"]["output"], 5.00)
        self.assertEqual(rates["gpt-6.1-terra"]["cache_read"], 0.05)

        # 不正な YAML のエラーハンドリング確認
        with self.assertRaises(ValueError):
            parse_rates_yaml("invalid_top_line\n  input: 1.0\n")
        with self.assertRaises(ValueError):
            parse_rates_yaml("model-a:\n  input: not_a_float\n")
        with self.assertRaises(ValueError):
            parse_rates_yaml("model-a:\n  input: -5.0\n")
        with self.assertRaises(ValueError):
            parse_rates_yaml("model-a:\n  cache-read: 1.5\n")
        with self.assertRaises(ValueError):
            parse_rates_yaml("model-a:\n  outptu: 75.0\n")
        with self.assertRaises(ValueError):
            parse_rates_yaml("model-empty:\n")
        with self.assertRaises(ValueError):
            parse_rates_yaml("model-a:\n  input: 1.0\nmodel-a:\n  output: 2.0\n")
        with self.assertRaises(ValueError):
            parse_rates_yaml("gemini-3.8-flash:\n  input: 0.1\ngemini-3-8-flash:\n  input: 0.2\n")
        with self.assertRaises(ValueError):
            parse_rates_yaml("model-a:\n  input: 1.0\n  input: 2.0\n")
        with self.assertRaises(ValueError):
            parse_rates_yaml("model-a:\n  input: 1.0\n    output: 2.0\n")
        with self.assertRaises(RuntimeError):
            load_rates("/nonexistent/rates.yaml")

    def test_match_model_rate_key(self):
        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        rates = load_rates(repo_rates_path)

        self.assertEqual(match_model_rate_key("gemini-3-8-flash-high", rates), "gemini-3.8-flash")
        self.assertEqual(match_model_rate_key("gemini-3-8-flash-medium", rates), "gemini-3.8-flash")
        self.assertEqual(match_model_rate_key("gemini-3-8-flash-low", rates), "gemini-3.8-flash")
        self.assertEqual(match_model_rate_key("Gemini 3.8 Flash (High)", rates), "gemini-3.8-flash")
        self.assertEqual(match_model_rate_key("gemini-4-argon-high", rates), "gemini-4-argon")
        self.assertEqual(match_model_rate_key("Gemini 4 Argon (High)", rates), "gemini-4-argon")
        self.assertEqual(match_model_rate_key("gemini-4-hydrogen-high", rates), "gemini-4-hydrogen")
        self.assertEqual(match_model_rate_key("gemini-4-hydrogen-xhigh", rates), "gemini-4-hydrogen")
        self.assertEqual(match_model_rate_key("gemini-4-hydrogen-medium", rates), "gemini-4-hydrogen")
        self.assertEqual(match_model_rate_key("gemini-4-hydrogen-low", rates), "gemini-4-hydrogen")
        self.assertEqual(match_model_rate_key("Gemini 4 Hydrogen (High)", rates), "gemini-4-hydrogen")
        self.assertEqual(match_model_rate_key("gemini-4-neon-high", rates), "gemini-4-neon")
        self.assertEqual(match_model_rate_key("Gemini 4 Neon (High)", rates), "gemini-4-neon")
        self.assertEqual(match_model_rate_key("Orchestrator (Neon)", rates), "orchestrator-neon")
        self.assertEqual(match_model_rate_key("gemini-pro-orchestrator-neon", rates), "gemini-pro-orchestrator-neon")
        self.assertEqual(match_model_rate_key("Orchestrator (Argon)", rates), "orchestrator-argon")
        self.assertEqual(match_model_rate_key("gemini-pro-orchestrator-g1-pro", rates), "gemini-pro-orchestrator-g1-pro")
        self.assertEqual(match_model_rate_key("claude-opus-5-5", rates), "claude-opus-5-5")
        self.assertEqual(match_model_rate_key("claude-opus-5-5@high", rates), "claude-opus-5-5")
        self.assertEqual(match_model_rate_key("claude-opus-5-5-low", rates), "claude-opus-5-5")
        self.assertEqual(match_model_rate_key("claude-opus-5-5-20251101", rates), "claude-opus-5-5")
        self.assertEqual(match_model_rate_key("claude-sonnet-5-5-low", rates), "claude-sonnet-5-5")
        self.assertEqual(match_model_rate_key("claude-haiku-5-5@low", rates), "claude-haiku-5-5")
        self.assertEqual(match_model_rate_key("gpt-oss-120b-medium", rates), "gpt-oss-120b")
        self.assertEqual(match_model_rate_key("gpt-6-astra", rates), "gpt-6-astra")
        self.assertEqual(match_model_rate_key("gpt-6-astra@high", rates), "gpt-6-astra")
        self.assertEqual(match_model_rate_key("gpt-6.2-astra", rates), "gpt-6.2-astra")
        self.assertEqual(match_model_rate_key("gpt-6.2-astra@high", rates), "gpt-6.2-astra")
        self.assertEqual(match_model_rate_key("gpt-6-2-astra", rates), "gpt-6.2-astra")
        self.assertEqual(match_model_rate_key("gpt-6.1-sol", rates), "gpt-6.1-sol")
        self.assertEqual(match_model_rate_key("gpt-6-1-sol", rates), "gpt-6.1-sol")
        self.assertEqual(match_model_rate_key("gpt-6.2-sol", rates), "gpt-6.2-sol")
        self.assertEqual(match_model_rate_key("gpt-6.2-sol@medium", rates), "gpt-6.2-sol")
        self.assertEqual(match_model_rate_key("gpt-6-2-sol", rates), "gpt-6.2-sol")
        self.assertEqual(match_model_rate_key("gpt-6-luna", rates), "gpt-6-luna")
        self.assertEqual(match_model_rate_key("gpt-6.1-terra", rates), "gpt-6.1-terra")
        self.assertEqual(match_model_rate_key("gpt-6-1-terra", rates), "gpt-6.1-terra")

        # 未定義モデルは None
        self.assertIsNone(match_model_rate_key("unknown", rates))
        self.assertIsNone(match_model_rate_key("synthetic", rates))
        self.assertIsNone(match_model_rate_key("gemini-3-8-pro-high", rates))
        self.assertIsNone(match_model_rate_key("gpt-5-turbo", rates))
        self.assertIsNone(match_model_rate_key("", rates))

    def test_cost_calculation_and_prometheus_output(self):
        # Claude と Antigravity のログからトークン増分×単価で USD コストが計算され、thinking は二重加算されないこと
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-cost.jsonl")

        # claude-opus-5-5: input=$4/1M, output=$20/1M, cache_read=$0.20/1M, cache_creation=$5.00/1M
        # 100,000 input ($0.40) + 20,000 output ($0.40) + 200,000 cache_read ($0.04) + 40,000 cache_creation ($0.20) = $1.04
        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "queue-operation",
                "content": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。",
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                "gitBranch": "bot-wa-wa/cost-branch",
                "message": {
                    "id": "msg-cost-1",
                    "model": "claude-opus-5-5",
                    "usage": {
                        "input_tokens": 100_000,
                        "output_tokens": 20_000,
                        "cache_read_input_tokens": 200_000,
                        "cache_creation_input_tokens": 40_000,
                        "output_tokens_details": {
                            "thinking_tokens": 5_000,
                        },
                    },
                },
            }) + "\n")

        # Antigravity: gemini-3-8-flash-high -> gemini-3.8-flash (input=$0.75/1M, output=$3.75/1M, cache_read=$0.075/1M)
        # 500,000 input ($0.375) + 100,000 output ($0.375) + 400,000 cache_read ($0.03) = $0.78
        brain_dir = os.path.join(self.test_dir, "brain", "conv-cost", ".system_generated", "logs")
        os.makedirs(brain_dir, exist_ok=True)
        transcript_path = os.path.join(brain_dir, "transcript.jsonl")
        with open(transcript_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>あなたはコードレビュアーである。</USER_REQUEST><USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Gemini 3.8 Flash (High).</USER_SETTINGS_CHANGE>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 500_000,
                "output_tokens": 100_000,
                "cache_read_tokens": 400_000,
                "content": "レビュー完了",
            }) + "\n")

        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
            rates_file=repo_rates_path,
        )
        collector.state["cid_to_meta"]["conv-cost"] = {
            "repo": "nuage-cluster",
            "branch": "bot-wa-wa/cost-branch",
            "worktree": "/home/nixos/orca/workspaces/nuage-cluster/test",
        }

        orig_glob = collector_mod.glob.glob
        def mock_glob(p):
            if "claude" in p:
                return [jsonl_path]
            if "antigravity" in p:
                return [transcript_path]
            return []

        collector_mod.glob.glob = mock_glob
        try:
            collector.collect_claude()
            collector.collect_antigravity()
        finally:
            collector_mod.glob.glob = orig_glob

        costs = collector.state["counters"]["cost_usd"]
        claude_cost_key = 'agent="claude",branch="bot-wa-wa/cost-branch",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="bot-wa-wa/cost-branch"'
        agy_cost_key = 'agent="agy",branch="bot-wa-wa/cost-branch",model="gemini-3-8-flash-high",phase="review",repo="nuage-cluster",task="bot-wa-wa/cost-branch"'

        self.assertAlmostEqual(costs[claude_cost_key], 1.04, places=8)
        self.assertAlmostEqual(costs[agy_cost_key], 0.78, places=8)

        payload = collector.generate_prometheus_payload()
        self.assertIn("# HELP nuage_ai_agent_cost_usd_total Total cost in USD used by AI agents", payload)
        self.assertIn("# TYPE nuage_ai_agent_cost_usd_total counter", payload)
        self.assertIn(f"nuage_ai_agent_cost_usd_total{{{claude_cost_key}}} 1.04", payload)
        self.assertIn(f"nuage_ai_agent_cost_usd_total{{{agy_cost_key}}} 0.78", payload)

    def test_unknown_model_cost_zero_and_warns(self):
        # 単価未定義のモデルはコスト 0 とし、警告ログが出力され、トークン数は引き続き計上されること
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-unknown-model.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                "gitBranch": "main",
                "message": {
                    "id": "msg-unk-1",
                    "model": "mystery-new-model-99",
                    "usage": {
                        "input_tokens": 50_000,
                        "output_tokens": 10_000,
                    },
                },
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "claude" in p else []
        try:
            with mock.patch.object(collector, "warn", wraps=collector.warn) as mock_warn:
                collector.collect_claude()
                mock_warn.assert_called_once()
                self.assertIn("mystery-new-model-99", mock_warn.call_args[0][0])
        finally:
            collector_mod.glob.glob = orig_glob

        cost_key = 'agent="claude",branch="main",model="mystery-new-model-99",phase="portal",repo="nuage-cluster",task="portal"'
        self.assertIn(cost_key, collector.state["counters"]["cost_usd"])
        self.assertEqual(collector.state["counters"]["cost_usd"][cost_key], 0.0)

        token_key = 'agent="claude",branch="main",model="mystery-new-model-99",phase="portal",repo="nuage-cluster",task="portal",type="input"'
        self.assertEqual(collector.state["counters"]["tokens"][token_key], 50_000)

        payload = collector.generate_prometheus_payload()
        self.assertIn(f"nuage_ai_agent_cost_usd_total{{{cost_key}}} 0.0", payload)

    def test_zero_token_synthetic_model_does_not_warn(self):
        # Claude Code の <synthetic> メッセージ等でトークンがすべて 0 の場合は未定義モデル警告を出さないこと
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-synthetic.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                "gitBranch": "main",
                "message": {
                    "id": "msg-syn-1",
                    "model": "<synthetic>",
                    "usage": {
                        "input_tokens": 0,
                        "output_tokens": 0,
                        "cache_read_input_tokens": 0,
                        "cache_creation_input_tokens": 0,
                    },
                },
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "claude" in p else []
        try:
            with mock.patch.object(collector, "warn", wraps=collector.warn) as mock_warn:
                collector.collect_claude()
                mock_warn.assert_not_called()
        finally:
            collector_mod.glob.glob = orig_glob

    def test_cost_incremental_consistency_and_rate_change_protection(self):
        # 1. 差分集計の整合性（1回目＋2回目の増分集計結果が正確であること）
        # 2. 価格改定時に過去の確定実績が遡及変更されず、増分のみに新単価が適用されること
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-inc-cost.jsonl")

        rates_v1 = {
            "claude-sonnet-5-5": {
                "input": 3.00,
                "output": 15.00,
                "cache_read": 0.30,
                "cache_creation": 3.75,
            }
        }
        rates_v2 = {
            "claude-sonnet-5-5": {
                "input": 6.00,
                "output": 30.00,
                "cache_read": 0.60,
                "cache_creation": 7.50,
            }
        }

        # 1回目: 1,000,000 input ($3.00) + 100,000 output ($1.50) = $4.50
        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "user",
                "entrypoint": "sdk-cli",
                "message": {"content": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。"},
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                "gitBranch": "bot-wa-wa/inc-cost",
                "message": {
                    "id": "msg-inc-cost-1",
                    "model": "claude-sonnet-5-5",
                    "usage": {"input_tokens": 1_000_000, "output_tokens": 100_000},
                },
            }) + "\n")

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "claude" in p else []
        try:
            collector1 = MetricsCollector(
                state_file=self.state_file,
                vm_url="http://localhost:8427",
                dry_run=False,
                rates=rates_v1,
            )
            collector1.collect_claude()
            collector1._save_state()

            cost_key = 'agent="claude",branch="bot-wa-wa/inc-cost",model="claude-sonnet-5-5",phase="implement",repo="nuage-cluster",task="bot-wa-wa/inc-cost"'
            self.assertAlmostEqual(collector1.state["counters"]["cost_usd"][cost_key], 4.50, places=8)

            # 2回目追記: 500,000 input + 100,000 output
            with open(jsonl_path, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "type": "assistant",
                    "entrypoint": "sdk-cli",
                    "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                    "gitBranch": "bot-wa-wa/inc-cost",
                    "message": {
                        "id": "msg-inc-cost-2",
                        "model": "claude-sonnet-5-5",
                        "usage": {"input_tokens": 500_000, "output_tokens": 100_000},
                    },
                }) + "\n")

            # 単価改定 (rates_v2: 2倍) 後に差分収集:
            # 1回目の $4.50 は維持され、2回目増分 (0.5M * $6 + 0.1M * $30 = $3.00 + $3.00 = $6.00) のみが加算され合計 $10.50 になること
            collector2 = MetricsCollector(
                state_file=self.state_file,
                vm_url="http://localhost:8427",
                dry_run=False,
                rates=rates_v2,
            )
            collector2.collect_claude()
            collector2._save_state()

            self.assertAlmostEqual(collector2.state["counters"]["cost_usd"][cost_key], 10.50, places=8)
            token_in_key = f'{cost_key},type="input"'
            self.assertEqual(collector2.state["counters"]["tokens"][token_in_key], 1_500_000)
        finally:
            collector_mod.glob.glob = orig_glob

    def test_backfill_cost_from_existing_state_without_cost_key(self):
        # cost_usd キーを持たない既存の state ファイルから初期コストがバックフィルされ、task ラベルも整合すること
        legacy_state = {
            "version": CURRENT_STATE_VERSION,
            "claude_offsets": {},
            "agy_offsets": {},
            "last_orca_stats_timestamp": 0,
            "counters": {
                "tokens": {
                    'agent="claude",branch="main",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",type="input"': 100_000,
                    'agent="claude",branch="main",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",type="output"': 20_000,
                    'agent="claude",branch="main",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",type="thinking"': 5_000,
                },
                "sessions": {},
                "duration": {},
                "autopilot_runs": {},
            },
        }
        with open(self.state_file, "w", encoding="utf-8") as f:
            json.dump(legacy_state, f)

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
            rates={
                "claude-opus-5-5": {
                    "input": 15.00,
                    "output": 75.00,
                    "cache_read": 1.50,
                    "cache_creation": 18.75,
                }
            },
        )
        cost_key = 'agent="claude",branch="main",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="main"'
        # 100,000 * 15 / 1M ($1.50) + 20,000 * 75 / 1M ($1.50) = $3.00 (thinking は除外)
        self.assertAlmostEqual(collector.state["counters"]["cost_usd"][cost_key], 3.00, places=8)
        self.assertEqual(collector.state["counters"]["tokens"][f'{cost_key},type="input"'], 100_000)

    def test_autopilot_rates_env_override(self):
        custom_rates_path = os.path.join(self.test_dir, "custom-rates.yaml")
        with open(custom_rates_path, "w", encoding="utf-8") as f:
            f.write(
                "custom-model-x:\n"
                "  input: 10.0\n"
                "  output: 20.0\n"
            )

        with mock.patch.dict(os.environ, {"AUTOPILOT_RATES": custom_rates_path}):
            collector = MetricsCollector(
                state_file=self.state_file,
                vm_url="http://localhost:8427",
                dry_run=True,
            )
            self.assertEqual(collector.rates_file, custom_rates_path)
            self.assertAlmostEqual(
                collector.calculate_cost_usd("custom-model-x-high", input_tokens=100_000, output_tokens=50_000),
                2.0,
                places=8,
            )

        with mock.patch.object(collector_mod, "default_rates_file", wraps=collector_mod.default_rates_file) as mock_def:
            collector_explicit = MetricsCollector(
                state_file=self.state_file,
                vm_url="http://localhost:8427",
                dry_run=True,
                rates_file=custom_rates_path,
            )
            mock_def.assert_not_called()
            self.assertEqual(collector_explicit.rates_file, custom_rates_path)

    def test_normalize_autopilot_phase_and_terminal_status(self):
        # 各 status 表記からの phase 正規化検証
        self.assertEqual(normalize_autopilot_phase("implementing (agy)"), "implementing")
        self.assertEqual(normalize_autopilot_phase("implementing (claude)\n"), "implementing")
        self.assertEqual(normalize_autopilot_phase("waiting CI (round 1)"), "waiting_ci")
        self.assertEqual(normalize_autopilot_phase("waiting CI (round 2)"), "waiting_ci")
        self.assertEqual(normalize_autopilot_phase("reviewing (round 1: claude)"), "reviewing")
        self.assertEqual(normalize_autopilot_phase("reviewing (round 2: agy, copilot)"), "reviewing")
        self.assertEqual(normalize_autopilot_phase("fixing (round 2)"), "fixing")
        self.assertEqual(normalize_autopilot_phase("gating (round 1: claude)"), "gating")
        self.assertEqual(normalize_autopilot_phase("summarizing"), "summarizing")

        # 完了系および空の status の判定と phase 正規化結果の検証
        for terminal in (
            "done",
            "done\n",
            "failed: 実装担当が異常終了した",
            "needs-human: 修正ループが上限（3 回）に達した",
            "stopped: 人間が停止した",
            "",
            "\n",
            "-",
        ):
            self.assertTrue(is_terminal_autopilot_status(terminal), f"should be terminal: {terminal!r}")
            self.assertEqual(normalize_autopilot_phase(terminal), "unknown")

        for active in (
            "implementing (agy)",
            "waiting CI (round 1)",
            "reviewing (round 1: claude)",
            "fixing (round 2)",
            "gating (round 1: claude)",
            "summarizing",
        ):
            self.assertFalse(is_terminal_autopilot_status(active), f"should be active: {active!r}")

    def test_autopilot_active_running_output(self):
        # 1. PR 作成前の実装中タスク (nuage-cluster)
        ws1 = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "feature-active")
        auto1 = os.path.join(ws1, ".autopilot")
        os.makedirs(auto1, exist_ok=True)
        with open(os.path.join(auto1, "run.pid"), "w", encoding="utf-8") as f:
            f.write(f"{os.getpid()}\n")
        with open(os.path.join(auto1, "status"), "w", encoding="utf-8") as f:
            f.write("implementing (agy)\n")
        with open(os.path.join(auto1, "run.log"), "w", encoding="utf-8") as f:
            f.write(
                "[23:51:34] start impl=agy level=high reviewers=claude base=1cfde718 from=implement\n"
                "[23:51:35] == implementing (agy)\n"
                "直前 PR #63 (https://github.com/k-wa-wa/nuage-cluster/pull/63) に追従して実装する。\n"
            )
        with open(os.path.join(auto1, "brief.md"), "w", encoding="utf-8") as f:
            f.write("# 自走中ステータスの新設\n\n詳細...")
        git1 = os.path.join(ws1, ".git")
        os.makedirs(git1, exist_ok=True)
        with open(os.path.join(git1, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/feature-ai-agent-active-status\n")

        # 2. PR 作成済みの CI 待ちタスク (nuage-monitoring-stack)
        ws2 = os.path.join(self.test_dir, "workspaces", "nuage-monitoring-stack", "feature-dash")
        auto2 = os.path.join(ws2, ".autopilot")
        os.makedirs(auto2, exist_ok=True)
        with open(os.path.join(auto2, "run.pid"), "w", encoding="utf-8") as f:
            f.write(f"{os.getpid()}\n")
        with open(os.path.join(auto2, "status"), "w", encoding="utf-8") as f:
            f.write("waiting CI (round 1)\n")
        with open(os.path.join(auto2, "run.log"), "w", encoding="utf-8") as f:
            f.write(
                "[10:00:00] start impl=claude:claude-opus-5-5@high level=standard reviewers=agy base=abcdef12\n"
                "[10:05:00] PR #64\n"
            )
        with open(os.path.join(auto2, "brief.md"), "w", encoding="utf-8") as f:
            f.write("# ダッシュボード更新\n")
        git2 = os.path.join(ws2, ".git")
        os.makedirs(git2, exist_ok=True)
        with open(os.path.join(git2, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/feature-dash\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_exists = os.path.exists
        with (
            mock.patch.object(
                collector_mod.glob,
                "glob",
                side_effect=lambda p: [auto1, auto2] if "autopilot" in p else [],
            ),
            mock.patch.object(
                os.path,
                "exists",
                side_effect=lambda p: True if p == "/home/nixos/orca/workspaces" else orig_exists(p),
            ),
        ):
            collector.collect_autopilot_runs()

        expected_key1 = (
            'branch="bot-wa-wa/feature-ai-agent-active-status",impl="agy",level="high",'
            'phase="implementing",pr="unknown",repo="nuage-cluster",task="自走中ステータスの新設"'
        )
        expected_key2 = (
            'branch="bot-wa-wa/feature-dash",impl="claude",level="standard",'
            'phase="waiting_ci",pr="64",repo="nuage-monitoring-stack",task="ダッシュボード更新"'
        )
        self.assertEqual(collector.active_autopilots.get(expected_key1), 1)
        self.assertEqual(collector.active_autopilots.get(expected_key2), 1)
        self.assertEqual(len(collector.active_autopilots), 2)
        self.assertEqual(len(collector.state["counters"]["autopilot_runs"]), 0)

        payload = collector.generate_prometheus_payload()
        self.assertIn(
            "# HELP nuage_ai_agent_autopilot_active Whether an autopilot task is currently running (1 for running)",
            payload,
        )
        self.assertIn("# TYPE nuage_ai_agent_autopilot_active gauge", payload)
        self.assertIn(f"nuage_ai_agent_autopilot_active{{{expected_key1}}} 1", payload)
        self.assertIn(f"nuage_ai_agent_autopilot_active{{{expected_key2}}} 1", payload)

    def test_autopilot_active_not_emitted_when_dead_or_completed(self):
        # 1. status は未完了だが run.pid のプロセスが非生存
        auto_dead = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-dead", ".autopilot")
        os.makedirs(auto_dead, exist_ok=True)
        with open(os.path.join(auto_dead, "run.pid"), "w", encoding="utf-8") as f:
            f.write("999999\n")
        with open(os.path.join(auto_dead, "status"), "w", encoding="utf-8") as f:
            f.write("reviewing (round 1: claude)\n")
        with open(os.path.join(auto_dead, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] start impl=claude level=high\n")

        # 2. status は未完了だが run.pid ファイルが存在しない
        auto_nopid = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-nopid", ".autopilot")
        os.makedirs(auto_nopid, exist_ok=True)
        with open(os.path.join(auto_nopid, "status"), "w", encoding="utf-8") as f:
            f.write("fixing (round 2)\n")

        # 3. run.pid は生存しているが status が完了系 (done, needs-human, failed, stopped)
        terminal_dirs = []
        for idx, st in enumerate([
            "done",
            "needs-human: 修正ループが上限に達した",
            "failed: 実装担当が異常終了した",
            "stopped: 人間が停止した",
        ]):
            d = os.path.join(self.test_dir, "workspaces", "nuage-cluster", f"ws-term-{idx}", ".autopilot")
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "run.pid"), "w", encoding="utf-8") as f:
                f.write(f"{os.getpid()}\n")
            with open(os.path.join(d, "status"), "w", encoding="utf-8") as f:
                f.write(f"{st}\n")
            with open(os.path.join(d, "run.log"), "w", encoding="utf-8") as f:
                f.write("[10:00:00] start impl=agy level=high\n")
            terminal_dirs.append(d)

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        all_dirs = [auto_dead, auto_nopid] + terminal_dirs
        orig_exists = os.path.exists

        def mock_pid_running(pid: int) -> bool:
            return pid == os.getpid()

        with (
            mock.patch.object(
                collector_mod.glob,
                "glob",
                side_effect=lambda p: all_dirs if "autopilot" in p else [],
            ),
            mock.patch.object(
                os.path,
                "exists",
                side_effect=lambda p: True if p == "/home/nixos/orca/workspaces" else orig_exists(p),
            ),
            mock.patch.object(collector_mod, "is_pid_running", side_effect=mock_pid_running),
        ):
            collector.collect_autopilot_runs()

        # いずれのワークスペースも active としては出力されないこと
        self.assertEqual(collector.active_autopilots, {})
        payload = collector.generate_prometheus_payload()
        self.assertNotIn("nuage_ai_agent_autopilot_active", payload)

        # 完了カウンタ (done, needs-human, failed の 3 件) は従来通り集計されること
        runs = collector.state["counters"]["autopilot_runs"]
        self.assertEqual(sum(runs.values()), 3)

    def test_autopilot_active_disappears_after_task_completes(self):
        # 実行中から完了に遷移した際、active メトリクスが出力されなくなり、完了カウンタに加算されること
        ws = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-transition")
        auto_dir = os.path.join(ws, ".autopilot")
        os.makedirs(auto_dir, exist_ok=True)
        pid_file = os.path.join(auto_dir, "run.pid")
        status_file = os.path.join(auto_dir, "status")
        with open(pid_file, "w", encoding="utf-8") as f:
            f.write(f"{os.getpid()}\n")
        with open(status_file, "w", encoding="utf-8") as f:
            f.write("summarizing\n")
        with open(os.path.join(auto_dir, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] start impl=claude level=high\n[10:10:00] PR #70\n")
        with open(os.path.join(auto_dir, "brief.md"), "w", encoding="utf-8") as f:
            f.write("# 遷移テスト用タスク\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_exists = os.path.exists
        with (
            mock.patch.object(
                collector_mod.glob,
                "glob",
                side_effect=lambda p: [auto_dir] if "autopilot" in p else [],
            ),
            mock.patch.object(
                os.path,
                "exists",
                side_effect=lambda p: True if p == "/home/nixos/orca/workspaces" else orig_exists(p),
            ),
        ):
            # 1回目: summarizing で稼働中
            collector.collect_autopilot_runs()
            payload1 = collector.generate_prometheus_payload()
            self.assertIn("nuage_ai_agent_autopilot_active{", payload1)
            self.assertIn('phase="summarizing"', payload1)
            self.assertIn('pr="70"', payload1)
            self.assertNotIn("nuage_ai_agent_autopilot_runs_total", payload1)

            # 2回目: 完了して status=done, run.pid 削除
            os.remove(pid_file)
            with open(status_file, "w", encoding="utf-8") as f:
                f.write("done\n")

            collector.collect_autopilot_runs()
            payload2 = collector.generate_prometheus_payload()
            self.assertNotIn("nuage_ai_agent_autopilot_active", payload2)
            self.assertIn("nuage_ai_agent_autopilot_runs_total{", payload2)

    def test_autopilot_reused_workspace_pr_and_impl_compat(self):
        # ワークスペースを使い回した際、未作成の PR に前回の PR 番号が付かないこと（active / runs_total 両方）
        # およびモデル指定付き impl の runs_total 後方互換性を検証する
        ws = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "feature-reused")
        auto_dir = os.path.join(ws, ".autopilot")
        os.makedirs(auto_dir, exist_ok=True)
        git_dir = os.path.join(ws, ".git")
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/feature-second-task\n")

        pid_file = os.path.join(auto_dir, "run.pid")
        status_file = os.path.join(auto_dir, "status")
        run_log_file = os.path.join(auto_dir, "run.log")
        result_file = os.path.join(auto_dir, "result.md")

        with open(pid_file, "w", encoding="utf-8") as f:
            f.write(f"{os.getpid()}\n")
        with open(status_file, "w", encoding="utf-8") as f:
            f.write("implementing (claude)\n")
        with open(os.path.join(auto_dir, "brief.md"), "w", encoding="utf-8") as f:
            f.write("# 2回目のタスク\n")
        with open(run_log_file, "w", encoding="utf-8") as f:
            f.write(
                "[23:27:23] start impl=agy level=high reviewers=claude base=13e10339 from=implement\n"
                "- PR: https://github.com/k-wa-wa/nuage-cluster/pull/60\n"
                "[23:42:28] PR #60\n"
                "[00:29:32] == done\n"
                "[00:14:24] start impl=claude:claude-opus-5-5@high level=standard reviewers=agy base=1cfde718 from=implement\n"
                "[00:14:24] == implementing (claude)\n"
            )

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )

        orig_exists = os.path.exists
        with (
            mock.patch.object(
                collector_mod.glob,
                "glob",
                side_effect=lambda p: [auto_dir] if "autopilot" in p else [],
            ),
            mock.patch.object(
                os.path,
                "exists",
                side_effect=lambda p: True if p == "/home/nixos/orca/workspaces" else orig_exists(p),
            ),
        ):
            # 1. 稼働中 (PR 未作成): 前回の #60 ではなく pr="unknown" になり、impl="claude" になること
            collector.collect_autopilot_runs()
            expected_active_key = (
                'branch="bot-wa-wa/feature-second-task",impl="claude",level="standard",'
                'phase="implementing",pr="unknown",repo="nuage-cluster",task="2回目のタスク"'
            )
            self.assertEqual(collector.active_autopilots, {expected_active_key: 1})

            # 2. PR 未作成のまま failed で終了した場合: runs_total でも pr="none" になり、
            #    impl は既存仕様通り "claude-claude-opus-5-5-high" が維持されること
            os.remove(pid_file)
            with open(status_file, "w", encoding="utf-8") as f:
                f.write("failed: 実装担当が異常終了した\n")
            with open(result_file, "w", encoding="utf-8") as f:
                f.write("要約は書かれなかった。結果: failed: 実装担当が異常終了した\n詳細は .autopilot/run.log を読むこと。\n")

            collector.collect_autopilot_runs()
            self.assertEqual(collector.active_autopilots, {})
            runs = collector.state["counters"]["autopilot_runs"]
            expected_run_key = (
                'branch="bot-wa-wa/feature-second-task",impl="claude-claude-opus-5-5-high",level="standard",'
                'pr="none",repo="nuage-cluster",result="failed",task="2回目のタスク"'
            )
            self.assertEqual(runs, {expected_run_key: 1})



    def test_task_label_with_brief_portal_and_fallback(self):
        # 1. brief.md が存在するワークスペース (日本語タスク名 + エスケープ対象文字)
        ws_with_brief = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-brief")
        auto_dir = os.path.join(ws_with_brief, ".autopilot")
        os.makedirs(auto_dir, exist_ok=True)
        with open(os.path.join(auto_dir, "brief.md"), "w", encoding="utf-8") as f:
            f.write('# タスク別 "コスト" 集計と \\エスケープ\\ 対応\n\n詳細仕様...\n')
        git_dir = os.path.join(ws_with_brief, ".git")
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/task-label\n")

        # 2. brief.md が存在しないワークスペース (branch フォールバック)
        ws_no_brief = os.path.join(self.test_dir, "workspaces", "pechka", "ws-deleted")

        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-ws-brief")
        os.makedirs(project_dir, exist_ok=True)

        # (A) Claude 自律実行セッション (brief.md あり -> 日本語タスク名)
        claude_impl_jsonl = os.path.join(project_dir, "claude-impl.jsonl")
        with open(claude_impl_jsonl, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "queue-operation",
                "content": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。",
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": ws_with_brief,
                "gitBranch": "bot-wa-wa/task-label",
                "message": {
                    "id": "msg-brief-1",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 100_000, "output_tokens": 20_000},
                },
            }) + "\n")

        # (B) Claude 窓口セッション (同じ brief.md があるワークスペースでも phase=="portal" -> task="portal")
        claude_portal_jsonl = os.path.join(project_dir, "claude-portal.jsonl")
        with open(claude_portal_jsonl, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "cli",
                "cwd": ws_with_brief,
                "gitBranch": "bot-wa-wa/task-label",
                "message": {
                    "id": "msg-portal-1",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 50_000, "output_tokens": 10_000},
                },
            }) + "\n")

        # (C) Claude 自律実行セッション (brief.md なし -> branch にフォールバック)
        claude_fallback_jsonl = os.path.join(project_dir, "claude-fallback.jsonl")
        with open(claude_fallback_jsonl, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "queue-operation",
                "content": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。",
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": ws_no_brief,
                "gitBranch": "bot-wa-wa/deleted-ws-branch",
                "message": {
                    "id": "msg-fb-1",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 40_000, "output_tokens": 5_000},
                },
            }) + "\n")

        # (D) Antigravity 自律実行セッション (brief.md あり -> 日本語タスク名)
        brain_dir = os.path.join(self.test_dir, "brain", "conv-brief-agy", ".system_generated", "logs")
        os.makedirs(brain_dir, exist_ok=True)
        agy_transcript = os.path.join(brain_dir, "transcript.jsonl")
        with open(agy_transcript, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>あなたはコードレビュアーである。</USER_REQUEST><USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Gemini 3.8 Flash (High).</USER_SETTINGS_CHANGE>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 200_000,
                "output_tokens": 50_000,
                "content": f"ワークスペース {ws_with_brief} の変更をレビューした。",
            }) + "\n")

        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=False,
            rates_file=repo_rates_path,
        )

        orig_glob = collector_mod.glob.glob
        def mock_glob(p):
            if "claude" in p:
                return [claude_impl_jsonl, claude_portal_jsonl, claude_fallback_jsonl]
            if "antigravity" in p:
                return [agy_transcript]
            return []

        collector_mod.glob.glob = mock_glob
        try:
            collector.collect_claude()
            collector.collect_antigravity()
            collector._save_state()
        finally:
            collector_mod.glob.glob = orig_glob

        escaped_task = 'タスク別 \\"コスト\\" 集計と \\\\エスケープ\\\\ 対応'
        tokens = collector.state["counters"]["tokens"]
        costs = collector.state["counters"]["cost_usd"]

        # (A) brief.md あり (Claude implement)
        claude_impl_cost_key = f'agent="claude",branch="bot-wa-wa/task-label",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="{escaped_task}"'
        self.assertIn(claude_impl_cost_key, costs)
        self.assertAlmostEqual(costs[claude_impl_cost_key], 0.8, places=8)
        self.assertEqual(tokens[f'{claude_impl_cost_key},type="input"'], 100_000)

        # (B) phase == "portal" (Claude portal)
        claude_portal_cost_key = 'agent="claude",branch="bot-wa-wa/task-label",model="claude-opus-5-5",phase="portal",repo="nuage-cluster",task="portal"'
        self.assertIn(claude_portal_cost_key, costs)
        self.assertAlmostEqual(costs[claude_portal_cost_key], 0.4, places=8)
        self.assertEqual(tokens[f'{claude_portal_cost_key},type="input"'], 50_000)

        # (C) brief.md なし -> branch フォールバック
        claude_fb_cost_key = 'agent="claude",branch="bot-wa-wa/deleted-ws-branch",model="claude-opus-5-5",phase="implement",repo="pechka",task="bot-wa-wa/deleted-ws-branch"'
        self.assertIn(claude_fb_cost_key, costs)
        self.assertEqual(tokens[f'{claude_fb_cost_key},type="input"'], 40_000)

        # (D) brief.md あり (Antigravity review)
        agy_rev_cost_key = f'agent="agy",branch="bot-wa-wa/task-label",model="gemini-3-8-flash-high",phase="review",repo="nuage-cluster",task="{escaped_task}"'
        self.assertIn(agy_rev_cost_key, costs)
        self.assertAlmostEqual(costs[agy_rev_cost_key], 0.3375, places=8)
        self.assertEqual(tokens[f'{agy_rev_cost_key},type="input"'], 200_000)

        # Prometheus ペイロード形式にエスケープされた task="..." が出力されること
        payload = collector.generate_prometheus_payload()
        self.assertIn(f'nuage_ai_agent_tokens_total{{{claude_impl_cost_key},type="input"}} 100000', payload)
        self.assertIn(f"nuage_ai_agent_cost_usd_total{{{claude_impl_cost_key}}} 0.8", payload)
        self.assertIn(f"nuage_ai_agent_cost_usd_total{{{claude_portal_cost_key}}} 0.4", payload)
        self.assertIn(f"nuage_ai_agent_cost_usd_total{{{agy_rev_cost_key}}} 0.3375", payload)

        # ワークスペース削除後の差分収集でも、保存済み brief_task により同じ task ラベルが維持されること
        shutil.rmtree(ws_with_brief)
        with open(claude_impl_jsonl, "a", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": ws_with_brief,
                "gitBranch": "bot-wa-wa/task-label",
                "message": {
                    "id": "msg-brief-2",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 50_000, "output_tokens": 10_000},
                },
            }) + "\n")

        collector2 = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
            rates_file=repo_rates_path,
        )
        collector_mod.glob.glob = mock_glob
        try:
            collector2.collect_claude()
        finally:
            collector_mod.glob.glob = orig_glob

        self.assertEqual(
            collector2.state["counters"]["tokens"][f'{claude_impl_cost_key},type="input"'],
            150_000,
        )
        self.assertAlmostEqual(
            collector2.state["counters"]["cost_usd"][claude_impl_cost_key],
            1.2,
            places=8,
        )

    def test_reused_workspace_branch_mismatch_does_not_use_current_brief(self):
        # 使い回したワークスペースで、過去の別ブランチのセッションが現在の brief.md のタスク名で記録されないこと
        ws_reused = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "feature-ai-agent-ledger")
        auto_dir = os.path.join(ws_reused, ".autopilot")
        git_dir = os.path.join(ws_reused, ".git")
        os.makedirs(auto_dir, exist_ok=True)
        os.makedirs(git_dir, exist_ok=True)

        # まず旧ブランチ (feature/ai-agent-ledger) で稼働していた時点の状態を作る
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/feature/ai-agent-ledger\n")
        with open(os.path.join(auto_dir, "brief.md"), "w", encoding="utf-8") as f:
            f.write("# 旧タスク: メインフレーム勘定系の基盤構築\n")

        project_dir = os.path.join(
            self.test_dir,
            "projects",
            "-home-nixos-orca-workspaces-nuage-cluster-feature-ai-agent-ledger",
        )
        os.makedirs(project_dir, exist_ok=True)

        # セッション1: 旧ブランチ当時に一度収集されたセッション (prev_meta に旧 brief_task が保存されるケース)
        old_saved_jsonl = os.path.join(project_dir, "old-saved.jsonl")
        with open(old_saved_jsonl, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "queue-operation",
                "content": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。",
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": ws_reused,
                "gitBranch": "feature/ai-agent-ledger",
                "message": {
                    "id": "msg-old-saved-1",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 100_000, "output_tokens": 20_000},
                },
            }) + "\n")

        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        orig_glob = collector_mod.glob.glob
        collector1 = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=False,
            rates_file=repo_rates_path,
        )
        collector_mod.glob.glob = lambda p: [old_saved_jsonl] if "claude" in p else []
        try:
            collector1.collect_claude()
            collector1._save_state()
        finally:
            collector_mod.glob.glob = orig_glob

        old_saved_cost_key = 'agent="claude",branch="feature/ai-agent-ledger",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="旧タスク: メインフレーム勘定系の基盤構築"'
        self.assertIn(old_saved_cost_key, collector1.state["counters"]["cost_usd"])
        self.assertAlmostEqual(collector1.state["counters"]["cost_usd"][old_saved_cost_key], 0.8, places=8)

        # ワークスペースが新しいブランチ (bot-wa-wa/feature-ai-agent-task-metadata) に使い回され、brief.md が書き換わる
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/feature-ai-agent-task-metadata\n")
        with open(os.path.join(auto_dir, "brief.md"), "w", encoding="utf-8") as f:
            f.write("# 新タスク: 日本語タスク名 (task) ラベル連携\n")

        # セッション1 (old_saved_jsonl) に追記が発生した場合でも、新しい brief で上書きされず旧タスク名が維持されること
        with open(old_saved_jsonl, "a", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": ws_reused,
                "gitBranch": "feature/ai-agent-ledger",
                "message": {
                    "id": "msg-old-saved-2",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 50_000, "output_tokens": 10_000},
                },
            }) + "\n")

        # セッション2: 状態リセット後や新規再集計として offset=0 から読まれる過去ブランチのセッション
        # (現在のワークスペースのブランチと gitBranch が不一致 -> 現在の brief を使わず branch にフォールバック)
        old_rescan_jsonl = os.path.join(project_dir, "old-rescan.jsonl")
        with open(old_rescan_jsonl, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "queue-operation",
                "content": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。",
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": ws_reused,
                "gitBranch": "feature/ai-agent-ledger",
                "message": {
                    "id": "msg-old-rescan-1",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 200_000, "output_tokens": 40_000},
                },
            }) + "\n")

        # セッション3: 現在のブランチと一致するセッション (-> 現在の brief の新タスク名が使われる)
        current_jsonl = os.path.join(project_dir, "current.jsonl")
        with open(current_jsonl, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "queue-operation",
                "content": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。",
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": ws_reused,
                "gitBranch": "bot-wa-wa/feature-ai-agent-task-metadata",
                "message": {
                    "id": "msg-current-1",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 100_000, "output_tokens": 20_000},
                },
            }) + "\n")

        # セッション4: Antigravity で記録上の branch がワークスペースの現在ブランチと食い違うケース
        brain_dir = os.path.join(self.test_dir, "brain", "conv-old-agy", ".system_generated", "logs")
        os.makedirs(brain_dir, exist_ok=True)
        old_agy_transcript = os.path.join(brain_dir, "transcript.jsonl")
        with open(old_agy_transcript, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>あなたはコードレビュアーである。</USER_REQUEST><USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Gemini 3.8 Flash (High).</USER_SETTINGS_CHANGE>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 100_000,
                "output_tokens": 25_000,
                "content": f"ワークスペース {ws_reused} を確認した。",
            }) + "\n")

        collector2 = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
            rates_file=repo_rates_path,
        )
        collector2.state["cid_to_meta"]["conv-old-agy"] = {
            "repo": "nuage-cluster",
            "branch": "feature/ai-agent-ledger",
            "worktree": ws_reused,
        }

        def mock_glob2(p):
            if "claude" in p:
                return [old_saved_jsonl, old_rescan_jsonl, current_jsonl]
            if "antigravity" in p:
                return [old_agy_transcript]
            return []

        collector_mod.glob.glob = mock_glob2
        try:
            collector2.collect_claude()
            collector2.collect_antigravity()
        finally:
            collector_mod.glob.glob = orig_glob

        costs2 = collector2.state["counters"]["cost_usd"]
        tokens2 = collector2.state["counters"]["tokens"]

        # 1. old_saved_jsonl の追記分は「旧タスク」のまま加算されること ($0.8 + $0.4 = $1.2)
        self.assertAlmostEqual(costs2[old_saved_cost_key], 1.2, places=8)
        self.assertEqual(tokens2[f'{old_saved_cost_key},type="input"'], 150_000)

        # 2. old_rescan_jsonl は現在の brief とブランチが不一致のため branch ("feature/ai-agent-ledger") にフォールバックされること
        old_rescan_cost_key = 'agent="claude",branch="feature/ai-agent-ledger",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="feature/ai-agent-ledger"'
        self.assertIn(old_rescan_cost_key, costs2)
        self.assertAlmostEqual(costs2[old_rescan_cost_key], 1.6, places=8)
        self.assertEqual(tokens2[f'{old_rescan_cost_key},type="input"'], 200_000)

        # 誤って旧ブランチの記録に「新タスク」が付与されていないこと
        wrong_cost_key = 'agent="claude",branch="feature/ai-agent-ledger",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="新タスク: 日本語タスク名 (task) ラベル連携"'
        self.assertNotIn(wrong_cost_key, costs2)

        # 3. current_jsonl はブランチが一致するため「新タスク」が付与されること
        current_cost_key = 'agent="claude",branch="bot-wa-wa/feature-ai-agent-task-metadata",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",task="新タスク: 日本語タスク名 (task) ラベル連携"'
        self.assertIn(current_cost_key, costs2)
        self.assertAlmostEqual(costs2[current_cost_key], 0.8, places=8)

        # 4. Antigravity の不一致ブランチも branch にフォールバックされ「新タスク」が付与されないこと
        old_agy_cost_key = 'agent="agy",branch="feature/ai-agent-ledger",model="gemini-3-8-flash-high",phase="review",repo="nuage-cluster",task="feature/ai-agent-ledger"'
        self.assertIn(old_agy_cost_key, costs2)
        self.assertAlmostEqual(costs2[old_agy_cost_key], 0.16875, places=8)

    def test_codex_collection_cost_dedup_and_phases(self):
        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        ws_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-codex")
        auto_dir = os.path.join(ws_dir, ".autopilot")
        git_dir = os.path.join(ws_dir, ".git")
        os.makedirs(auto_dir, exist_ok=True)
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/feat/codex-metrics\n")
        with open(os.path.join(auto_dir, "brief.md"), "w", encoding="utf-8") as f:
            f.write("# Codex メトリクス収集対応\n\n詳細\n")

        codex_dir = os.path.join(self.test_dir, "codex", "sessions", "2026", "11", "19")
        os.makedirs(codex_dir, exist_ok=True)
        jsonl_path = os.path.join(codex_dir, "rollout-exec.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "session_meta",
                "payload": {
                    "session_id": "sess-codex-1",
                    "cwd": ws_dir,
                    "source": "exec",
                    "originator": "codex_exec",
                    "git": {"branch": "feat/codex-metrics"},
                },
            }) + "\n")
            # AGENTS.md ラッパーはフェーズ誤判定を起こさないこと
            f.write(json.dumps({
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": "# AGENTS.md instructions\n\nあなたはコードレビュアーではない"}],
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "event_msg",
                "payload": {
                    "type": "thread_settings_applied",
                    "thread_settings": {"model": "gpt-6-astra"},
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。"}],
                },
            }) + "\n")
            # input_tokens=500,000, cached=400,000 -> non-cached input=100,000 ($1.00)
            # output=20,000 ($1.00), cache_read=400,000 ($0.40) -> 合計 $2.40
            usage_rec = {
                "type": "token_usage_record",
                "payload": {
                    "response_id": "resp-dup-1",
                    "usage": {
                        "input_tokens": 500_000,
                        "cached_input_tokens": 400_000,
                        "cache_write_input_tokens": 0,
                        "output_tokens": 20_000,
                        "reasoning_output_tokens": 5_000,
                        "total_tokens": 520_000,
                    },
                },
            }
            f.write(json.dumps(usage_rec) + "\n")
            # 同一 response_id の重複レコードは無視されること
            f.write(json.dumps(usage_rec) + "\n")
            # 同一セッション内で codex exec resume により fix フェーズへ遷移しモデルも変更
            f.write(json.dumps({
                "type": "event_msg",
                "payload": {
                    "type": "thread_settings_applied",
                    "thread_settings": {"model": "gpt-6.1-sol"},
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": "次のファイルを読み、直すべきものを直す。\n- レビュー結果: .autopilot/review-1-claude.md"}],
                },
            }) + "\n")
            # gpt-6.1-sol: non-cached input=100,000 ($0.20) + output=50,000 ($0.50) + cache_read=200,000 ($0.02) = $0.72
            f.write(json.dumps({
                "type": "token_usage_record",
                "payload": {
                    "response_id": "resp-fix-1",
                    "usage": {
                        "input_tokens": 300_000,
                        "cached_input_tokens": 200_000,
                        "cache_write_input_tokens": 0,
                        "output_tokens": 50_000,
                        "reasoning_output_tokens": 10_000,
                        "total_tokens": 350_000,
                    },
                },
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=False,
            rates_file=repo_rates_path,
        )

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "codex" in p else []
        try:
            collector.collect_codex()
            collector._save_state()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector.state["counters"]["tokens"]
        costs = collector.state["counters"]["cost_usd"]
        sessions = collector.state["counters"]["sessions"]

        impl_base = 'agent="codex",branch="feat/codex-metrics",model="gpt-6-astra",phase="implement",repo="nuage-cluster",task="Codex メトリクス収集対応"'
        self.assertEqual(tokens[f'{impl_base},type="input"'], 100_000)
        self.assertEqual(tokens[f'{impl_base},type="output"'], 20_000)
        self.assertEqual(tokens[f'{impl_base},type="cache_read"'], 400_000)
        self.assertEqual(tokens[f'{impl_base},type="thinking"'], 5_000)
        self.assertAlmostEqual(costs[impl_base], 2.40, places=8)

        fix_base = 'agent="codex",branch="feat/codex-metrics",model="gpt-6-1-sol",phase="fix",repo="nuage-cluster",task="Codex メトリクス収集対応"'
        self.assertEqual(tokens[f'{fix_base},type="input"'], 100_000)
        self.assertEqual(tokens[f'{fix_base},type="output"'], 50_000)
        self.assertEqual(tokens[f'{fix_base},type="cache_read"'], 200_000)
        self.assertEqual(tokens[f'{fix_base},type="thinking"'], 10_000)
        self.assertAlmostEqual(costs[fix_base], 0.72, places=8)

        self.assertEqual(
            sessions['agent="codex",branch="feat/codex-metrics",phase="implement",repo="nuage-cluster"'],
            1,
        )
        self.assertEqual(
            sessions['agent="codex",branch="feat/codex-metrics",phase="fix",repo="nuage-cluster"'],
            1,
        )

        # 差分追記: 重複 response_id は無視され、新規 response_id と不完全行を正しく扱うこと
        with open(jsonl_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "token_usage_record",
                "payload": {
                    "response_id": "resp-fix-1",
                    "usage": {"input_tokens": 999_999, "cached_input_tokens": 0, "output_tokens": 999_999},
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "token_usage_record",
                "payload": {
                    "response_id": "resp-fix-2",
                    "usage": {
                        "input_tokens": 150_000,
                        "cached_input_tokens": 100_000,
                        "cache_write_input_tokens": 0,
                        "output_tokens": 10_000,
                        "reasoning_output_tokens": 0,
                        "total_tokens": 160_000,
                    },
                },
            }) + "\n")
            # 改行なしの不完全行
            f.write('{"type": "token_usage_record", "payload": {"response_id": "resp-partial"')

        collector2 = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=False,
            rates_file=repo_rates_path,
        )
        collector_mod.glob.glob = lambda p: [jsonl_path] if "codex" in p else []
        try:
            collector2.collect_codex()
            collector2._save_state()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens2 = collector2.state["counters"]["tokens"]
        costs2 = collector2.state["counters"]["cost_usd"]
        self.assertEqual(tokens2[f'{fix_base},type="input"'], 150_000)
        self.assertEqual(tokens2[f'{fix_base},type="output"'], 60_000)
        self.assertEqual(tokens2[f'{fix_base},type="cache_read"'], 300_000)
        # +50,000 input ($0.10) + 10,000 output ($0.10) + 100,000 cache_read ($0.01) = +$0.21 -> $0.93
        self.assertAlmostEqual(costs2[fix_base], 0.93, places=8)

        # 不完全行に改行を補完して3回目の収集で加算されること
        with open(jsonl_path, "a", encoding="utf-8") as f:
            f.write(', "usage": {"input_tokens": 10000, "cached_input_tokens": 0, "cache_write_input_tokens": 5000, "output_tokens": 2000}}}\n')

        collector3 = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
            rates_file=repo_rates_path,
        )
        collector_mod.glob.glob = lambda p: [jsonl_path] if "codex" in p else []
        try:
            collector3.collect_codex()
        finally:
            collector_mod.glob.glob = orig_glob

        self.assertEqual(collector3.state["counters"]["tokens"][f'{fix_base},type="input"'], 160_000)
        self.assertEqual(collector3.state["counters"]["tokens"][f'{fix_base},type="cache_creation"'], 5_000)
        self.assertEqual(collector3.state["counters"]["tokens"][f'{fix_base},type="output"'], 62_000)

    def test_codex_portal_unknown_runlog_and_error_rollback(self):
        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        ws_dir = os.path.join(self.test_dir, "workspaces", "nuage-monitoring-stack", "ws-codex-portal")
        auto_dir = os.path.join(ws_dir, ".autopilot")
        os.makedirs(auto_dir, exist_ok=True)
        with open(os.path.join(auto_dir, "brief.md"), "w", encoding="utf-8") as f:
            f.write("# ポータルと混同しないタスク\n")
        with open(os.path.join(auto_dir, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] == reviewing (round 1: codex)\n")

        codex_dir = os.path.join(self.test_dir, "codex", "sessions", "2026", "11", "19")
        os.makedirs(codex_dir, exist_ok=True)

        # 1. portal セッション (source=cli): レビュー文言や run.log があっても phase="portal", task="portal" 固定
        portal_jsonl = os.path.join(codex_dir, "rollout-portal.jsonl")
        with open(portal_jsonl, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "session_meta",
                "payload": {
                    "cwd": ws_dir,
                    "source": "cli",
                    "originator": "codex-tui",
                    "git": {"branch": "bot-wa-wa/portal-branch"},
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "event_msg",
                "payload": {
                    "type": "thread_settings_applied",
                    "thread_settings": {"model": "gpt-6.1-terra"},
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": "あなたはコードレビュアーである。レビューする。"}],
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "token_usage_record",
                "payload": {
                    "response_id": "resp-portal-1",
                    "usage": {
                        "input_tokens": 120_000,
                        "cached_input_tokens": 20_000,
                        "output_tokens": 10_000,
                    },
                },
            }) + "\n")

        # 2. exec セッションだが定型外プロンプト + run.log なし (/tmp smoke test) -> repo="tmp", phase="unknown"
        smoke_jsonl = os.path.join(codex_dir, "rollout-smoke.jsonl")
        with open(smoke_jsonl, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "session_meta",
                "payload": {
                    "cwd": "/tmp/autopilot-codex-smoke-xyz",
                    "source": "exec",
                    "originator": "codex_exec",
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "event_msg",
                "payload": {
                    "type": "thread_settings_applied",
                    "thread_settings": {"model": "gpt-6-luna"},
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": "Reply with exactly OK."}],
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "token_usage_record",
                "payload": {
                    "response_id": "resp-smoke-1",
                    "usage": {
                        "input_tokens": 200_000,
                        "cached_input_tokens": 100_000,
                        "output_tokens": 20_000,
                    },
                },
            }) + "\n")

        # 3. exec セッション + 定型外プロンプト + run.log あり -> run.log のフェーズ (review) を引き継ぐ
        runlog_jsonl = os.path.join(codex_dir, "rollout-runlog.jsonl")
        with open(runlog_jsonl, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "session_meta",
                "payload": {
                    "cwd": ws_dir,
                    "source": "exec",
                    "originator": "codex_exec",
                    "git": {"branch": "feat/runlog-fb"},
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "event_msg",
                "payload": {
                    "type": "thread_settings_applied",
                    "thread_settings": {"model": "gpt-6-luna"},
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "token_usage_record",
                "payload": {
                    "response_id": "resp-runlog-1",
                    "usage": {"input_tokens": 100_000, "cached_input_tokens": 0, "output_tokens": 10_000},
                },
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
            rates_file=repo_rates_path,
        )
        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [portal_jsonl, smoke_jsonl, runlog_jsonl] if "codex" in p else []
        try:
            collector.collect_codex()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector.state["counters"]["tokens"]
        costs = collector.state["counters"]["cost_usd"]

        portal_base = 'agent="codex",branch="bot-wa-wa/portal-branch",model="gpt-6-1-terra",phase="portal",repo="nuage-monitoring-stack",task="portal"'
        self.assertEqual(tokens[f'{portal_base},type="input"'], 100_000)
        # gpt-6.1-terra: 100k*$1 + 10k*$5 + 20k*$0.05 = $0.10 + $0.05 + $0.001 = $0.151
        self.assertAlmostEqual(costs[portal_base], 0.151, places=8)

        smoke_base = 'agent="codex",branch="unknown",model="gpt-6-luna",phase="unknown",repo="tmp",task="unknown"'
        self.assertEqual(tokens[f'{smoke_base},type="input"'], 100_000)
        # gpt-6-luna: 100k*$0.10 + 20k*$0.50 + 100k*$0.01 = $0.01 + $0.01 + $0.001 = $0.021
        self.assertAlmostEqual(costs[smoke_base], 0.021, places=8)

        runlog_base = 'agent="codex",branch="feat/runlog-fb",model="gpt-6-luna",phase="review",repo="nuage-monitoring-stack",task="feat/runlog-fb"'
        self.assertEqual(tokens[f'{runlog_base},type="input"'], 100_000)

        # 4. エラー発生時はファイル単位でロールバックされ、オフセットもカウンタも更新されないこと
        err_jsonl = os.path.join(codex_dir, "rollout-err.jsonl")
        with open(err_jsonl, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "session_meta",
                "payload": {"cwd": ws_dir, "source": "exec"},
            }) + "\n")
            f.write(json.dumps({
                "type": "token_usage_record",
                "payload": {
                    "response_id": "resp-ok-before-err",
                    "usage": {"input_tokens": 500, "cached_input_tokens": 0, "output_tokens": 50},
                },
            }) + "\n")
            f.write('{"type": "token_usage_record", "payload": {"response_id": "resp-bad", "usage": {"input_tokens": "NOT_INT"}}}\n')

        collector_err = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
            rates_file=repo_rates_path,
        )
        collector_mod.glob.glob = lambda p: [err_jsonl] if "codex" in p else []
        try:
            collector_err.collect_codex()
        finally:
            collector_mod.glob.glob = orig_glob

        self.assertTrue(collector_err.has_errors)
        self.assertEqual(len(collector_err.state["counters"]["tokens"]), 0)
        self.assertEqual(len(collector_err.state["counters"]["cost_usd"]), 0)
        self.assertNotIn(err_jsonl, collector_err.state["codex_offsets"])

    def test_codex_sessions_consistent_across_incremental_and_batch(self):
        # 逐次（毎分）収集と一括収集で nuage_ai_agent_sessions_total のフェーズ別件数が一致すること
        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        ws_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-codex-sess")
        os.makedirs(ws_dir, exist_ok=True)
        codex_dir = os.path.join(self.test_dir, "codex", "sessions", "2026", "11", "19")
        os.makedirs(codex_dir, exist_ok=True)
        jsonl_path = os.path.join(codex_dir, "rollout-resume.jsonl")

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "codex" in p else []
        try:
            # 1. session_meta と AGENTS.md だけが書き出された瞬間 -> phase="unknown" を誤計上しないこと
            with open(jsonl_path, "w", encoding="utf-8") as f:
                f.write(json.dumps({
                    "type": "session_meta",
                    "payload": {
                        "cwd": ws_dir,
                        "source": "exec",
                        "originator": "codex_exec",
                        "git": {"branch": "feat/resume-consistency"},
                    },
                }) + "\n")
                f.write(json.dumps({
                    "type": "response_item",
                    "payload": {
                        "type": "message",
                        "role": "user",
                        "content": [{"type": "input_text", "text": "# AGENTS.md instructions\n..."}],
                    },
                }) + "\n")

            c1 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c1.collect_codex()
            c1._save_state()
            self.assertEqual(c1.state["counters"]["sessions"], {})

            # 2. implement ターン実行 -> implement=1 が計上されること
            with open(jsonl_path, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "type": "event_msg",
                    "payload": {"type": "thread_settings_applied", "thread_settings": {"model": "gpt-6-astra"}},
                }) + "\n")
                f.write(json.dumps({
                    "type": "response_item",
                    "payload": {
                        "type": "message",
                        "role": "user",
                        "content": [{"type": "input_text", "text": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。"}],
                    },
                }) + "\n")
                f.write(json.dumps({
                    "type": "token_usage_record",
                    "payload": {
                        "response_id": "resp-r1",
                        "usage": {"input_tokens": 1000, "cached_input_tokens": 0, "output_tokens": 100},
                    },
                }) + "\n")

            c2 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c2.collect_codex()
            c2._save_state()
            self.assertEqual(
                c2.state["counters"]["sessions"],
                {'agent="codex",branch="feat/resume-consistency",phase="implement",repo="nuage-cluster"': 1},
            )

            # 3. 同一ターンのトークン追記のみ -> セッション数は増えないこと
            with open(jsonl_path, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "type": "token_usage_record",
                    "payload": {
                        "response_id": "resp-r2",
                        "usage": {"input_tokens": 2000, "cached_input_tokens": 1000, "output_tokens": 200},
                    },
                }) + "\n")

            c3 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c3.collect_codex()
            c3._save_state()
            self.assertEqual(
                c3.state["counters"]["sessions"],
                {'agent="codex",branch="feat/resume-consistency",phase="implement",repo="nuage-cluster"': 1},
            )

            # 4. codex exec resume で fix を 2 回実行 -> fix=2 が加算されること
            for idx in range(2):
                with open(jsonl_path, "a", encoding="utf-8") as f:
                    f.write(json.dumps({
                        "type": "response_item",
                        "payload": {
                            "type": "message",
                            "role": "user",
                            "content": [{"type": "input_text", "text": f"次のファイルを読み、直すべきものを直す。\n- レビュー結果: .autopilot/review-{idx + 1}-claude.md"}],
                        },
                    }) + "\n")
                    f.write(json.dumps({
                        "type": "token_usage_record",
                        "payload": {
                            "response_id": f"resp-fix-{idx}",
                            "usage": {"input_tokens": 1000, "cached_input_tokens": 0, "output_tokens": 50},
                        },
                    }) + "\n")

            c4 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c4.collect_codex()

            expected_sessions = {
                'agent="codex",branch="feat/resume-consistency",phase="implement",repo="nuage-cluster"': 1,
                'agent="codex",branch="feat/resume-consistency",phase="fix",repo="nuage-cluster"': 2,
            }
            self.assertEqual(c4.state["counters"]["sessions"], expected_sessions)

            # 5. 一括収集（新しい state ファイルから最初から読み直し）でも完全に一致すること
            batch_state = os.path.join(self.test_dir, "batch-state.json")
            c_batch = MetricsCollector(
                state_file=batch_state, vm_url="http://localhost:8427", dry_run=True, rates_file=repo_rates_path
            )
            c_batch.collect_codex()
            self.assertEqual(c_batch.state["counters"]["sessions"], expected_sessions)
        finally:
            collector_mod.glob.glob = orig_glob

    def test_gate_phase_parallel_and_delayed_collection_across_agents(self):
        # Claude・Codex・Antigravity の並列 gate および run.log が後続フェーズへ進んだ後の遅延収集で、
        # 各セッションが指示文優先で phase="gate"（セッション数も各 1 件ずつ）として計上されること
        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        ws_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-gate-parallel")
        auto_dir = os.path.join(ws_dir, ".autopilot")
        git_dir = os.path.join(ws_dir, ".git")
        os.makedirs(auto_dir, exist_ok=True)
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/gate-parallel\n")
        with open(os.path.join(auto_dir, "brief.md"), "w", encoding="utf-8") as f:
            f.write("# 並列ゲート計測テスト\n")
        # 収集時点ではすでに run.log が後続の summarizing / fixing に進んでいる状態を模擬
        with open(os.path.join(auto_dir, "run.log"), "w", encoding="utf-8") as f:
            f.write(
                "[10:00:00] start impl=agy level=high reviewers=claude\n"
                "[10:05:00] == gating (round 1)\n"
                "[10:10:00] == fixing (round 1)\n"
                "[10:15:00] == summarizing\n"
            )

        gate_prompt = (
            "あなたはリポジトリのゲート検証担当である。ファイルは一切変更しない。\n"
            "ゲートの手順書に従ってコマンドを実際に実行して確かめる。"
        )

        # 1. Claude 並列 gate 2 セッション (queue-operation と user 文字列 + 後続 tool_result で上書きされない)
        claude_dir = os.path.join(
            self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-ws-gate-parallel"
        )
        os.makedirs(claude_dir, exist_ok=True)
        claude_gate_1 = os.path.join(claude_dir, "gate-1.jsonl")
        with open(claude_gate_1, "w", encoding="utf-8") as f:
            f.write(json.dumps({"type": "queue-operation", "content": gate_prompt}) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": ws_dir,
                "gitBranch": "bot-wa-wa/gate-parallel",
                "message": {
                    "id": "msg-cl-gate-1",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 100_000, "output_tokens": 20_000},
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "user",
                "entrypoint": "sdk-cli",
                "message": {"content": [{"type": "tool_result", "content": "あなたはコードレビュアーである。"}]},
            }) + "\n")

        claude_gate_2 = os.path.join(claude_dir, "gate-2.jsonl")
        with open(claude_gate_2, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "user",
                "entrypoint": "sdk-cli",
                "message": {"content": gate_prompt},
            }) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": ws_dir,
                "gitBranch": "bot-wa-wa/gate-parallel",
                "message": {
                    "id": "msg-cl-gate-2",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 50_000, "output_tokens": 10_000},
                },
            }) + "\n")

        # 2. Codex 並列 gate 2 セッション (AGENTS.md ラッパー付き)
        codex_dir = os.path.join(self.test_dir, "codex", "sessions", "2026", "11", "19")
        os.makedirs(codex_dir, exist_ok=True)
        codex_gate_files = []
        for idx in range(2):
            p = os.path.join(codex_dir, f"rollout-gate-{idx}.jsonl")
            with open(p, "w", encoding="utf-8") as f:
                f.write(json.dumps({
                    "type": "session_meta",
                    "payload": {
                        "cwd": ws_dir,
                        "source": "exec",
                        "originator": "codex_exec",
                        "git": {"branch": "bot-wa-wa/gate-parallel"},
                    },
                }) + "\n")
                f.write(json.dumps({
                    "type": "event_msg",
                    "payload": {"type": "thread_settings_applied", "thread_settings": {"model": "gpt-6-astra"}},
                }) + "\n")
                f.write(json.dumps({
                    "type": "response_item",
                    "payload": {
                        "type": "message",
                        "role": "user",
                        "content": [{"type": "input_text", "text": "# AGENTS.md instructions\nゲート結果について"}],
                    },
                }) + "\n")
                f.write(json.dumps({
                    "type": "response_item",
                    "payload": {
                        "type": "message",
                        "role": "user",
                        "content": [{"type": "input_text", "text": gate_prompt}],
                    },
                }) + "\n")
                f.write(json.dumps({
                    "type": "token_usage_record",
                    "payload": {
                        "response_id": f"resp-cx-gate-{idx}",
                        "usage": {"input_tokens": 100_000, "cached_input_tokens": 0, "output_tokens": 10_000},
                    },
                }) + "\n")
            codex_gate_files.append(p)

        # 3. Antigravity 並列 gate 2 セッション (step_index > 0 / GENERIC で別フェーズ文言が出ても phase="gate" を維持)
        agy_gate_files = []
        for idx in range(2):
            b_dir = os.path.join(self.test_dir, "brain", f"conv-agy-gate-{idx}", ".system_generated", "logs")
            os.makedirs(b_dir, exist_ok=True)
            tp = os.path.join(b_dir, "transcript.jsonl")
            with open(tp, "w", encoding="utf-8") as f:
                f.write(json.dumps({
                    "step_index": 0,
                    "source": "USER_EXPLICIT",
                    "type": "USER_INPUT",
                    "content": (
                        f"<USER_REQUEST>{gate_prompt}</USER_REQUEST>"
                        "<USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Gemini 4 Hydrogen (High).</USER_SETTINGS_CHANGE>"
                    ),
                }) + "\n")
                f.write(json.dumps({
                    "step_index": 1,
                    "source": "MODEL",
                    "type": "PLANNER_RESPONSE",
                    "input_tokens": 200_000,
                    "output_tokens": 40_000,
                    "content": f"ワークスペース {ws_dir} でゲート検証を実行した。",
                }) + "\n")
                f.write(json.dumps({
                    "step_index": 2,
                    "source": "USER_EXPLICIT",
                    "type": "GENERIC",
                    "content": "あなたはコードレビュアーである。人間向けの要約を .autopilot/result.md に書く。",
                }) + "\n")
            agy_gate_files.append(tp)

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
            rates_file=repo_rates_path,
        )
        for idx in range(2):
            collector.state["cid_to_meta"][f"conv-agy-gate-{idx}"] = {
                "repo": "nuage-cluster",
                "branch": "bot-wa-wa/gate-parallel",
                "worktree": ws_dir,
            }

        orig_glob = collector_mod.glob.glob

        def mock_glob(p):
            if "claude" in p:
                return [claude_gate_1, claude_gate_2]
            if "codex" in p:
                return codex_gate_files
            if "antigravity" in p:
                return agy_gate_files
            return []

        collector_mod.glob.glob = mock_glob
        try:
            collector.collect_claude()
            collector.collect_codex()
            collector.collect_antigravity()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector.state["counters"]["tokens"]
        costs = collector.state["counters"]["cost_usd"]
        sessions = collector.state["counters"]["sessions"]

        # Claude: 2 セッション合算 (150k input * $4/1M + 30k output * $20/1M = $0.60 + $0.60 = $1.20)
        cl_base = 'agent="claude",branch="bot-wa-wa/gate-parallel",model="claude-opus-5-5",phase="gate",repo="nuage-cluster",task="並列ゲート計測テスト"'
        self.assertEqual(tokens[f'{cl_base},type="input"'], 150_000)
        self.assertEqual(tokens[f'{cl_base},type="output"'], 30_000)
        self.assertAlmostEqual(costs[cl_base], 1.20, places=8)
        self.assertEqual(
            sessions['agent="claude",branch="bot-wa-wa/gate-parallel",phase="gate",repo="nuage-cluster"'],
            2,
        )

        # Codex: 2 セッション合算 (200k input * $10/1M + 20k output * $50/1M = $2.00 + $1.00 = $3.00)
        cx_base = 'agent="codex",branch="bot-wa-wa/gate-parallel",model="gpt-6-astra",phase="gate",repo="nuage-cluster",task="並列ゲート計測テスト"'
        self.assertEqual(tokens[f'{cx_base},type="input"'], 200_000)
        self.assertEqual(tokens[f'{cx_base},type="output"'], 20_000)
        self.assertAlmostEqual(costs[cx_base], 3.00, places=8)
        self.assertEqual(
            sessions['agent="codex",branch="bot-wa-wa/gate-parallel",phase="gate",repo="nuage-cluster"'],
            2,
        )

        # Antigravity: 2 セッション合算 (400k input * $1.50/1M + 80k output * $7.50/1M = $0.60 + $0.60 = $1.20)
        agy_base = 'agent="agy",branch="bot-wa-wa/gate-parallel",model="gemini-4-hydrogen-high",phase="gate",repo="nuage-cluster",task="並列ゲート計測テスト"'
        self.assertEqual(tokens[f'{agy_base},type="input"'], 400_000)
        self.assertEqual(tokens[f'{agy_base},type="output"'], 80_000)
        self.assertAlmostEqual(costs[agy_base], 1.20, places=8)
        self.assertEqual(
            sessions['agent="agy",branch="bot-wa-wa/gate-parallel",phase="gate",repo="nuage-cluster"'],
            2,
        )

        # Prometheus 出力と run.log の後続フェーズに引きずられていないことの確認
        payload = collector.generate_prometheus_payload()
        self.assertIn(f'nuage_ai_agent_tokens_total{{{cl_base},type="input"}} 150000', payload)
        self.assertIn(f'nuage_ai_agent_cost_usd_total{{{cx_base}}} 3.0', payload)
        self.assertIn('nuage_ai_agent_sessions_total{agent="agy",branch="bot-wa-wa/gate-parallel",phase="gate",repo="nuage-cluster"} 2', payload)
        self.assertNotIn('phase="summarize"', payload)
        self.assertNotIn('phase="fix"', payload)
        self.assertNotIn('phase="review"', payload)

    def test_gate_portal_isolation_and_run_log_fallback(self):
        # 1. 各エージェントの portal セッションは gate 文言や == gating の run.log があっても phase="portal", task="portal" を維持
        # 2. Codex exec セッションの == gating フォールバックは phase="gate" になる
        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        ws_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-gate-portal")
        auto_dir = os.path.join(ws_dir, ".autopilot")
        git_dir = os.path.join(ws_dir, ".git")
        os.makedirs(auto_dir, exist_ok=True)
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/gate-portal\n")
        with open(os.path.join(auto_dir, "brief.md"), "w", encoding="utf-8") as f:
            f.write("# ポータル隔離テスト\n")
        with open(os.path.join(auto_dir, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] start impl=agy level=high\n[10:01:00] == gating (round 1: codex)\n")

        gate_text = "あなたはリポジトリのゲート検証担当である。ゲートの手順書に従って実際に実行して確かめる。"

        # Claude CLI (portal)
        claude_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-ws-gate-portal")
        os.makedirs(claude_dir, exist_ok=True)
        claude_portal = os.path.join(claude_dir, "cli-portal.jsonl")
        with open(claude_portal, "w", encoding="utf-8") as f:
            f.write(json.dumps({"type": "attachment", "entrypoint": "cli"}) + "\n")
            f.write(json.dumps({"type": "user", "entrypoint": "cli", "message": {"content": gate_text}}) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "cli",
                "cwd": ws_dir,
                "gitBranch": "bot-wa-wa/gate-portal",
                "message": {"id": "msg-p-cl", "model": "claude-opus-5-5", "usage": {"input_tokens": 1000, "output_tokens": 100}},
            }) + "\n")

        # Codex portal 各条件を単独で検証 (source="cli", source="vscode", originator="codex-tui", originator="orca_desktop")
        # + Codex exec (プロンプト未特定 -> run.log == gating フォールバック)
        codex_dir = os.path.join(self.test_dir, "codex", "sessions", "2026", "11", "19")
        os.makedirs(codex_dir, exist_ok=True)
        codex_portal_cases = [
            ("cli-only", {"source": "cli", "originator": "other"}),
            ("vscode-only", {"source": "vscode", "originator": "other"}),
            ("codex-tui-only", {"source": "other", "originator": "codex-tui"}),
            ("orca-desktop-only", {"source": "other", "originator": "orca_desktop"}),
        ]
        codex_portals = []
        for idx, (label, meta_fields) in enumerate(codex_portal_cases):
            p = os.path.join(codex_dir, f"rollout-portal-{label}.jsonl")
            with open(p, "w", encoding="utf-8") as f:
                f.write(json.dumps({
                    "type": "session_meta",
                    "payload": {"cwd": ws_dir, "git": {"branch": "bot-wa-wa/gate-portal"}, **meta_fields},
                }) + "\n")
                f.write(json.dumps({
                    "type": "event_msg",
                    "payload": {"type": "thread_settings_applied", "thread_settings": {"model": "gpt-6-luna"}},
                }) + "\n")
                f.write(json.dumps({
                    "type": "response_item",
                    "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": gate_text}]},
                }) + "\n")
                f.write(json.dumps({
                    "type": "token_usage_record",
                    "payload": {"response_id": f"resp-p-cx-{idx}", "usage": {"input_tokens": 500, "cached_input_tokens": 0, "output_tokens": 50}},
                }) + "\n")
            codex_portals.append(p)

        codex_fb = os.path.join(codex_dir, "rollout-exec-fb.jsonl")
        with open(codex_fb, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "session_meta",
                "payload": {"cwd": ws_dir, "source": "exec", "originator": "codex_exec", "git": {"branch": "bot-wa-wa/gate-portal"}},
            }) + "\n")
            f.write(json.dumps({
                "type": "event_msg",
                "payload": {"type": "thread_settings_applied", "thread_settings": {"model": "gpt-6-luna"}},
            }) + "\n")
            f.write(json.dumps({
                "type": "token_usage_record",
                "payload": {"response_id": "resp-fb-cx", "usage": {"input_tokens": 3000, "cached_input_tokens": 0, "output_tokens": 300}},
            }) + "\n")

        # Antigravity (A: portal_cids 登録済み, B: 未登録だが非定型 USER_INPUT + step_index > 0 で gate 文言)
        agy_portal_a_dir = os.path.join(self.test_dir, "brain", "conv-portal-gate-a", ".system_generated", "logs")
        os.makedirs(agy_portal_a_dir, exist_ok=True)
        agy_portal_a = os.path.join(agy_portal_a_dir, "transcript.jsonl")
        with open(agy_portal_a, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": f"<USER_REQUEST>{gate_text}</USER_REQUEST>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 4000,
                "output_tokens": 400,
                "content": "確認した。",
            }) + "\n")

        agy_portal_b_dir = os.path.join(self.test_dir, "brain", "conv-portal-gate-b", ".system_generated", "logs")
        os.makedirs(agy_portal_b_dir, exist_ok=True)
        agy_portal_b = os.path.join(agy_portal_b_dir, "transcript.jsonl")
        with open(agy_portal_b, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>この PR のゲート結果を教えて。brief の要点も確認したい。</USER_REQUEST>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": gate_text,
            }) + "\n")
            f.write(json.dumps({
                "step_index": 2,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 5000,
                "output_tokens": 500,
                "content": "承知した。",
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
            rates_file=repo_rates_path,
        )
        collector.state["portal_cids"]["conv-portal-gate-a"] = True
        for cid in ("conv-portal-gate-a", "conv-portal-gate-b"):
            collector.state["cid_to_meta"][cid] = {
                "repo": "nuage-cluster",
                "branch": "bot-wa-wa/gate-portal",
                "worktree": ws_dir,
            }

        orig_glob = collector_mod.glob.glob

        def mock_glob(p):
            if "claude" in p:
                return [claude_portal]
            if "codex" in p:
                return codex_portals + [codex_fb]
            if "antigravity" in p:
                return [agy_portal_a, agy_portal_b]
            return []

        collector_mod.glob.glob = mock_glob
        try:
            collector.collect_claude()
            collector.collect_codex()
            collector.collect_antigravity()
        finally:
            collector_mod.glob.glob = orig_glob

        tokens = collector.state["counters"]["tokens"]
        self.assertEqual(
            tokens['agent="claude",branch="bot-wa-wa/gate-portal",model="claude-opus-5-5",phase="portal",repo="nuage-cluster",task="portal",type="input"'],
            1000,
        )
        self.assertEqual(
            tokens['agent="codex",branch="bot-wa-wa/gate-portal",model="gpt-6-luna",phase="portal",repo="nuage-cluster",task="portal",type="input"'],
            2000,
        )
        self.assertEqual(
            collector.state["counters"]["sessions"]['agent="codex",branch="bot-wa-wa/gate-portal",phase="portal",repo="nuage-cluster"'],
            4,
        )
        self.assertEqual(
            tokens['agent="codex",branch="bot-wa-wa/gate-portal",model="gpt-6-luna",phase="gate",repo="nuage-cluster",task="ポータル隔離テスト",type="input"'],
            3000,
        )
        self.assertEqual(
            tokens['agent="agy",branch="bot-wa-wa/gate-portal",model="unknown",phase="portal",repo="nuage-cluster",task="portal",type="input"'],
            9000,
        )
        self.assertEqual(
            collector.state["counters"]["sessions"]['agent="agy",branch="bot-wa-wa/gate-portal",phase="portal",repo="nuage-cluster"'],
            2,
        )

    def test_claude_and_agy_session_counted_deferred_until_prompt_classification(self):
        # 先頭に session-owner や queue-operation (gate 指示文) のみが書き出された時点で
        # portal=1 や branch="unknown", phase="gate" を誤計上せず、
        # 起動元・ラベル情報の取得後に正しいフェーズ・ブランチで 1 セッション計上されること
        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        ws_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-defer")
        git_dir = os.path.join(ws_dir, ".git")
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/defer-no-meta\n")
        gate_prompt = "あなたはリポジトリのゲート検証担当である。ゲートの手順書に従って実際に実行して確かめる。"

        claude_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-ws-defer")
        os.makedirs(claude_dir, exist_ok=True)
        claude_gate = os.path.join(claude_dir, "sess-gate.jsonl")
        claude_cli_with_q = os.path.join(claude_dir, "sess-cli-q.jsonl")
        claude_cli = os.path.join(claude_dir, "sess-cli.jsonl")

        agy_dir = os.path.join(self.test_dir, "brain", "conv-agy-defer", ".system_generated", "logs")
        os.makedirs(agy_dir, exist_ok=True)
        agy_gate = os.path.join(agy_dir, "transcript.jsonl")

        agy_no_meta_dir = os.path.join(self.test_dir, "brain", "conv-agy-no-meta", ".system_generated", "logs")
        os.makedirs(agy_no_meta_dir, exist_ok=True)
        agy_no_meta = os.path.join(agy_no_meta_dir, "transcript.jsonl")

        # 段階1: メタ行のみ（および cid_to_meta なしの Antigravity USER_INPUT のみ）
        with open(claude_gate, "w", encoding="utf-8") as f:
            f.write(json.dumps({"type": "session-owner", "sessionId": "s-gate"}) + "\n")
            f.write(json.dumps({"parentUuid": None, "attachment": {"type": "hook_success"}}) + "\n")
        with open(claude_cli_with_q, "w", encoding="utf-8") as f:
            f.write(json.dumps({"type": "session-owner", "sessionId": "s-cli-q"}) + "\n")
            f.write(json.dumps({"type": "queue-operation", "operation": "enqueue", "content": gate_prompt}) + "\n")
        with open(claude_cli, "w", encoding="utf-8") as f:
            f.write(json.dumps({"type": "session-owner", "sessionId": "s-cli"}) + "\n")
        with open(agy_gate, "w", encoding="utf-8") as f:
            f.write(json.dumps({"step_index": 0, "source": "SYSTEM", "type": "GENERIC", "content": "init"}) + "\n")
        with open(agy_no_meta, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": f"<USER_REQUEST>{gate_prompt}</USER_REQUEST><USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Gemini 4 Hydrogen (High).</USER_SETTINGS_CHANGE>",
            }) + "\n")

        orig_glob = collector_mod.glob.glob

        def mock_glob(p):
            if "claude" in p:
                return [claude_gate, claude_cli_with_q, claude_cli]
            if "antigravity" in p:
                return [agy_gate, agy_no_meta]
            return []

        collector_mod.glob.glob = mock_glob
        try:
            c1 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c1.state["cid_to_meta"]["conv-agy-defer"] = {
                "repo": "nuage-cluster",
                "branch": "bot-wa-wa/defer-test",
                "worktree": ws_dir,
            }
            c1.collect_claude()
            c1.collect_antigravity()
            c1._save_state()

            # 段階1 では起動元・ラベル未確定のため何も計上されないこと
            self.assertEqual(c1.state["counters"]["sessions"], {})
            self.assertEqual(c1.state["counters"]["tokens"], {})
            self.assertEqual(c1.state["counters"]["cost_usd"], {})

            # 段階2: claude_gate に queue-operation (gate 指示文) だけを追記して収集
            with open(claude_gate, "a", encoding="utf-8") as f:
                f.write(json.dumps({"type": "queue-operation", "operation": "enqueue", "content": gate_prompt}) + "\n")

            c2_q = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c2_q.collect_claude()
            c2_q.collect_antigravity()
            c2_q._save_state()

            # queue-operation 直後でも起動元とブランチが未取得のため保留されること
            self.assertEqual(c2_q.state["counters"]["sessions"], {})
            self.assertEqual(c2_q.state["counters"]["tokens"], {})

            # 段階3: 起動元 (sdk-cli / cli)・ブランチ・応答が追記される
            with open(claude_gate, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "type": "attachment",
                    "entrypoint": "sdk-cli",
                    "cwd": ws_dir,
                    "gitBranch": "bot-wa-wa/defer-test",
                }) + "\n")
                f.write(json.dumps({
                    "type": "user",
                    "entrypoint": "sdk-cli",
                    "cwd": ws_dir,
                    "gitBranch": "bot-wa-wa/defer-test",
                    "message": {"role": "user", "content": gate_prompt},
                }) + "\n")
                f.write(json.dumps({
                    "type": "assistant",
                    "entrypoint": "sdk-cli",
                    "cwd": ws_dir,
                    "gitBranch": "bot-wa-wa/defer-test",
                    "message": {"id": "msg-defer-gate", "model": "claude-opus-5-5", "usage": {"input_tokens": 1000, "output_tokens": 200}},
                }) + "\n")

            with open(claude_cli_with_q, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "type": "user",
                    "entrypoint": "cli",
                    "cwd": ws_dir,
                    "gitBranch": "bot-wa-wa/defer-cli-q",
                    "message": {"role": "user", "content": gate_prompt},
                }) + "\n")
                f.write(json.dumps({
                    "type": "assistant",
                    "entrypoint": "cli",
                    "cwd": ws_dir,
                    "gitBranch": "bot-wa-wa/defer-cli-q",
                    "message": {"id": "msg-defer-cli-q", "model": "claude-opus-5-5", "usage": {"input_tokens": 200, "output_tokens": 40}},
                }) + "\n")

            with open(claude_cli, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "type": "user",
                    "entrypoint": "cli",
                    "cwd": ws_dir,
                    "gitBranch": "bot-wa-wa/defer-portal",
                    "message": {"role": "user", "content": "状態を確認して"},
                }) + "\n")
                f.write(json.dumps({
                    "type": "assistant",
                    "entrypoint": "cli",
                    "cwd": ws_dir,
                    "gitBranch": "bot-wa-wa/defer-portal",
                    "message": {"id": "msg-defer-cli", "model": "claude-opus-5-5", "usage": {"input_tokens": 300, "output_tokens": 50}},
                }) + "\n")

            with open(agy_gate, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "step_index": 0,
                    "source": "USER_EXPLICIT",
                    "type": "USER_INPUT",
                    "content": f"<USER_REQUEST>{gate_prompt}</USER_REQUEST><USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Gemini 4 Hydrogen (High).</USER_SETTINGS_CHANGE>",
                }) + "\n")
                f.write(json.dumps({
                    "step_index": 1,
                    "source": "MODEL",
                    "type": "PLANNER_RESPONSE",
                    "input_tokens": 4000,
                    "output_tokens": 500,
                    "content": "検証完了",
                }) + "\n")

            with open(agy_no_meta, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "step_index": 1,
                    "source": "MODEL",
                    "type": "PLANNER_RESPONSE",
                    "input_tokens": 2500,
                    "output_tokens": 250,
                    "content": f"ワークスペース {ws_dir} で検証完了",
                }) + "\n")

            c3 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c3.collect_claude()
            c3.collect_antigravity()
            c3._save_state()

            expected_sessions = {
                'agent="claude",branch="bot-wa-wa/defer-test",phase="gate",repo="nuage-cluster"': 1,
                'agent="claude",branch="bot-wa-wa/defer-cli-q",phase="portal",repo="nuage-cluster"': 1,
                'agent="claude",branch="bot-wa-wa/defer-portal",phase="portal",repo="nuage-cluster"': 1,
                'agent="agy",branch="bot-wa-wa/defer-test",phase="gate",repo="nuage-cluster"': 1,
                'agent="agy",branch="bot-wa-wa/defer-no-meta",phase="gate",repo="nuage-cluster"': 1,
            }
            self.assertEqual(c3.state["counters"]["sessions"], expected_sessions)

            # 一括収集（最初から全行を読む場合）と辞書全体が一致すること
            batch_state = os.path.join(self.test_dir, "batch-defer.json")
            c_batch = MetricsCollector(
                state_file=batch_state, vm_url="http://localhost:8427", dry_run=True, rates_file=repo_rates_path
            )
            c_batch.state["cid_to_meta"]["conv-agy-defer"] = {
                "repo": "nuage-cluster",
                "branch": "bot-wa-wa/defer-test",
                "worktree": ws_dir,
            }
            c_batch.collect_claude()
            c_batch.collect_antigravity()

            self.assertEqual(c3.state["counters"]["sessions"], c_batch.state["counters"]["sessions"])
            self.assertEqual(c3.state["counters"]["tokens"], c_batch.state["counters"]["tokens"])
            self.assertEqual(c3.state["counters"]["cost_usd"], c_batch.state["counters"]["cost_usd"])
        finally:
            collector_mod.glob.glob = orig_glob

    def test_antigravity_deferred_session_without_usage_or_file_growth(self):
        # 1. portal_cids 未登録の通常会話で USER_INPUT を先に収集し、次回使用量なし GENERIC 行から
        #    repo/branch が判明した際、saw_user_input 復元により portal=1 が計上されること
        # 2. gate 指示だけの先行収集で保留した後、ログ追記なし (file_size 不変) で会話メタデータや
        #    portal_cids が後から取得可能になった場合に再評価され、一括収集と一致すること
        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        ws_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-agy-meta")
        git_dir = os.path.join(ws_dir, ".git")
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/agy-meta-branch\n")

        gate_prompt = "あなたはリポジトリのゲート検証担当である。ゲートの手順書に従って実際に実行して確かめる。"

        # (A) 通常会話 (使用量なし GENERIC 行からワークスペース取得)
        portal_dir = os.path.join(self.test_dir, "brain", "conv-agy-generic-ws", ".system_generated", "logs")
        os.makedirs(portal_dir, exist_ok=True)
        portal_path = os.path.join(portal_dir, "transcript.jsonl")
        with open(portal_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>状況を教えて</USER_REQUEST>",
            }) + "\n")

        # (B) gate 指示のみ -> 後からファイル追記なしで cid_to_meta が利用可能になるケース
        gate_nometa_dir = os.path.join(self.test_dir, "brain", "conv-agy-static-gate", ".system_generated", "logs")
        os.makedirs(gate_nometa_dir, exist_ok=True)
        gate_nometa_path = os.path.join(gate_nometa_dir, "transcript.jsonl")
        with open(gate_nometa_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": f"<USER_REQUEST>{gate_prompt}</USER_REQUEST>",
            }) + "\n")

        # (C) gate 文言入り -> 後からファイル追記なしで portal_cids + cid_to_meta に載るケース
        late_portal_dir = os.path.join(self.test_dir, "brain", "conv-agy-late-portal", ".system_generated", "logs")
        os.makedirs(late_portal_dir, exist_ok=True)
        late_portal_path = os.path.join(late_portal_dir, "transcript.jsonl")
        with open(late_portal_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": f"<USER_REQUEST>{gate_prompt}</USER_REQUEST>",
            }) + "\n")

        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [portal_path, gate_nometa_path, late_portal_path] if "antigravity" in p else []
        try:
            # 段階1: メタデータもワークスペースパスも無い状態で初回収集 -> すべて保留
            c1 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c1.collect_antigravity()
            c1._save_state()
            self.assertEqual(c1.state["counters"]["sessions"], {})
            self.assertTrue(c1.state["agy_offsets"][portal_path]["saw_user_input"])
            self.assertFalse(c1.state["agy_offsets"][portal_path]["session_counted"])
            self.assertFalse(c1.state["agy_offsets"][gate_nometa_path]["session_counted"])

            # 段階2:
            # - (A) には使用量なしの GENERIC 行のみ追記
            # - (B), (C) はファイルサイズ不変のまま cid_to_meta / portal_cids のみ更新
            with open(portal_path, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "step_index": 1,
                    "source": "SYSTEM",
                    "type": "GENERIC",
                    "content": f"ワークスペース {ws_dir} を開いた。",
                }) + "\n")

            c2 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c2.state["cid_to_meta"]["conv-agy-static-gate"] = {
                "repo": "nuage-cluster",
                "branch": "bot-wa-wa/agy-meta-branch",
                "worktree": ws_dir,
            }
            c2.state["cid_to_meta"]["conv-agy-late-portal"] = {
                "repo": "nuage-cluster",
                "branch": "bot-wa-wa/agy-late-portal",
                "worktree": ws_dir,
            }
            c2.state["portal_cids"]["conv-agy-late-portal"] = True
            c2.collect_antigravity()
            c2._save_state()

            expected_sessions = {
                'agent="agy",branch="bot-wa-wa/agy-meta-branch",phase="portal",repo="nuage-cluster"': 1,
                'agent="agy",branch="bot-wa-wa/agy-meta-branch",phase="gate",repo="nuage-cluster"': 1,
                'agent="agy",branch="bot-wa-wa/agy-late-portal",phase="portal",repo="nuage-cluster"': 1,
            }
            self.assertEqual(c2.state["counters"]["sessions"], expected_sessions)
            self.assertTrue(c2.state["agy_offsets"][portal_path]["session_counted"])
            self.assertTrue(c2.state["agy_offsets"][gate_nometa_path]["session_counted"])
            self.assertTrue(c2.state["agy_offsets"][late_portal_path]["session_counted"])

            # 段階3: 追記なしで再実行しても二重計上されないこと
            c3 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c3.collect_antigravity()
            self.assertEqual(c3.state["counters"]["sessions"], expected_sessions)

            # 一括収集（メタデータ確定済みの状態で最初から収集）と一致すること
            batch_state = os.path.join(self.test_dir, "batch-agy-meta.json")
            c_batch = MetricsCollector(
                state_file=batch_state, vm_url="http://localhost:8427", dry_run=True, rates_file=repo_rates_path
            )
            c_batch.state["cid_to_meta"]["conv-agy-static-gate"] = {
                "repo": "nuage-cluster",
                "branch": "bot-wa-wa/agy-meta-branch",
                "worktree": ws_dir,
            }
            c_batch.state["cid_to_meta"]["conv-agy-late-portal"] = {
                "repo": "nuage-cluster",
                "branch": "bot-wa-wa/agy-late-portal",
                "worktree": ws_dir,
            }
            c_batch.state["portal_cids"]["conv-agy-late-portal"] = True
            c_batch.collect_antigravity()
            self.assertEqual(c3.state["counters"]["sessions"], c_batch.state["counters"]["sessions"])
            self.assertEqual(c3.state["counters"]["tokens"], c_batch.state["counters"]["tokens"])
            self.assertEqual(c3.state["counters"]["cost_usd"], c_batch.state["counters"]["cost_usd"])
        finally:
            collector_mod.glob.glob = orig_glob

    def test_antigravity_recovers_from_incomplete_cache_via_db_without_file_growth(self):
        # 初回収集で repo・worktree のみ判明し branch="unknown" の不完全キャッシュが cid_to_meta に保存された場合でも、
        # 後から conversation_summaries.db とワークスペースのブランチ情報が揃えば無追記再評価で回復し、
        # 一括収集と一致して phase="gate" の 1 セッションが計上されること
        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        ws_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-agy-db-recover")
        partial_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-agy-partial-nogit")
        os.makedirs(ws_dir, exist_ok=True)
        os.makedirs(partial_dir, exist_ok=True)

        db_path = os.path.join(self.test_dir, "conversation_summaries.db")
        with sqlite3.connect(db_path) as conn:
            conn.execute("CREATE TABLE conversation_summaries (conversation_id TEXT PRIMARY KEY, workspace_uris TEXT)")

        gate_prompt = "あなたはリポジトリのゲート検証担当である。ゲートの手順書に従って実際に実行して確かめる。"
        agy_dir = os.path.join(self.test_dir, "brain", "conv-agy-db-recover", ".system_generated", "logs")
        os.makedirs(agy_dir, exist_ok=True)
        agy_path = os.path.join(agy_dir, "transcript.jsonl")
        with open(agy_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": (
                    f"<USER_REQUEST>{gate_prompt}</USER_REQUEST>"
                    "<USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Gemini 4 Hydrogen (High).</USER_SETTINGS_CHANGE>"
                ),
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "SYSTEM",
                "type": "GENERIC",
                "content": f"作業ディレクトリ {partial_dir} を確認中。",
            }) + "\n")

        orig_glob = collector_mod.glob.glob
        orig_expanduser = os.path.expanduser
        collector_mod.glob.glob = lambda p: [agy_path] if "antigravity" in p else []
        os.path.expanduser = lambda p: db_path if "conversation_summaries.db" in p else orig_expanduser(p)
        try:
            # 段階1: repo と ws_path (partial_dir) だけ判明し、branch="unknown" のまま cid_to_meta に保存される
            c1 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c1.collect_antigravity()
            c1._save_state()

            self.assertEqual(c1.state["counters"]["sessions"], {})
            self.assertFalse(c1.state["agy_offsets"][agy_path]["session_counted"])
            self.assertEqual(
                c1.state["cid_to_meta"]["conv-agy-db-recover"],
                {"repo": "nuage-cluster", "branch": "unknown", "worktree": partial_dir},
            )

            # 段階2: ログへの追記なし (file_size 不変) で、DB と実ワークスペース (ws_dir) の git HEAD・brief.md が揃う
            git_dir = os.path.join(ws_dir, ".git")
            auto_dir = os.path.join(ws_dir, ".autopilot")
            os.makedirs(git_dir, exist_ok=True)
            os.makedirs(auto_dir, exist_ok=True)
            with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
                f.write("ref: refs/heads/bot-wa-wa/db-recovered-gate\n")
            with open(os.path.join(auto_dir, "brief.md"), "w", encoding="utf-8") as f:
                f.write("# DB復旧ゲートタスク\n")
            with sqlite3.connect(db_path) as conn:
                conn.execute(
                    "INSERT INTO conversation_summaries VALUES (?, ?)",
                    ("conv-agy-db-recover", f'["file://{ws_dir}"]'),
                )

            c2 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c2.collect_antigravity()
            c2._save_state()

            expected_sessions = {
                'agent="agy",branch="bot-wa-wa/db-recovered-gate",phase="gate",repo="nuage-cluster"': 1,
            }
            self.assertEqual(c2.state["counters"]["sessions"], expected_sessions)
            self.assertTrue(c2.state["agy_offsets"][agy_path]["session_counted"])
            self.assertEqual(c2.state["agy_offsets"][agy_path]["branch"], "bot-wa-wa/db-recovered-gate")
            self.assertEqual(c2.state["agy_offsets"][agy_path]["ws_path"], ws_dir)
            self.assertEqual(c2.state["agy_offsets"][agy_path]["task"], "DB復旧ゲートタスク")
            self.assertEqual(
                c2.state["cid_to_meta"]["conv-agy-db-recover"],
                {"repo": "nuage-cluster", "branch": "bot-wa-wa/db-recovered-gate", "worktree": ws_dir},
            )

            # 段階3: その後トークン使用量が追記されても、ws_dir の brief.md 見出し (DB復旧ゲートタスク) で計上され一括収集と一致する
            with open(agy_path, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "step_index": 2,
                    "source": "MODEL",
                    "type": "PLANNER_RESPONSE",
                    "input_tokens": 100_000,
                    "output_tokens": 10_000,
                    "content": "ゲート検証を完了した。",
                }) + "\n")

            c3 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c3.collect_antigravity()
            c3._save_state()

            expected_tok_base = 'agent="agy",branch="bot-wa-wa/db-recovered-gate",model="gemini-4-hydrogen-high",phase="gate",repo="nuage-cluster",task="DB復旧ゲートタスク"'
            self.assertEqual(c3.state["counters"]["tokens"][f'{expected_tok_base},type="input"'], 100_000)
            self.assertEqual(c3.state["counters"]["tokens"][f'{expected_tok_base},type="output"'], 10_000)
            self.assertGreater(c3.state["counters"]["cost_usd"][expected_tok_base], 0.0)

            # 一括収集（DB 確定済み状態での初回収集）と一致すること
            batch_state = os.path.join(self.test_dir, "batch-db-recover.json")
            c_batch = MetricsCollector(
                state_file=batch_state, vm_url="http://localhost:8427", dry_run=True, rates_file=repo_rates_path
            )
            c_batch.collect_antigravity()
            self.assertEqual(c3.state["counters"]["sessions"], c_batch.state["counters"]["sessions"])
            self.assertEqual(c3.state["counters"]["tokens"], c_batch.state["counters"]["tokens"])
            self.assertEqual(c3.state["counters"]["cost_usd"], c_batch.state["counters"]["cost_usd"])
        finally:
            collector_mod.glob.glob = orig_glob
            os.path.expanduser = orig_expanduser

    def test_gate_incremental_dedup_partial_and_v4_state_compat(self):
        # 1. 非空オフセット・重複防止IDを持つ既存の v4 状態を引き継いだまま、gate セッションを追加収集しても既存ログが再計上されず既存カウンタも保持されること
        # 2. Claude・Codex・Antigravity の gate セッションで初回指示前分割・段階的追記・不完全行・重複 ID スキップ・再実行を行っても一括収集と辞書全体で一致すること
        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        ws_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-gate-inc")
        os.makedirs(ws_dir, exist_ok=True)
        gate_prompt = "あなたはリポジトリのゲート検証担当である。ゲートの手順書に従って実際に実行して確かめる。"

        claude_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-ws-gate-inc")
        os.makedirs(claude_dir, exist_ok=True)
        prev_claude_path = os.path.join(claude_dir, "prev-review.jsonl")
        claude_path = os.path.join(claude_dir, "gate-inc.jsonl")

        codex_dir = os.path.join(self.test_dir, "codex", "sessions", "2026", "11", "19")
        os.makedirs(codex_dir, exist_ok=True)
        prev_codex_path = os.path.join(codex_dir, "rollout-prev-fix.jsonl")
        codex_path = os.path.join(codex_dir, "rollout-gate-inc.jsonl")

        prev_agy_dir = os.path.join(self.test_dir, "brain", "conv-prev-review", ".system_generated", "logs")
        os.makedirs(prev_agy_dir, exist_ok=True)
        prev_agy_path = os.path.join(prev_agy_dir, "transcript.jsonl")

        agy_dir = os.path.join(self.test_dir, "brain", "conv-agy-gate-inc", ".system_generated", "logs")
        os.makedirs(agy_dir, exist_ok=True)
        agy_path = os.path.join(agy_dir, "transcript.jsonl")

        # 既存収集済みログ (過去の review / fix セッション)
        with open(prev_claude_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({"type": "queue-operation", "content": "あなたはコードレビュアーである。"}) + "\n")
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": ws_dir,
                "gitBranch": "bot-wa-wa/prev",
                "message": {"id": "cl-prev-1", "model": "claude-opus-5-5", "usage": {"input_tokens": 12_345, "output_tokens": 500}},
            }) + "\n")
        with open(prev_codex_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "session_meta",
                "payload": {"cwd": ws_dir, "source": "exec", "originator": "codex_exec", "git": {"branch": "bot-wa-wa/prev"}},
            }) + "\n")
            f.write(json.dumps({
                "type": "event_msg",
                "payload": {"type": "thread_settings_applied", "thread_settings": {"model": "gpt-6-astra"}},
            }) + "\n")
            f.write(json.dumps({
                "type": "response_item",
                "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "直すべきものを直す。"}]},
            }) + "\n")
            f.write(json.dumps({
                "type": "token_usage_record",
                "payload": {"response_id": "cx-prev-1", "usage": {"input_tokens": 8000, "cached_input_tokens": 0, "output_tokens": 400}},
            }) + "\n")
        with open(prev_agy_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>あなたはコードレビュアーである。</USER_REQUEST><USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Gemini 4 Hydrogen (High).</USER_SETTINGS_CHANGE>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 9000,
                "output_tokens": 300,
                "content": "確認済み",
            }) + "\n")

        # 既存 v4 状態ファイル (session_counted 未導入の旧 v4 オフセットも含む非空状態)
        initial_tokens = {
            'agent="claude",branch="bot-wa-wa/prev",model="claude-opus-5-5",phase="review",repo="nuage-cluster",task="bot-wa-wa/prev",type="input"': 12_345,
            'agent="claude",branch="bot-wa-wa/prev",model="claude-opus-5-5",phase="review",repo="nuage-cluster",task="bot-wa-wa/prev",type="output"': 500,
            'agent="codex",branch="bot-wa-wa/prev",model="gpt-6-astra",phase="fix",repo="nuage-cluster",task="bot-wa-wa/prev",type="input"': 8000,
            'agent="codex",branch="bot-wa-wa/prev",model="gpt-6-astra",phase="fix",repo="nuage-cluster",task="bot-wa-wa/prev",type="output"': 400,
            'agent="agy",branch="bot-wa-wa/prev",model="gemini-4-hydrogen-high",phase="review",repo="nuage-cluster",task="bot-wa-wa/prev",type="input"': 9000,
            'agent="agy",branch="bot-wa-wa/prev",model="gemini-4-hydrogen-high",phase="review",repo="nuage-cluster",task="bot-wa-wa/prev",type="output"': 300,
        }
        initial_costs = {
            'agent="claude",branch="bot-wa-wa/prev",model="claude-opus-5-5",phase="review",repo="nuage-cluster",task="bot-wa-wa/prev"': 0.222675,
            'agent="codex",branch="bot-wa-wa/prev",model="gpt-6-astra",phase="fix",repo="nuage-cluster",task="bot-wa-wa/prev"': 0.1,
            'agent="agy",branch="bot-wa-wa/prev",model="gemini-4-hydrogen-high",phase="review",repo="nuage-cluster",task="bot-wa-wa/prev"': 0.01575,
        }
        initial_sessions = {
            'agent="claude",branch="bot-wa-wa/prev",phase="review",repo="nuage-cluster"': 1,
            'agent="codex",branch="bot-wa-wa/prev",phase="fix",repo="nuage-cluster"': 1,
            'agent="agy",branch="bot-wa-wa/prev",phase="review",repo="nuage-cluster"': 1,
        }
        initial_v4_state = {
            "version": 4,
            "claude_offsets": {
                prev_claude_path: {
                    "offset": os.path.getsize(prev_claude_path),
                    "repo": "nuage-cluster",
                    "branch": "bot-wa-wa/prev",
                    "ws_path": ws_dir,
                    "phase": "review",
                    "task": "bot-wa-wa/prev",
                    "brief_task": "unknown",
                    "context": "autopilot",
                    "entrypoint": "sdk-cli",
                    "model": "claude-opus-5-5",
                    "seen_message_ids": ["cl-prev-1"],
                }
            },
            "agy_offsets": {
                prev_agy_path: {
                    "offset": os.path.getsize(prev_agy_path),
                    "repo": "nuage-cluster",
                    "branch": "bot-wa-wa/prev",
                    "ws_path": ws_dir,
                    "phase": "review",
                    "task": "bot-wa-wa/prev",
                    "brief_task": "unknown",
                    "context": "autopilot",
                    "model": "gemini-4-hydrogen-high",
                }
            },
            "codex_offsets": {
                prev_codex_path: {
                    "offset": os.path.getsize(prev_codex_path),
                    "repo": "nuage-cluster",
                    "branch": "bot-wa-wa/prev",
                    "ws_path": ws_dir,
                    "phase": "fix",
                    "task": "bot-wa-wa/prev",
                    "brief_task": "unknown",
                    "context": "autopilot",
                    "source": "exec",
                    "originator": "codex_exec",
                    "model": "gpt-6-astra",
                    "session_counted": True,
                    "seen_response_ids": ["cx-prev-1"],
                }
            },
            "last_orca_stats_timestamp": 0,
            "orca_sessions": {},
            "portal_cids": {},
            "cid_to_repo": {},
            "cid_to_meta": {
                "conv-prev-review": {"repo": "nuage-cluster", "branch": "bot-wa-wa/prev", "worktree": ws_dir},
                "conv-agy-gate-inc": {"repo": "nuage-cluster", "branch": "bot-wa-wa/gate-inc", "worktree": ws_dir},
            },
            "autopilot_runs": {},
            "counters": {
                "tokens": dict(initial_tokens),
                "cost_usd": dict(initial_costs),
                "sessions": dict(initial_sessions),
                "duration": {},
                "autopilot_runs": {},
            },
        }
        with open(self.state_file, "w", encoding="utf-8") as f:
            json.dump(initial_v4_state, f)

        # 段階0: Claude は session-owner のみ、Codex は session_meta のみ、Antigravity は GENERIC メタ行のみ
        with open(claude_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({"type": "session-owner", "sessionId": "gate-inc-sess"}) + "\n")
        with open(codex_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "session_meta",
                "payload": {"cwd": ws_dir, "source": "exec", "originator": "codex_exec", "git": {"branch": "bot-wa-wa/gate-inc"}},
            }) + "\n")
        with open(agy_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({"step_index": 0, "source": "SYSTEM", "type": "GENERIC", "content": "init"}) + "\n")

        orig_glob = collector_mod.glob.glob
        include_prev_in_glob = True

        def mock_glob(p):
            if "claude" in p:
                return ([prev_claude_path] if include_prev_in_glob else []) + [claude_path]
            if "codex" in p:
                return ([prev_codex_path] if include_prev_in_glob else []) + [codex_path]
            if "antigravity" in p:
                return ([prev_agy_path] if include_prev_in_glob else []) + [agy_path]
            return []

        collector_mod.glob.glob = mock_glob
        try:
            # 段階0 収集
            c0 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c0.collect_claude()
            c0.collect_codex()
            c0.collect_antigravity()
            c0._save_state()

            # 段階0 ではエラーも起きず、既存値から一切増えないこと (portal 誤計上もなし)
            self.assertFalse(c0.has_errors)
            self.assertEqual(c0.state["counters"]["tokens"], initial_tokens)
            self.assertEqual(c0.state["counters"]["sessions"], initial_sessions)

            # 段階1: gate 指示文 + 初回応答 + 不完全行を各ファイルに書き込む
            # また既存収集済みファイルへ重複 ID 行を追記して seen_* による重複防止も検証
            with open(prev_claude_path, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "type": "assistant",
                    "entrypoint": "sdk-cli",
                    "cwd": ws_dir,
                    "gitBranch": "bot-wa-wa/prev",
                    "message": {"id": "cl-prev-1", "model": "claude-opus-5-5", "usage": {"input_tokens": 99999, "output_tokens": 99999}},
                }) + "\n")
            with open(prev_codex_path, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "type": "token_usage_record",
                    "payload": {"response_id": "cx-prev-1", "usage": {"input_tokens": 99999, "cached_input_tokens": 0, "output_tokens": 99999}},
                }) + "\n")

            with open(claude_path, "a", encoding="utf-8") as f:
                f.write(json.dumps({"type": "queue-operation", "content": gate_prompt}) + "\n")
                f.write(json.dumps({
                    "type": "assistant",
                    "entrypoint": "sdk-cli",
                    "cwd": ws_dir,
                    "gitBranch": "bot-wa-wa/gate-inc",
                    "message": {"id": "cl-inc-1", "model": "claude-opus-5-5", "usage": {"input_tokens": 1000, "output_tokens": 100}},
                }) + "\n")
                f.write('{"type": "assistant", "entrypoint": "sdk-cli", "message": {"id": "cl-inc-2"')

            with open(codex_path, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "type": "event_msg",
                    "payload": {"type": "thread_settings_applied", "thread_settings": {"model": "gpt-6-astra"}},
                }) + "\n")
                f.write(json.dumps({
                    "type": "response_item",
                    "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": gate_prompt}]},
                }) + "\n")
                f.write(json.dumps({
                    "type": "token_usage_record",
                    "payload": {"response_id": "cx-inc-1", "usage": {"input_tokens": 2000, "cached_input_tokens": 0, "output_tokens": 200}},
                }) + "\n")
                f.write('{"type": "token_usage_record", "payload": {"response_id": "cx-inc-2"')

            with open(agy_path, "a", encoding="utf-8") as f:
                f.write(json.dumps({
                    "step_index": 0,
                    "source": "USER_EXPLICIT",
                    "type": "USER_INPUT",
                    "content": f"<USER_REQUEST>{gate_prompt}</USER_REQUEST><USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Gemini 4 Hydrogen (High).</USER_SETTINGS_CHANGE>",
                }) + "\n")
                f.write(json.dumps({
                    "step_index": 1,
                    "source": "MODEL",
                    "type": "PLANNER_RESPONSE",
                    "input_tokens": 3000,
                    "output_tokens": 300,
                    "content": f"ワークスペース {ws_dir} で検証中。",
                }) + "\n")
                f.write('{"step_index": 2, "source": "MODEL", "type": "PLANNER_RESPONSE"')

            c1 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c1.collect_claude()
            c1.collect_codex()
            c1.collect_antigravity()
            c1._save_state()

            # 段階2: 不完全行を補完 + 重複 ID の再送を追記
            with open(claude_path, "a", encoding="utf-8") as f:
                f.write(', "model": "claude-opus-5-5", "usage": {"input_tokens": 500, "output_tokens": 50}}}\n')
                f.write(json.dumps({
                    "type": "assistant",
                    "entrypoint": "sdk-cli",
                    "cwd": ws_dir,
                    "gitBranch": "bot-wa-wa/gate-inc",
                    "message": {"id": "cl-inc-1", "model": "claude-opus-5-5", "usage": {"input_tokens": 9999, "output_tokens": 9999}},
                }) + "\n")

            with open(codex_path, "a", encoding="utf-8") as f:
                f.write(', "usage": {"input_tokens": 600, "cached_input_tokens": 0, "output_tokens": 60}}}\n')
                f.write(json.dumps({
                    "type": "token_usage_record",
                    "payload": {"response_id": "cx-inc-1", "usage": {"input_tokens": 9999, "cached_input_tokens": 0, "output_tokens": 9999}},
                }) + "\n")

            with open(agy_path, "a", encoding="utf-8") as f:
                f.write(', "input_tokens": 700, "output_tokens": 70, "content": "検証完了"}\n')

            c2 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c2.collect_claude()
            c2.collect_codex()
            c2.collect_antigravity()
            c2._save_state()

            # 段階3: 変更なしで再実行しても何も増えないこと
            c3 = MetricsCollector(
                state_file=self.state_file, vm_url="http://localhost:8427", dry_run=False, rates_file=repo_rates_path
            )
            c3.collect_claude()
            c3.collect_codex()
            c3.collect_antigravity()

            self.assertFalse(c1.has_errors)
            self.assertFalse(c2.has_errors)
            self.assertFalse(c3.has_errors)
            self.assertEqual(c3.state["version"], 4)

            # 既存 v4 カウンタを除いた gate 増分辞書を算出
            delta_tokens = {}
            for k, v in c3.state["counters"]["tokens"].items():
                diff = v - initial_tokens.get(k, 0)
                if diff != 0 or k not in initial_tokens:
                    delta_tokens[k] = diff
            delta_costs = {}
            for k, v in c3.state["counters"]["cost_usd"].items():
                diff = round(v - initial_costs.get(k, 0.0), 10)
                if diff != 0.0 or k not in initial_costs:
                    delta_costs[k] = diff
            delta_sessions = {}
            for k, v in c3.state["counters"]["sessions"].items():
                diff = v - initial_sessions.get(k, 0)
                if diff != 0 or k not in initial_sessions:
                    delta_sessions[k] = diff

            # 既存カウンタが 1 ビットも変化していないこと
            for k, v in initial_tokens.items():
                self.assertEqual(c3.state["counters"]["tokens"][k], v)
            for k, v in initial_costs.items():
                self.assertAlmostEqual(c3.state["counters"]["cost_usd"][k], v, places=8)
            for k, v in initial_sessions.items():
                self.assertEqual(c3.state["counters"]["sessions"][k], v)

            # 各エージェントの期待トークン数・期待セッション数の明示検証
            expected_gate_tokens = {
                'agent="claude",branch="bot-wa-wa/gate-inc",model="claude-opus-5-5",phase="gate",repo="nuage-cluster",task="bot-wa-wa/gate-inc",type="input"': 1500,
                'agent="claude",branch="bot-wa-wa/gate-inc",model="claude-opus-5-5",phase="gate",repo="nuage-cluster",task="bot-wa-wa/gate-inc",type="output"': 150,
                'agent="codex",branch="bot-wa-wa/gate-inc",model="gpt-6-astra",phase="gate",repo="nuage-cluster",task="bot-wa-wa/gate-inc",type="input"': 2600,
                'agent="codex",branch="bot-wa-wa/gate-inc",model="gpt-6-astra",phase="gate",repo="nuage-cluster",task="bot-wa-wa/gate-inc",type="output"': 260,
                'agent="agy",branch="bot-wa-wa/gate-inc",model="gemini-4-hydrogen-high",phase="gate",repo="nuage-cluster",task="bot-wa-wa/gate-inc",type="input"': 3700,
                'agent="agy",branch="bot-wa-wa/gate-inc",model="gemini-4-hydrogen-high",phase="gate",repo="nuage-cluster",task="bot-wa-wa/gate-inc",type="output"': 370,
                'agent="agy",branch="bot-wa-wa/gate-inc",model="gemini-4-hydrogen-high",phase="gate",repo="nuage-cluster",task="bot-wa-wa/gate-inc",type="cache_read"': 0,
            }
            expected_gate_sessions = {
                'agent="claude",branch="bot-wa-wa/gate-inc",phase="gate",repo="nuage-cluster"': 1,
                'agent="codex",branch="bot-wa-wa/gate-inc",phase="gate",repo="nuage-cluster"': 1,
                'agent="agy",branch="bot-wa-wa/gate-inc",phase="gate",repo="nuage-cluster"': 1,
            }
            self.assertEqual(delta_tokens, expected_gate_tokens)
            self.assertEqual(delta_sessions, expected_gate_sessions)

            # 一括収集（新規状態ファイル・新規 gate セッションのみ）と増分辞書全体が完全一致すること
            include_prev_in_glob = False
            batch_state = os.path.join(self.test_dir, "batch-gate-state.json")
            c_batch = MetricsCollector(
                state_file=batch_state, vm_url="http://localhost:8427", dry_run=True, rates_file=repo_rates_path
            )
            c_batch.state["cid_to_meta"]["conv-agy-gate-inc"] = {
                "repo": "nuage-cluster",
                "branch": "bot-wa-wa/gate-inc",
                "worktree": ws_dir,
            }
            c_batch.collect_claude()
            c_batch.collect_codex()
            c_batch.collect_antigravity()

            self.assertEqual(delta_tokens, c_batch.state["counters"]["tokens"])
            self.assertEqual(delta_sessions, c_batch.state["counters"]["sessions"])
            self.assertEqual(set(delta_costs.keys()), set(c_batch.state["counters"]["cost_usd"].keys()))
            for k, v in c_batch.state["counters"]["cost_usd"].items():
                self.assertAlmostEqual(delta_costs[k], v, places=8)
        finally:
            collector_mod.glob.glob = orig_glob

    def test_new_codex_models_collection_and_costs(self):
        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        ws_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-new-codex")
        git_dir = os.path.join(ws_dir, ".git")
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/new-codex\n")

        codex_dir = os.path.join(self.test_dir, "codex", "sessions", "2026", "11", "20")
        os.makedirs(codex_dir, exist_ok=True)
        jsonl_path = os.path.join(codex_dir, "rollout-new-codex.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "session_meta",
                "payload": {
                    "cwd": ws_dir,
                    "source": "exec",
                    "originator": "codex_exec",
                    "git": {"branch": "bot-wa-wa/new-codex"},
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "event_msg",
                "payload": {
                    "type": "thread_settings_applied",
                    "thread_settings": {"model": "gpt-6.2-astra"},
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": "あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。"}],
                },
            }) + "\n")
            # gpt-6.2-astra: non-cached input=100k ($0.80) + output=25k ($1.00) + cache_read=200k ($0.08) = $1.88
            f.write(json.dumps({
                "type": "token_usage_record",
                "payload": {
                    "response_id": "resp-62-astra-1",
                    "usage": {
                        "input_tokens": 300_000,
                        "cached_input_tokens": 200_000,
                        "output_tokens": 25_000,
                    },
                },
            }) + "\n")
            f.write(json.dumps({
                "type": "event_msg",
                "payload": {
                    "type": "thread_settings_applied",
                    "thread_settings": {"model": "gpt-6.2-sol"},
                },
            }) + "\n")
            # gpt-6.2-sol: non-cached input=100k ($0.20) + output=20k ($0.20) + cache_read=100k ($0.01) = $0.41
            f.write(json.dumps({
                "type": "token_usage_record",
                "payload": {
                    "response_id": "resp-62-sol-1",
                    "usage": {
                        "input_tokens": 200_000,
                        "cached_input_tokens": 100_000,
                        "output_tokens": 20_000,
                    },
                },
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
            rates_file=repo_rates_path,
        )
        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [jsonl_path] if "codex" in p else []
        try:
            with mock.patch.object(collector, "warn", wraps=collector.warn) as mock_warn:
                collector.collect_codex()
                mock_warn.assert_not_called()
        finally:
            collector_mod.glob.glob = orig_glob

        self.assertFalse(collector.has_errors)
        costs = collector.state["counters"]["cost_usd"]
        astra_key = 'agent="codex",branch="bot-wa-wa/new-codex",model="gpt-6-2-astra",phase="implement",repo="nuage-cluster",task="bot-wa-wa/new-codex"'
        sol_key = 'agent="codex",branch="bot-wa-wa/new-codex",model="gpt-6-2-sol",phase="implement",repo="nuage-cluster",task="bot-wa-wa/new-codex"'
        self.assertAlmostEqual(costs[astra_key], 1.88, places=8)
        self.assertAlmostEqual(costs[sol_key], 0.41, places=8)

    def test_antigravity_model_selection_and_record_model_fallback(self):
        repo_rates_path = os.path.join(
            os.path.dirname(__file__), "..", "nix", "hosts", "atelier", "rates.yaml"
        )
        ws_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-agy-models")
        git_dir = os.path.join(ws_dir, ".git")
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as f:
            f.write("ref: refs/heads/bot-wa-wa/agy-models\n")

        # 1. Model Selection (Orchestrator (Neon) -> Orchestrator (Argon)) が record["model"] より優先され途中変更にも追従する
        b1_dir = os.path.join(self.test_dir, "brain", "conv-sel-prio", ".system_generated", "logs")
        os.makedirs(b1_dir, exist_ok=True)
        t1_path = os.path.join(b1_dir, "transcript.jsonl")
        with open(t1_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": (
                    "<USER_REQUEST>あなたはコードレビュアーである。</USER_REQUEST>"
                    "<USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Orchestrator (Neon).</USER_SETTINGS_CHANGE>"
                ),
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "model": "gemini-pro-orchestrator-neon",
                "input_tokens": 100_000,
                "output_tokens": 20_000,
                "cache_read_tokens": 100_000,
                "content": f"ワークスペース {ws_dir} を確認。",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 2,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from Orchestrator (Neon) to Orchestrator (Argon).</USER_SETTINGS_CHANGE>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 3,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "model": "gemini-pro-orchestrator-g1-pro",
                "input_tokens": 100_000,
                "output_tokens": 10_000,
                "cache_read_tokens": 100_000,
                "content": "追加確認。",
            }) + "\n")

        # 2. Model Selection が無い場合、PLANNER_RESPONSE の record["model"] (gemini-4-neon-high) で補完され、以降の行や差分追記でも維持・Model Selection 変更で上書きされる
        b2_dir = os.path.join(self.test_dir, "brain", "conv-rec-fb", ".system_generated", "logs")
        os.makedirs(b2_dir, exist_ok=True)
        t2_path = os.path.join(b2_dir, "transcript.jsonl")
        with open(t2_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>あなたは自律実行の担当である。</USER_REQUEST>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "model": "gemini-4-neon-high",
                "input_tokens": 150_000,
                "output_tokens": 5_000,
                "cache_read_tokens": 50_000,
                "content": f"ワークスペース {ws_dir} で実装。",
            }) + "\n")
            # model フィールドが無い後続応答でも直前に補完されたモデルを引き継ぐ
            f.write(json.dumps({
                "step_index": 2,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 50_000,
                "output_tokens": 5_000,
                "cache_read_tokens": 50_000,
                "content": "継続応答。",
            }) + "\n")

        # 3. Model Selection なしでスラッグ名 (gemini-pro-orchestrator-neon / gemini-pro-orchestrator-g1-pro) を抽出するケース
        b3_dir = os.path.join(self.test_dir, "brain", "conv-slug-neon", ".system_generated", "logs")
        os.makedirs(b3_dir, exist_ok=True)
        t3_path = os.path.join(b3_dir, "transcript.jsonl")
        with open(t3_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>あなたはコードレビュアーである。</USER_REQUEST>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "model": "gemini-pro-orchestrator-neon",
                "input_tokens": 100_000,
                "output_tokens": 20_000,
                "cache_read_tokens": 100_000,
                "content": f"ワークスペース {ws_dir} をレビュー。",
            }) + "\n")

        b4_dir = os.path.join(self.test_dir, "brain", "conv-slug-argon", ".system_generated", "logs")
        os.makedirs(b4_dir, exist_ok=True)
        t4_path = os.path.join(b4_dir, "transcript.jsonl")
        with open(t4_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 0,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_REQUEST>あなたはコードレビュアーである。</USER_REQUEST>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 1,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "model": "gemini-pro-orchestrator-g1-pro",
                "input_tokens": 100_000,
                "output_tokens": 10_000,
                "cache_read_tokens": 100_000,
                "content": f"ワークスペース {ws_dir} をレビュー。",
            }) + "\n")

        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=False,
            rates_file=repo_rates_path,
        )
        orig_glob = collector_mod.glob.glob
        collector_mod.glob.glob = lambda p: [t1_path, t2_path, t3_path, t4_path] if "antigravity" in p else []
        try:
            with mock.patch.object(collector, "warn", wraps=collector.warn) as mock_warn:
                collector.collect_antigravity()
                collector._save_state()
                mock_warn.assert_not_called()
        finally:
            collector_mod.glob.glob = orig_glob

        self.assertFalse(collector.has_errors)
        costs = collector.state["counters"]["cost_usd"]
        tokens = collector.state["counters"]["tokens"]

        k_orch_neon = 'agent="agy",branch="bot-wa-wa/agy-models",model="orchestrator-neon",phase="review",repo="nuage-cluster",task="bot-wa-wa/agy-models"'
        k_orch_argon = 'agent="agy",branch="bot-wa-wa/agy-models",model="orchestrator-argon",phase="review",repo="nuage-cluster",task="bot-wa-wa/agy-models"'
        k_neon_high = 'agent="agy",branch="bot-wa-wa/agy-models",model="gemini-4-neon-high",phase="implement",repo="nuage-cluster",task="bot-wa-wa/agy-models"'
        k_slug_neon = 'agent="agy",branch="bot-wa-wa/agy-models",model="gemini-pro-orchestrator-neon",phase="review",repo="nuage-cluster",task="bot-wa-wa/agy-models"'
        k_slug_argon = 'agent="agy",branch="bot-wa-wa/agy-models",model="gemini-pro-orchestrator-g1-pro",phase="review",repo="nuage-cluster",task="bot-wa-wa/agy-models"'

        self.assertAlmostEqual(costs[k_orch_neon], 0.615, places=8)
        self.assertAlmostEqual(costs[k_orch_argon], 0.31, places=8)
        self.assertEqual(tokens[f'{k_neon_high},type="input"'], 200_000)
        self.assertAlmostEqual(costs[k_neon_high], 0.765, places=8)
        self.assertAlmostEqual(costs[k_slug_neon], 0.615, places=8)
        self.assertAlmostEqual(costs[k_slug_argon], 0.31, places=8)

        # 差分追記: t2 に Model Selection 変更を追加したら切り替わること
        with open(t2_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({
                "step_index": 3,
                "source": "USER_EXPLICIT",
                "type": "USER_INPUT",
                "content": "<USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from Gemini 4 Neon (High) to Gemini 4 Hydrogen (High).</USER_SETTINGS_CHANGE>",
            }) + "\n")
            f.write(json.dumps({
                "step_index": 4,
                "source": "MODEL",
                "type": "PLANNER_RESPONSE",
                "input_tokens": 100_000,
                "output_tokens": 20_000,
                "cache_read_tokens": 0,
                "content": "切り替え後応答。",
            }) + "\n")

        collector2 = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
            rates_file=repo_rates_path,
        )
        collector_mod.glob.glob = lambda p: [t2_path] if "antigravity" in p else []
        try:
            collector2.collect_antigravity()
        finally:
            collector_mod.glob.glob = orig_glob

        k_hydrogen = 'agent="agy",branch="bot-wa-wa/agy-models",model="gemini-4-hydrogen-high",phase="implement",repo="nuage-cluster",task="bot-wa-wa/agy-models"'
        self.assertAlmostEqual(collector2.state["counters"]["cost_usd"][k_hydrogen], 0.30, places=8)
        self.assertAlmostEqual(collector2.state["counters"]["cost_usd"][k_neon_high], 0.765, places=8)




if __name__ == "__main__":
    unittest.main()
