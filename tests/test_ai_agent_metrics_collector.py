#!/usr/bin/env python3
"""
ai-agent-metrics-collector.py の単体テスト。
"""

import importlib
import json
import os
import shutil
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
extract_task_from_brief = collector_mod.extract_task_from_brief
extract_pr_number = collector_mod.extract_pr_number
detect_phase = collector_mod.detect_phase
get_antigravity_conversation_meta = collector_mod.get_antigravity_conversation_meta
get_antigravity_conversation_repo = collector_mod.get_antigravity_conversation_repo
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
        self.assertEqual(normalize_branch_name("tmp"), "tmp")
        self.assertEqual(normalize_branch_name("/tmp"), "tmp")
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

    def test_extract_pr_number(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            auto_dir = os.path.join(tmp_dir, ".autopilot")
            os.makedirs(auto_dir, exist_ok=True)

            # run.log に PR #57
            with open(os.path.join(auto_dir, "run.log"), "w", encoding="utf-8") as f:
                f.write("[10:00:00] PR #57\n[10:05:00] == done\n")
            self.assertEqual(extract_pr_number(tmp_dir), "57")

            # result.md に URL 形式
            with open(os.path.join(auto_dir, "result.md"), "w", encoding="utf-8") as f:
                f.write("PR: https://github.com/k-wa-wa/nuage-cluster/pull/123\n")
            self.assertEqual(extract_pr_number(tmp_dir), "123")

            # PR 記載なし
            with tempfile.TemporaryDirectory() as empty_dir:
                self.assertEqual(extract_pr_number(empty_dir), "none")

    def test_detect_phase(self):
        self.assertEqual(
            detect_phase("あなたは自律実行の担当である。.autopilot/brief.md の仕様を実装し、テストがあれば実行して通す。"),
            "implement",
        )
        self.assertEqual(
            detect_phase("あなたはコードレビュアーである。ファイルは一切変更しない。`git diff` をレビューする。"),
            "review",
        )
        self.assertEqual(
            detect_phase("次のファイルを読み、直すべきものを直す。\n- レビュー結果: .autopilot/review-1-agy.md"),
            "fix",
        )
        self.assertEqual(
            detect_phase("人間向けの要約を .autopilot/result.md に書く。PR #57 の本文も同じ内容で更新する。"),
            "summarize",
        )
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

        expected_key = 'agent="claude",branch="bot-wa-wa/test-branch",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",type="input"'
        self.assertIn(expected_key, tokens)
        self.assertEqual(tokens[expected_key], 100)
        thinking_key = 'agent="claude",branch="bot-wa-wa/test-branch",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",type="thinking"'
        self.assertEqual(tokens[thinking_key], 10)
        session_key = 'agent="claude",branch="bot-wa-wa/test-branch",phase="implement",repo="nuage-cluster"'
        self.assertEqual(sessions[session_key], 1)

    def test_claude_phases(self):
        # review, fix, summarize 各フェーズで正しくラベルが付与されることのテスト
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)

        orig_glob = collector_mod.glob.glob
        try:
            for idx, (prompt, expected_phase) in enumerate([
                ("あなたはコードレビュアーである。レビューする。", "review"),
                ("直すべきものを直す。レビュー結果: .autopilot/review-1-agy.md", "fix"),
                ("人間向けの要約を .autopilot/result.md に書く。", "summarize"),
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
                expected_key = f'agent="claude",branch="bot-wa-wa/phase-branch",model="claude-opus-5-5",phase="{expected_phase}",repo="nuage-cluster",type="input"'
                self.assertIn(expected_key, tokens)
                self.assertEqual(tokens[expected_key], 10)
        finally:
            collector_mod.glob.glob = orig_glob

    def test_claude_duplicate_message_id_dedup(self):
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-dup.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
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
        key_input = 'agent="claude",branch="bot-wa-wa/test-branch",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",type="input"'
        key_output = 'agent="claude",branch="bot-wa-wa/test-branch",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",type="output"'
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

        expected_key = 'agent="agy",branch="bot-wa-wa/feat-branch",model="gemini-3-8-flash-high",phase="implement",repo="nuage-cluster",type="input"'
        self.assertIn(expected_key, tokens)
        self.assertEqual(tokens[expected_key], 1200)
        out_key = 'agent="agy",branch="bot-wa-wa/feat-branch",model="gemini-3-8-flash-high",phase="implement",repo="nuage-cluster",type="output"'
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
        expected_key = 'agent="agy",branch="bot-wa-wa/feat-branch",model="gemini-3-8-flash-high",phase="implement",repo="nuage-cluster",type="input"'
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

    def test_state_migration_v1_to_v2(self):
        # v1 形式の状態ファイルが読み込まれたとき v2 にマイグレーションされ、古いカウンタがリセットされること
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
        self.assertEqual(len(collector.state["counters"]["tokens"]), 0)
        self.assertEqual(len(collector.state["counters"]["autopilot_runs"]), 0)
        self.assertEqual(len(collector.state["claude_offsets"]), 0)

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
            'agent="claude",branch="main",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",type="input"': 100,
        }
        collector.state["counters"]["sessions"] = {
            'agent="claude",branch="main",phase="implement",repo="nuage-cluster"': 1,
        }

        payload = collector.generate_prometheus_payload()
        self.assertIn("# TYPE nuage_ai_agent_tokens_total counter", payload)
        self.assertIn('nuage_ai_agent_tokens_total{agent="claude",branch="main",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",type="input"} 100', payload)
        self.assertIn("# TYPE nuage_ai_agent_sessions_total counter", payload)
        self.assertIn('nuage_ai_agent_sessions_total{agent="claude",branch="main",phase="implement",repo="nuage-cluster"} 1', payload)

    def test_state_persistence_and_incremental(self):
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-inc.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
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
        key_input = 'agent="claude",branch="bot-wa-wa/inc-branch",model="claude-opus-5-5",phase="implement",repo="nuage-cluster",type="input"'
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
        expected_key = 'agent="agy",branch="unknown",model="unknown",phase="portal",repo="unknown",type="input"'
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
        expected_key = 'agent="agy",branch="main",model="unknown",phase="portal",repo="nuage-cluster",type="input"'
        self.assertIn(expected_key, tokens)
        self.assertNotIn('repo="pechka"', str(tokens))

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


if __name__ == "__main__":
    unittest.main()
