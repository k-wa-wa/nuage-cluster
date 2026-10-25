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
        # モックの autopilot 実行ディレクトリを作成
        auto_dir = os.path.join(self.test_dir, "workspaces", "nuage-cluster", "test-ws", ".autopilot")
        os.makedirs(auto_dir, exist_ok=True)

        with open(os.path.join(auto_dir, "status"), "w", encoding="utf-8") as f:
            f.write("done\n")

        with open(os.path.join(auto_dir, "run.log"), "w", encoding="utf-8") as f:
            f.write("[10:00:00] start impl=claude level=high reviewers=agy base=abcdef from=implement\n")

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
        self.assertEqual(runs.get('impl="claude",level="high",repo="nuage-cluster",result="done"'), 1)

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


if __name__ == "__main__":
    unittest.main()
