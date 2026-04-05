import os
import json
import re
import asyncio
import xml.etree.ElementTree as ET
from typing import Iterable, TypedDict
from openai import AsyncOpenAI
from openai.types.chat import (
    ChatCompletionMessageParam, ChatCompletionSystemMessageParam,
    ChatCompletionAssistantMessageParam, ChatCompletionUserMessageParam
)
from dotenv import load_dotenv
from pydantic import BaseModel

load_dotenv(".env")

class _AgentResponse_McpToolCall_ToolCall(BaseModel):
    name: str
    parameters: str

class _AgentResponse_McpToolCall(BaseModel):
    name: str
    tool_call: _AgentResponse_McpToolCall_ToolCall

class _AgentResponse(BaseModel):
    tasks: str
    thinking: str
    mcp_tool_call: _AgentResponse_McpToolCall | None
    completed: str | None

class AgentState(TypedDict):
    tasks: str
    thinking: str
    completed: str | None

class Agent:
    def __init__(self, openai_client: AsyncOpenAI | None = None):
        self.openai_client = openai_client if openai_client else AsyncOpenAI(
            api_key=os.getenv("OPENAI_API_KEY") or "dummy",
            base_url=os.getenv("OPENAI_BASE_URL"),
        )
        self.model_name = os.getenv("AI_MODEL_NAME", "llama3.2:3b")

    async def _format_mcp_tools(self, mcp_clients) -> str:
        formatted = ""
        for client in mcp_clients:
            print(f"DEBUG: Listing tools for {client.name}...")
            try:
                tools_res = await asyncio.wait_for(client.list_tools(), timeout=10.0)
                names = [t.name for t in tools_res.tools]
                formatted += f"### Client: {client.name}\nTools: {', '.join(names)}\n"
            except Exception as e:
                print(f"DEBUG: Error listing tools for {client.name}: {e}")
                formatted += f"### Client: {client.name} (Error: {e})\n"
        return formatted

    async def build_system_prompt(self, *, mcp_clients) -> Iterable[ChatCompletionSystemMessageParam]:
        tools_summary = await self._format_mcp_tools(mcp_clients)
        prompt = f"""あなたはKubernetes SREです。MCPツールを使ってクラスターを調査し、インシデントレポートを作成します。

⚠️ 絶対ルール: すべての出力は「日本語」で書くこと。韓国語・英語・中国語は一切使用禁止。

# 重要ルール (Important Rules)
- 出力は必ず以下のXMLタグ形式に従ってください。タグ外に文字を出力しないこと。
- 調査は複数ステップで行い、各ステップで <thinking> に分析を記録すること。
- 最終レポートは必ず <completed> タグ内に **Markdown形式** で出力すること。
- <completed> タグを省略してはいけません。調査完了時は必ず使うこと。
- レポートは以下のテンプレートを必ず埋めること。セクションを省略しないこと。
- 言語は必ず日本語。韓国語・中国語・英語は不可。

# 応答形式

<tasks>
[現在実行中・予定のタスク一覧]
</tasks>
<thinking>
[調査の思考過程・ログ/メトリクスの分析・仮説と検証]
</thinking>

# ツール使用時
<mcp_tool_call>
  <name>クライアント名 (mcp-k8s または mcp-grafana)</name>
  <tool_call>
    <name>ツール名</name>
    <parameters>{{"key": "value"}}</parameters>
  </tool_call>
</mcp_tool_call>

# 調査完了・最終レポート出力時（必ずこのMarkdownテンプレートを使うこと）
<completed>
# 🚨 インシデント調査レポート

> **重大度:** [CRITICAL / HIGH / MEDIUM / LOW]　|　**ステータス:** [Active / Resolved / Investigating]　|　**発生時刻:** [YYYY-MM-DD HH:MM JST]

---

## 📋 概要

[インシデントの内容を2〜3文で簡潔に説明する。何が起きたか、影響範囲、現在の状態を記載]

---

## ⏰ タイムライン

| 時刻 | イベント |
|------|---------|
| HH:MM | [最初に検知されたイベント] |
| HH:MM | [調査・対応の経緯] |
| HH:MM | [現在の状態] |

---

## 🔬 根本原因分析

[調査によって特定した根本原因を詳細に説明する。ログの証拠、エラーメッセージ、設定ミスなどを引用して裏付けること]

```
[関連するログやエラーメッセージをここに貼る]
```

---

## 📦 影響サービス・リソース

| サービス/リソース | 影響内容 | 重大度 |
|----------------|---------|--------|
| [名前] | [影響の説明] | 🔴 HIGH / 🟡 MEDIUM / 🟢 LOW |

---

## 🔄 インシデントフロー

```mermaid
graph TD
    A[🚨 アラート発生] --> B[根本原因]
    B --> C[影響範囲]
    C --> D[対応アクション]
    D --> E[解決/監視継続]
```

---

## ✅ 解決手順

1. **即時対応**: [今すぐ実行すべきこと]
2. **調査確認**: [確認すべきリソース・ログ]
3. **恒久対策**: [再発防止のための設定変更・改善策]

```bash
# 参考コマンド
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
```

---

## 🔗 参考情報

- **関連ダッシュボード**: [GrafanaダッシュボードURL or パネル名]
- **関連アラート**: [AlertmanagerルールID]
- **ドキュメント**: [関連するRunbook or ドキュメントリンク]
</completed>

# 利用可能ツール
{tools_summary}
"""
        return [{"role": "system", "content": prompt}]

    def parse_response(self, response_str: str) -> tuple[_AgentResponse, str | None]:
        t = re.search(r"<(?:tasks|task)>(.*?)</(?:tasks|task)>", response_str, re.DOTALL | re.IGNORECASE)
        th = re.search(r"<(?:thinking|thought)>(.*?)</(?:thinking|thought)>", response_str, re.DOTALL | re.IGNORECASE)
        c = re.search(r"<(?:completed|report|answer|final)>(.*?)</(?:completed|report|answer|final)>", response_str, re.DOTALL | re.IGNORECASE)
        m_n = re.search(r"<name>(.*?)</name>", response_str, re.IGNORECASE)
        t_n = re.search(r"<tool_call>.*?<name>(.*?)</name>", response_str, re.DOTALL | re.IGNORECASE)
        t_p = re.search(r"<parameters>(.*?)</parameters>", response_str, re.DOTALL | re.IGNORECASE)

        mcp_tool_call = None
        if m_n and t_n:
            mcp_tool_call = _AgentResponse_McpToolCall(
                name=m_n.group(1).strip(),
                tool_call=_AgentResponse_McpToolCall_ToolCall(
                    name=t_n.group(1).strip(),
                    parameters=t_p.group(1).strip() if t_p else "{}"
                )
            )

        # フォールバック：タグがないが十分な長さがあれば完了とみなす
        if not (t or th or c or mcp_tool_call) and len(response_str.strip()) > 100:
            print("DEBUG: Fallback to completed due to no tags but long text")
            fallback_text = response_str.strip()
            # 先頭の <completed> タグを除去
            fallback_text = re.sub(r"^\s*<(?:completed|report|answer|final)>\s*", "", fallback_text, flags=re.IGNORECASE)
            # 末尾の </completed> タグを除去
            fallback_text = re.sub(r"\s*</(?:completed|report|answer|final)>\s*$", "", fallback_text, flags=re.IGNORECASE)
            return _AgentResponse(tasks="", thinking="", mcp_tool_call=None, completed=fallback_text.strip()), None

        if t or th or c or mcp_tool_call:
            completed_text = c.group(1).strip() if c else None
            # モデルが <completed> を二重に出力した場合の後処理
            if completed_text:
                inner = re.search(r"<(?:completed|report|answer|final)>(.*?)(?:</(?:completed|report|answer|final)>|$)", completed_text, re.DOTALL | re.IGNORECASE)
                if inner:
                    completed_text = inner.group(1).strip()
            return _AgentResponse(
                tasks=t.group(1).strip() if t else "",
                thinking=th.group(1).strip() if th else "",
                mcp_tool_call=mcp_tool_call,
                completed=completed_text
            ), None
        return None, "No valid tags found"

    async def generate(self, *, user_instructions: str, mcp_clients):
        MAX_ITER = 10
        FORCE_COMPLETE_AT = MAX_ITER - 2  # この反復から完了を強制
        messages = [
            *(await self.build_system_prompt(mcp_clients=mcp_clients)),
            {"role": "user", "content": user_instructions}
        ]
        for i in range(MAX_ITER):
            print(f"====== Iteration {i+1} ======")
            # 最後の2回は強制的に完了するよう指示（日本語のみ）
            if i >= FORCE_COMPLETE_AT:
                messages.append({
                    "role": "user",
                    "content": (
                        "⚠️ 残り反復回数が少ないため、今すぐ最終レポートを出力してください。\n"
                        "・ツール呼び出しは禁止です。\n"
                        "・これまでに収集した情報に基づいて <completed> タグ内に最終レポートを書いてください。\n"
                        "・言語は必ず日本語のみ。韓国語・英語は絶対に使わないこと。\n"
                        "・<completed> タグの中身は下のテンプレート通りに書いてください。\n\n"
                        "<completed>\n# 🚨 インシデント調査レポート\n> **重大度:** HIGH | **ステータス:** Investigating\n\n## 📋 概要\n（ここに概要）\n\n## ⏰ タイムライン\n| 時刻 | イベント |\n|------|----------|\n| - | - |\n\n## 🔬 根本原因分析\n（ここに原因）\n\n## 📦 影響サービス\n（リスト）\n\n## ✅ 解決手順\n1. （手順1）\n</completed>"
                    )
                })
            try:
                res = await self.openai_client.chat.completions.create(
                    model=self.model_name,
                    messages=messages,
                    extra_body={"options": {"num_ctx": 16384}}
                )
                content = res.choices[0].message.content
                print(f"DEBUG: AI Output length: {len(content)}")
                messages.append({"role": "assistant", "content": content})

                resp, error = self.parse_response(content)
                if error:
                    print(f"DEBUG: Parse Error: {error}")
                    messages.append({"role": "user", "content": "エラー: <tasks>, <thinking>, <completed> タグを使ってください。"})
                    continue

                yield AgentState(tasks=resp.tasks, thinking=resp.thinking, completed=resp.completed)
                if resp.completed:
                    print("DEBUG: Agent completed.")
                    return

                if tc := resp.mcp_tool_call:
                    print(f"DEBUG: Executing tool {tc.name}:{tc.tool_call.name}")
                    try:
                        c = mcp_clients.get_client(tc.name)
                        r = await asyncio.wait_for(c.call_tool(name=tc.tool_call.name, arguments=json.loads(tc.tool_call.parameters)), timeout=20.0)
                        messages.append({"role": "user", "content": f"Result: {r}"})
                    except Exception as e:
                        print(f"DEBUG: Tool Error: {e}")
                        messages.append({"role": "user", "content": f"ツールエラー: {e}"})
            except Exception as e:
                print(f"DEBUG: API Error: {e}")
                yield AgentState(tasks="", thinking="", completed=f"Error: {e}")
                return
