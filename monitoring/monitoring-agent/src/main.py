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

model = ChatGoogleGenerativeAI(model=os.environ["GEMINI_MODEL"])


async def k8s_report_agent():
    return create_react_agent(
        name="k8s_report_agent",
        model=model,
        prompt=os.environ["K8S_REPORT_AGENT_PROMPT"],
        tools=[*(await client.get_tools()), insert_report],
    )


async def _create_supervisor():
    return create_supervisor(
        model=model,
        agents=[await k8s_report_agent()],
        prompt=(
            "You are a supervisor agent"
        ),
        add_handoff_back_messages=True,
        output_mode="full_history",
    ).compile(checkpointer=InMemorySaver())


async def main():
    app = await k8s_report_agent()

    content = os.environ["INPUT_PROMPT"]
    inputs = MessagesState(messages=[HumanMessage(content=content)])
    config: RunnableConfig = {'configurable': {'thread_id': '1'}}
    async for chunk in app.astream(input=inputs, config=config):
        print(chunk)
        print("\n")


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
