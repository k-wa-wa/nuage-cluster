import test_init  # noqa: F401
import pytest
from unittest.mock import AsyncMock, MagicMock
from openai.types.chat import ChatCompletionMessage

from src.agent import Agent
from src.agent.mcp_client import MCPClients, _MCPClient, MCPClientsConfig


class MockChatCompletion:
    def __init__(self, content: str):
        self.choices = [
            MagicMock(
                message=ChatCompletionMessage(
                    role="assistant",
                    content=content,
                    function_call=None,
                    tool_calls=None,
                )
            )
        ]


def create_mock_openai_client(responses: list[str]):

    mock_client = MagicMock()
    mock_client.chat.completions.create.side_effect = [
        MockChatCompletion(response) for response in responses
    ]
    return mock_client


class MockMCPClient(_MCPClient):
    def __init__(self, name: str, mcp_endpoint: str):
        super().__init__(name=name, mcp_endpoint=mcp_endpoint)
        self.list_tools = AsyncMock(return_value=MagicMock(tools=[]))
        self.call_tool = AsyncMock(return_value="tool_response_data")

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        pass


@pytest.fixture
def mock_mcp_clients():
    config: MCPClientsConfig = {
        "mcp_client_1": {
            "transport": "streamable_http",
            "url": "http://mock-url/mcp"
        },
    }
    mcp_clients = MCPClients(config)
    mcp_clients._mcp_clients["mcp_client_1"] = MockMCPClient(
        name="mcp_client_1",
        mcp_endpoint="http://mock-url/mcp"
    )
    return mcp_clients


@pytest.mark.asyncio
async def test_agent_generate_completed_task(mock_mcp_clients):
    mock_responses = [
        """<response>
    <tasks>
1. [x] レポートを生成する
    </tasks>
    <thinking>全てのタスクが完了しました。レポートを生成します。</thinking>
    <completed>
# Kubernetesクラスターの状態レポート
テストレポートの本文です。
    </completed>
</response>"""
    ]
    mock_openai_client = create_mock_openai_client(mock_responses)
    agent = Agent(openai_client=mock_openai_client)

    user_instructions = "テストレポートを生成してください。"

    states = []
    async for state in agent.generate(user_instructions=user_instructions, mcp_clients=mock_mcp_clients):
        states.append(state)

    assert len(states) == 1
    assert "1. [x] レポートを生成する" in states[0]["tasks"]
    assert "テストレポートの本文です。" in states[0]["completed"]
    mock_openai_client.chat.completions.create.assert_called_once()


@pytest.mark.asyncio
async def test_agent_generate_tool_call(mock_mcp_clients):
    mock_responses = [
        """<response>
    <tasks>
1. [ ] ツールを呼び出す
2. [ ] レポートを生成する
    </tasks>
    <thinking>ツールを呼び出して情報を取得します。</thinking>
    <mcp_tool_call>
        <name>mcp_client_1</name>
        <tool_call>
            <name>call_tool</name>
            <parameters>
                {
                    "param1": "value1"
                }
            </parameters>
        </tool_call>
    </mcp_tool_call>
</response>""",
        """<response>
    <tasks>
1. [x] ツールを呼び出す
2. [ ] レポートを生成する
    </tasks>
    <thinking>ツール呼び出しが完了しました。レポートを生成します。</thinking>
    <completed>
# Kubernetesクラスターの状態レポート
ツール呼び出しの結果を含むテストレポートです。
    </completed>
</response>"""
    ]
    mock_openai_client = create_mock_openai_client(mock_responses)
    agent = Agent(openai_client=mock_openai_client)

    user_instructions = "ツールを呼び出してレポートを生成してください。"

    states = []
    async for state in agent.generate(user_instructions=user_instructions, mcp_clients=mock_mcp_clients):
        states.append(state)

    assert len(states) == 2
    assert "ツールを呼び出して情報を取得します。" in states[0]["thinking"]
    assert mock_mcp_clients.get_client("mcp_client_1").call_tool.called
    assert "ツール呼び出しの結果を含むテストレポートです。" in states[1]["completed"]
    assert mock_openai_client.chat.completions.create.call_count == 2


@pytest.mark.asyncio
async def test_agent_generate_parse_error(mock_mcp_clients):
    mock_responses = [
        """`<response>
    <tasks>
1. [ ] 不正なレスポンス
    </tasks>
    <thinking>不正なレスポンスを生成します。</thinking>
</response>""",
        """<response>
    <tasks>
1. [x] 不正なレスポンスを修正
    </tasks>
    <thinking>不正なレスポンスを修正しました。</thinking>
    <completed>
# Kubernetesクラスターの状態レポート
不正なレスポンス修正後のレポートです。
    </completed>
</response>"""
    ]
    mock_openai_client = create_mock_openai_client(mock_responses)
    agent = Agent(openai_client=mock_openai_client)

    user_instructions = "不正なレスポンスを含むレポートを生成してください。"

    states = []
    async for state in agent.generate(user_instructions=user_instructions, mcp_clients=mock_mcp_clients):
        states.append(state)

    assert len(states) == 1
    assert "不正なレスポンスを修正しました。" in states[0]["thinking"]
    assert mock_openai_client.chat.completions.create.call_count == 2
    # 最初のレスポンスはパースエラーになり、修正を促すメッセージが追加されることを確認
    assert ("レスポンスの解析に失敗しました" in
            mock_openai_client.chat.completions.create.call_args_list[1].kwargs["messages"][-1]["content"])
