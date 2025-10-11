import init # noqa
import os
from langgraph.graph import MessagesState
from langgraph.prebuilt import create_react_agent
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_core.messages import HumanMessage
from langgraph.checkpoint.memory import InMemorySaver
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain_core.runnables import RunnableConfig
from langgraph_supervisor import create_supervisor

from db_tools import insert_report

client = MultiServerMCPClient(
    {
        "mcp-k8s": {
            "transport": "streamable_http",
            "url": os.environ["MCP_K8S_URL"]
        },
        "mcp-grafana": {
            "transport": "streamable_http",
            "url": os.environ["MCP_GRAFANA_URL"]
        },
        "mcp-chart": {
            "transport": "streamable_http",
            "url": os.environ["MCP_CHART_URL"]
        }
    }
)

model = ChatGoogleGenerativeAI(model='gemini-2.5-pro')


async def server_maintenance_agent():
    prompt = """
あなたはサーバー環境のメンテナンスを行う熟練したエンジニアです。
以下のツールを使用して、Kubernetesクラスターの監視、診断、レポート作成を行います。
- `mcp-k8s`: Kubernetesクラスターの情報を取得するためのツール。
- `mcp-grafana`: Grafanaからメトリクス（CPU使用率、メモリ使用率など）を取得するためのツール。
- `mcp-chart`: 取得したデータからグラフを作成するためのツール。
- `insert_report`: 作成したレポートをデータベースに保存するためのツール。

あなたの主なタスクは、Kubernetesノードの健全性を監視し、問題があれば特定し、詳細なレポートを作成することです。
レポートはmarkdown形式で作成してinsert_reportツールを使用してデータベースに保存してください。
ユーザーからの指示に従い、これらのツールを適切に組み合わせてタスクを遂行してください。

"""
    return create_react_agent(
        name="server_maintenance_agent",
        model=model,
        prompt=prompt,
        tools=[*(await client.get_tools()), insert_report],
    )


async def _create_supervisor():
    return create_supervisor(
        model=model,
        agents=[await server_maintenance_agent()],
        prompt=(
            "You are a supervisor agent"
        ),
        add_handoff_back_messages=True,
        output_mode="full_history",
    ).compile(checkpointer=InMemorySaver())


async def main():
    app = await server_maintenance_agent()

    content = """
    KubernetesクラスターのノードのCPU使用率とメモリ使用率を監視し、その結果をグラフ化してレポートを作成してください。
    レポートはデータベースに保存してください。
    """
    inputs = MessagesState(messages=[HumanMessage(content=content)])
    config: RunnableConfig = {'configurable': {'thread_id': '1'}}
    async for chunk in app.astream(input=inputs, config=config):
        print(chunk)
        print("\n\n")


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
