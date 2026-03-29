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
        prompt = f"""あなたはK8s監視エンジニアです。以下の指示に従い、ツールを活用して状況を調査し、原因と対策を分かりやすい日本語のレポート（1000文字程度）にまとめて出力してください。

# 重要ルールの遵守
- 出力は必ず以下の形式に従ってください。フォーマット以外の文字を直接出力してはいけません。
- 考える過程は必ず詳細に書き下してください。
- 調査が完了しレポートを出力するときは <completed> タグ内に Markdown 形式で詳細なレポート（インシデントの発生状況、エラー内容、対応方針など）を記載してください。決して「最終レポート（完了時のみ）」といった単語だけを出力してはいけません。

# 応答形式（必ずこの通りにすること）
<tasks>
[現在のタスク一覧]
</tasks>
<thinking>
[あなたの考えと分析]
</thinking>

# ツールを使用する場合（必要に応じて）
<mcp_tool_call>
  <name>クライアント名</name>
  <tool_call>
    <name>ツール名</name>
    <parameters>{{"key": "value"}}</parameters>
  </tool_call>
</mcp_tool_call>

# 調査が完了し最終報告を行う場合
<completed>
# インシデント調査レポート
## 概要
(インシデントの概要を記載)
## 詳細
(ログやメトリクスの詳細を記載)
## 対策
(対応方針を記載)
</completed>

利用可能ツール:
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
            return _AgentResponse(tasks="", thinking="", mcp_tool_call=None, completed=response_str.strip()), None

        if t or th or c or mcp_tool_call:
            return _AgentResponse(
                tasks=t.group(1).strip() if t else "",
                thinking=th.group(1).strip() if th else "",
                mcp_tool_call=mcp_tool_call,
                completed=c.group(1).strip() if c else None
            ), None
        return None, "No valid tags found"

    async def generate(self, *, user_instructions: str, mcp_clients):
        messages = [
            *(await self.build_system_prompt(mcp_clients=mcp_clients)),
            {"role": "user", "content": user_instructions}
        ]
        for i in range(10):
            print(f"====== Iteration {i+1} ======")
            try:
                res = await self.openai_client.chat.completions.create(
                    model=self.model_name, 
                    messages=messages,
                    extra_body={"options": {"num_ctx": 8192}}
                )
                content = res.choices[0].message.content
                print(f"DEBUG: AI Output length: {len(content)}")
                messages.append({"role": "assistant", "content": content})
                
                resp, error = self.parse_response(content)
                if error:
                    print(f"DEBUG: Parse Error: {error}")
                    messages.append({"role": "user", "content": "Error: Use tags <tasks>, <thinking>, <completed>."})
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
                        messages.append({"role": "user", "content": f"Error: {e}"})
            except Exception as e:
                print(f"DEBUG: API Error: {e}")
                yield AgentState(tasks="", thinking="", completed=f"Error: {e}")
                return
