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

from mcp_client import MCPClients

load_dotenv(".env")

client = OpenAI(
    api_key=os.getenv("OPENAI_API_KEY"),
    base_url=os.getenv("OPENAI_BASE_URL"),
)


class AgentState(TypedDict):
    tasks: str
    thinking: str
    completed: str | None


class Agent:
    async def build_system_prompt(
        self, *, mcp_clients: MCPClients
    ) -> Iterable[ChatCompletionSystemMessageParam]:
        prompt = f"""
あなたはkubernetesクラスターの監視をするエンジニアです。ユーザーの指示に従って、kubernetesクラスターの状態に関するレポートを生成してください。

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

例:

<response>
    <tasks>
        - [ ] ノードとポッドの一覧を取得する
        - [ ] 各ノードとポッドの状態を確認する
        - [ ] 各ノードとポッドのリソース使用率を収集する
        - [ ] ネットワークの状態を確認する
        - [ ] イベントログを収集する
        - [ ] レポートを生成する
    </tasks>

    <thinking>まず、ノードとポッドの一覧を取得します。</thinking>

    <tool_call>
        <name>execute_command</name>
        <parameters>
            <command>kubectl get nodes -o wide</command>
        </parameters>
    </tool_call>
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

    async def generate(self, *, user_instructions: str, mcp_clients: MCPClients):
        messages: Iterable[ChatCompletionMessageParam] = [
            *(await self.build_system_prompt(mcp_clients=mcp_clients)),
            *self.build_user_prompt(user_instructions=user_instructions),
        ]

        for i in range(30):
            res_content = client.chat.completions.create(
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
            response = ET.fromstring(f"{res_content}")

            state = AgentState(
                tasks=response.findtext("tasks", default=""),
                thinking=response.findtext("thinking", default=""),
                completed=response.findtext("completed"),
            )
            yield state

            if state["completed"] is not None:
                print("====== Task Completed ======")
                return

            if response.find("mcp_tool_call") is not None:
                mcp_client = None
                if mcp_name := response.findtext("mcp_tool_call/name"):
                    mcp_client = mcp_clients.get_client(mcp_name)
                if mcp_client is None:
                    messages.append(ChatCompletionUserMessageParam(
                        role="user",
                        content=f"Invalid tool_name: '{mcp_name}'"
                    ))
                    continue

                if not (tool_name := response.findtext("mcp_tool_call/tool_call/name")):
                    messages.append(ChatCompletionUserMessageParam(
                        role="user",
                        content="tool_name is required."
                    ))
                    continue
                tool_parameters = response.findtext("mcp_tool_call/tool_call/parameters")
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
                        content=f"Tool call failed: {str(e)}"
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
