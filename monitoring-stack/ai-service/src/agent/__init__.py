import os
import json
from typing import Iterable, TypedDict

from openai import OpenAI
from openai.types.chat import (
    ChatCompletionMessageParam, ChatCompletionSystemMessageParam,
    ChatCompletionAssistantMessageParam, ChatCompletionUserMessageParam
)
from dotenv import load_dotenv
import xml.etree.ElementTree as ET
from pydantic import BaseModel, ValidationError

from agent.mcp_client import MCPClients

load_dotenv(".env")


type ParseErrorMessage = str


class _AgentResponse_McpToolCall_ToolCall(BaseModel):
    name: str
    parameters: str  # JSON string


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
    def __init__(self, openai_client: OpenAI | None = None):
        self.openai_client = openai_client if openai_client else OpenAI(
            api_key=os.getenv("OPENAI_API_KEY"),
            base_url=os.getenv("OPENAI_BASE_URL"),
        )

    async def build_system_prompt(
        self, *, mcp_clients: MCPClients
    ) -> Iterable[ChatCompletionSystemMessageParam]:
        prompt = f"""
あなたはkubernetesクラスターの監視をするエンジニアです。ユーザーの指示に従って、kubernetesクラスターの状態に関するレポートを生成してください。
レポートは<completed></completed>タグ内に出力してください。

# ツール使用
あなたは必要に応じて以下のツールを使用して、kubernetesクラスターの状態を調査できます。

## mcp_tool_call
mcpクライアントを使用して、kubernetesクラスターの情報を取得します。
- 存在しないツールは絶対に使用しないでください。
- parametersはJSON形式で指定してください。

例:
<mcp_tool_call>
    <name>mcp_client_1</name>
    <tool_call>
        <name>list_tools</name>
        <parameters>
            {{
                "param1": "value1",
                "param2": "value2"
            }}
        </parameters>
    </tool_call>
</mcp_tool_call>

以下のmcpクライアントが利用可能です。

{[f"### {c.name}\n{await c.list_tools()}\n" for c in mcp_clients]}

# ゴール
与えられたタスクを明確なステップに分解し、反復的にタスクを実行します。

1. ユーザーの指示を分析し、明確で達成可能なサブタスクに分解します。
2. 必要に応じてツールを利用しながら、各サブタスクを順番に実行します。
3. 各応答では<tasks></tasks>タグで現在のタスク状況を提供し、<thinking></thinking>タグで次に行うステップを説明してください。
4. タスクを完了したら、<completed></completed>タグで完了を宣言します。

# 出力形式
必ずxml形式で出力してください。```等で囲わず、xmlタグのみで出力してください。
tasksやcompletedタグ内の内容はmarkdown形式で記述してください。
markdownをxmlタグ内に含める際には、不要なタブやスペースを入れないでください。

## 例: ツール呼び出し

<response>
    <tasks>
1. [ ] ノードとポッドの一覧を取得する
2. [ ] 各ノードとポッドの状態を確認する
3. [ ] 各ノードとポッドのリソース使用率を収集する
4. [ ] ネットワークの状態を確認する
5. [ ] イベントログを収集する
6. [ ] レポートを生成する
    </tasks>

    <thinking>まず、ノードとポッドの一覧を取得します。</thinking>

    <tool_call>
        <name>execute_command</name>
        <parameters>
            <command>kubectl get nodes -o wide</command>
        </parameters>
    </tool_call>
</response>

## 例: タスク完了

<response>
    <tasks>
省略
    </tasks>
    <thinking>全てのタスクが完了しました。レポートを生成します。</thinking>
    <completed>
# Kubernetesクラスターの状態レポート
以下は、現在のKubernetesクラスターの状態に関する詳細なレポートです。
省略
    </completed>
</response>

"""
        return [
            {
                "role": "system",
                "content": prompt,
            },
        ]

    def build_user_prompt(self, *, user_instructions: str) -> Iterable[ChatCompletionUserMessageParam]:
        return [
            {
                "role": "user",
                "content": f"{user_instructions}",
            },
        ]

    def parse_response(
        self, response_str: str
    ) -> tuple[_AgentResponse, None] | tuple[None, ParseErrorMessage]:
        try:
            response_xml = ET.fromstring(response_str)
        except ET.ParseError as e:
            return None, f"XMLのパースに失敗しました: {e}"

        try:
            agent_response = _AgentResponse.model_validate({
                "tasks": response_xml.findtext("tasks"),
                "thinking": response_xml.findtext("thinking"),
                "mcp_tool_call": _AgentResponse_McpToolCall.model_validate({
                    "name": response_xml.findtext("mcp_tool_call/name"),
                    "tool_call": _AgentResponse_McpToolCall_ToolCall.model_validate({
                        "name": response_xml.findtext("mcp_tool_call/tool_call/name"),
                        "parameters": response_xml.findtext("mcp_tool_call/tool_call/parameters"),
                    }),
                }) if response_xml.find("mcp_tool_call") is not None else None,
                "completed": response_xml.findtext("completed"),
            })
        except ValidationError as e:
            return None, f"レスポンスの解析に失敗しました: {e}"

        return agent_response, None

    async def generate(self, *, user_instructions: str, mcp_clients: MCPClients):
        messages: Iterable[ChatCompletionMessageParam] = [
            *(await self.build_system_prompt(mcp_clients=mcp_clients)),
            *self.build_user_prompt(user_instructions=user_instructions),
        ]

        for i in range(30):
            print("====== New Iteration ======")
            print(messages)
            res_content = self.openai_client.chat.completions.create(
                model="gemini-2.5-flash",
                messages=messages
            ).choices[0].message.content
            messages: Iterable[ChatCompletionMessageParam] = [
                *messages,
                ChatCompletionAssistantMessageParam(
                    name="agent",
                    role="assistant",
                    content=res_content
                )
            ]
            print(res_content)
            agent_response, parse_error = self.parse_response(f"{res_content}")
            if parse_error or not agent_response:
                messages.append(ChatCompletionUserMessageParam(
                    role="user",
                    content=f"レスポンスの解析に失敗しました。正しく解析できるようエラーを修正してください。\n{parse_error}"
                ))
                continue

            state = AgentState(
                tasks=agent_response.tasks,
                thinking=agent_response.thinking,
                completed=agent_response.completed,
            )
            yield state

            if state["completed"] is not None:
                print("====== Task Completed ======")
                return

            if mcp_tool_call := agent_response.mcp_tool_call:
                try:
                    mcp_client = mcp_clients.get_client(mcp_tool_call.name)
                except KeyError:
                    messages.append(ChatCompletionUserMessageParam(
                        role="user",
                        content=f"Invalid tool_name: '{mcp_tool_call.name}'"
                    ))
                    continue
                tool_name = mcp_tool_call.tool_call.name
                tool_parameters = mcp_tool_call.tool_call.parameters
                try:
                    tool_response = await mcp_client.call_tool(
                        name=tool_name,
                        arguments=json.loads(tool_parameters) if tool_parameters else {},
                    )
                    messages.append(ChatCompletionUserMessageParam(
                        role="user",
                        content=f"{tool_response}"
                    ))
                except Exception as e:
                    messages.append(ChatCompletionUserMessageParam(
                        role="user",
                        content=f"Tool call failed: {e}"
                    ))


if __name__ == '__main__':
    import asyncio

    async def main():
        user_instructions = "ノード、ポッドの一覧とその状態、リソース使用率（CPU、メモリ、ディスク）、\
            ネットワークの状態、イベントログなどを含むkubernetesクラスターの現在の状態に関する詳細なレポートを生成してください。"

        async with MCPClients(
            mcp_clients_config={
                "mcp_client_1": {
                    "transport": "streamable_http",
                    "url": "http://mcp-k8s.default.svc.cluster.local/mcp"
                },
            }
        ) as mcp_clients:
            async for state in Agent().generate(
                user_instructions=user_instructions,
                mcp_clients=mcp_clients
            ):
                print(state)

    asyncio.run(main())
