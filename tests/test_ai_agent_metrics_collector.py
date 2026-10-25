#!/usr/bin/env python3
"""
ai-agent-metrics-collector.py の単体テスト。
"""

import json
import os
import shutil
import tempfile
import unittest
import sys

# テスト対象スクリプトのインポート
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
import importlib
collector_mod = importlib.import_module("ai-agent-metrics-collector")

normalize_identifier = collector_mod.normalize_identifier
normalize_repo_name = collector_mod.normalize_repo_name
normalize_model_name = collector_mod.normalize_model_name
MetricsCollector = collector_mod.MetricsCollector


class TestNormalization(unittest.TestCase):
    def test_normalize_identifier(self):
        self.assertEqual(normalize_identifier("Claude-Opus-5.5"), "claude-opus-5-5")
        self.assertEqual(normalize_identifier("Gemini 3.8 Flash"), "gemini-3-8-flash")
        self.assertEqual(normalize_identifier(""), "unknown")
        self.assertEqual(normalize_identifier(None), "unknown")

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


class TestMetricsCollector(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.state_file = os.path.join(self.test_dir, "state.json")

    def tearDown(self):
        shutil.rmtree(self.test_dir)

    def test_claude_collection(self):
        # モックの Claude ログを作成
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-1.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
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

        self.assertIn('agent="claude",context="autopilot",model="claude-opus-5-5",repo="nuage-cluster",type="input"', tokens)
        self.assertEqual(tokens['agent="claude",context="autopilot",model="claude-opus-5-5",repo="nuage-cluster",type="input"'], 100)
        self.assertEqual(tokens['agent="claude",context="autopilot",model="claude-opus-5-5",repo="nuage-cluster",type="thinking"'], 10)
        self.assertEqual(sessions['agent="claude",context="autopilot",repo="nuage-cluster"'], 1)

    def test_claude_duplicate_message_id_dedup(self):
        # 同一 message.id を持つ複数行が重複計上されないことのテスト
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-dup.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            # 1つの応答の content ブロック (thinking / text / tool_use) が複数行に分かれて同じ id / usage を持つ
            for _ in range(3):
                f.write(json.dumps({
                    "type": "assistant",
                    "entrypoint": "sdk-cli",
                    "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
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
        # 3行あっても 100 / 50 の 1 回分のみ加算されること
        self.assertEqual(tokens['agent="claude",context="autopilot",model="claude-opus-5-5",repo="nuage-cluster",type="input"'], 100)
        self.assertEqual(tokens['agent="claude",context="autopilot",model="claude-opus-5-5",repo="nuage-cluster",type="output"'], 50)

    def test_antigravity_collection(self):
        # モックの Antigravity ログを作成
        brain_dir = os.path.join(self.test_dir, "brain", "conv-1", ".system_generated", "logs")
        os.makedirs(brain_dir, exist_ok=True)
        transcript_path = os.path.join(brain_dir, "transcript.jsonl")

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
                "content": "ワークスペース /home/nixos/orca/workspaces/nuage-cluster/feat で作業する。",
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

        self.assertIn('agent="agy",context="autopilot",model="gemini-3-8-flash-high",repo="nuage-cluster",type="input"', tokens)
        self.assertEqual(tokens['agent="agy",context="autopilot",model="gemini-3-8-flash-high",repo="nuage-cluster",type="input"'], 1200)
        self.assertEqual(tokens['agent="agy",context="autopilot",model="gemini-3-8-flash-high",repo="nuage-cluster",type="output"'], 80)
        self.assertEqual(sessions['agent="agy",context="autopilot",repo="nuage-cluster"'], 1)

    def test_antigravity_incremental_preserves_labels(self):
        # 差分実行時にも判定済みラベル (repo, model, context) が保持されることのテスト
        brain_dir = os.path.join(self.test_dir, "brain", "conv-inc", ".system_generated", "logs")
        os.makedirs(brain_dir, exist_ok=True)
        transcript_path = os.path.join(brain_dir, "transcript.jsonl")

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
                "content": "ワークスペース /home/nixos/orca/workspaces/nuage-cluster/feat で作業する。",
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

        # 追記（モデル変更や自律実行プロンプトを含まない純粋な回答追記）
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
        expected_key = 'agent="agy",context="autopilot",model="gemini-3-8-flash-high",repo="nuage-cluster",type="input"'
        self.assertIn(expected_key, tokens)
        # 1回目 10 + 2回目 20 = 30
        self.assertEqual(tokens[expected_key], 30)
        # unknown ラベルに入っていないこと
        unknown_key = 'agent="agy",context="portal",model="unknown",repo="unknown",type="input"'
        self.assertNotIn(unknown_key, tokens)

    def test_file_error_rollback(self):
        # パース途中でエラーが出たファイルの中間状態がロールバックされ、オフセットも進まないこと
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
            # 壊れた行（usage が辞書でない不正データ等）ではなく、意図的に型エラーを起こす異常値
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

        # エラーが記録されたこと
        self.assertTrue(collector.has_errors)
        # トークンは途中でロールバックされ 0 件であること
        self.assertEqual(len(collector.state["counters"]["tokens"]), 0)
        # オフセットも保存されていないこと
        self.assertNotIn(jsonl_path, collector.state["claude_offsets"])

    def test_autopilot_runs_collection(self):
        # モックの autopilot 実行ディレクトリを作成（done, failed: ..., needs-human: ...）
        auto_dir_done = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "ws-done", ".autopilot")
        os.makedirs(auto_dir_done, exist_ok=True)
        with open(os.path.join(auto_dir_done, "status"), "w", encoding="utf-8") as f:
            f.write("done\n")
        with open(os.path.join(auto_dir_done, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] start impl=claude level=high reviewers=agy base=abcdef from=implement\n")

        auto_dir_failed = os.path.join(self.test_dir, "workspaces", "pechka", "ws-failed", ".autopilot")
        os.makedirs(auto_dir_failed, exist_ok=True)
        with open(os.path.join(auto_dir_failed, "status"), "w", encoding="utf-8") as f:
            f.write("failed: test execution timed out\n")
        with open(os.path.join(auto_dir_failed, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] start impl=agy level=medium reviewers=claude base=123456\n")

        auto_dir_human = os.path.join(self.test_dir, "workspaces", "nuage-autopilot5", "ws-human", ".autopilot")
        os.makedirs(auto_dir_human, exist_ok=True)
        with open(os.path.join(auto_dir_human, "status"), "w", encoding="utf-8") as f:
            f.write("needs-human: merge conflicts require user intervention\n")
        with open(os.path.join(auto_dir_human, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] start impl=claude level=low\n")

        # 未完了ステータス（集計対象外）
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
        self.assertEqual(runs.get('impl="claude",level="high",repo="nuage-cluster",result="done"'), 1)
        self.assertEqual(runs.get('impl="agy",level="medium",repo="pechka",result="failed"'), 1)
        self.assertEqual(runs.get('impl="claude",level="low",repo="nuage-autopilot5",result="needs-human"'), 1)
        # 未完了ステータスは含まれないこと
        self.assertEqual(len(runs), 3)

    def test_state_file_corruption_raises_error(self):
        # 破損した JSON が存在する場合に空状態で継続せず RuntimeError で停止すること
        with open(self.state_file, "w", encoding="utf-8") as f:
            f.write("{invalid_json: true, broken")

        with self.assertRaises(RuntimeError):
            MetricsCollector(
                state_file=self.state_file,
                vm_url="http://localhost:8427",
                dry_run=True,
            )

    def test_orca_stats_portal_context(self):
        # worktree に .autopilot があっても Orca ペインのセッション時間は context="portal" になること
        auto_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "feature-x", ".autopilot")
        os.makedirs(auto_dir, exist_ok=True)

        orca_stats_file = os.path.join(self.test_dir, "orca-stats.json")
        last_status_file = os.path.join(self.test_dir, "last-status.json")

        sk = "test-tab:test-pane"
        wt_path = os.path.dirname(auto_dir)

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
        expected_key = 'agent="claude",context="portal",repo="nuage-cluster"'
        self.assertIn(expected_key, duration)
        self.assertEqual(duration[expected_key], 50.0)
        # context="autopilot" のキーが存在しないこと
        unexpected_key = 'agent="claude",context="autopilot",repo="nuage-cluster"'
        self.assertNotIn(unexpected_key, duration)

    def test_generate_prometheus_payload(self):
        collector = MetricsCollector(
            state_file=self.state_file,
            vm_url="http://localhost:8427",
            dry_run=True,
        )
        collector.state["counters"]["tokens"] = {
            'agent="claude",context="autopilot",model="claude-opus-5-5",repo="nuage-cluster",type="input"': 100,
        }
        collector.state["counters"]["sessions"] = {
            'agent="claude",context="autopilot",repo="nuage-cluster"': 1,
        }

        payload = collector.generate_prometheus_payload()
        self.assertIn("# TYPE nuage_ai_agent_tokens_total counter", payload)
        self.assertIn('nuage_ai_agent_tokens_total{agent="claude",context="autopilot",model="claude-opus-5-5",repo="nuage-cluster",type="input"} 100', payload)
        self.assertIn("# TYPE nuage_ai_agent_sessions_total counter", payload)
        self.assertIn('nuage_ai_agent_sessions_total{agent="claude",context="autopilot",repo="nuage-cluster"} 1', payload)

    def test_state_persistence_and_incremental(self):
        # 状態保存と増分読み取りのテスト
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-inc.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
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

        # 状態ファイルが保存されたことの確認
        self.assertTrue(os.path.exists(self.state_file))

        # 2行目を追記
        with open(jsonl_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({
                "type": "assistant",
                "entrypoint": "sdk-cli",
                "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
                "message": {
                    "id": "msg-inc-2",
                    "model": "claude-opus-5-5",
                    "usage": {"input_tokens": 30, "output_tokens": 5},
                },
            }) + "\n")

        # collector2 で増分のみパース
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
        self.assertEqual(tokens['agent="claude",context="autopilot",model="claude-opus-5-5",repo="nuage-cluster",type="input"'], 80)
        self.assertEqual(tokens['agent="claude",context="autopilot",model="claude-opus-5-5",repo="nuage-cluster",type="output"'], 15)
        # セッション数は 1 のまま増えていないこと
        sessions = collector2.state["counters"]["sessions"]
        self.assertEqual(sessions['agent="claude",context="autopilot",repo="nuage-cluster"'], 1)

    def test_claude_seen_message_ids_order(self):
        # seen_message_ids が 500 件を超えた場合に順序が保たれ最新 500 件が残ること
        project_dir = os.path.join(self.test_dir, "projects", "-home-nixos-orca-workspaces-nuage-cluster-test")
        os.makedirs(project_dir, exist_ok=True)
        jsonl_path = os.path.join(project_dir, "session-order.jsonl")

        with open(jsonl_path, "w", encoding="utf-8") as f:
            for i in range(550):
                f.write(json.dumps({
                    "type": "assistant",
                    "entrypoint": "sdk-cli",
                    "cwd": "/home/nixos/orca/workspaces/nuage-cluster/test",
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
        # 最初の 50 件 (0000〜0049) は切り捨てられ、最新 500 件 (0050〜0549) が順番通り残っていること
        self.assertEqual(seen_ids[0], "msg-ord-0050")
        self.assertEqual(seen_ids[-1], "msg-ord-0549")

    def test_antigravity_conversation_repo_from_db(self):
        # conversation_summaries.db から正しくワークスペースのリポジトリ名が引けること
        import sqlite3
        db_path = os.path.join(self.test_dir, "conversation_summaries.db")
        with sqlite3.connect(db_path) as conn:
            conn.execute("CREATE TABLE conversation_summaries (conversation_id TEXT PRIMARY KEY, workspace_uris TEXT)")
            conn.execute(
                "INSERT INTO conversation_summaries VALUES (?, ?)",
                ("cid-test-1", '["file:///home/nixos/orca/workspaces/nuage-cluster/my-branch"]'),
            )
            conn.execute(
                "INSERT INTO conversation_summaries VALUES (?, ?)",
                ("cid-test-2", '["file:///tmp"]'),
            )

        orig_expanduser = os.path.expanduser
        os.path.expanduser = lambda p: db_path if "conversation_summaries.db" in p else orig_expanduser(p)
        try:
            repo1 = collector_mod.get_antigravity_conversation_repo("cid-test-1")
            self.assertEqual(repo1, "nuage-cluster")
            repo2 = collector_mod.get_antigravity_conversation_repo("cid-test-2")
            self.assertEqual(repo2, "tmp")
            repo_unknown = collector_mod.get_antigravity_conversation_repo("nonexistent")
            self.assertEqual(repo_unknown, "unknown")
        finally:
            os.path.expanduser = orig_expanduser


if __name__ == "__main__":
    unittest.main()
