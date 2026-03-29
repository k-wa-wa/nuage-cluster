from typing import TypedDict, Literal
import asyncio
from contextlib import AsyncExitStack

from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client


class _MCPClient:
    def __init__(self, *, name: str, mcp_endpoint: str):
        self.name = name
        self.mcp_endpoint = mcp_endpoint
        self._client_session: ClientSession | None = None

    async def connect_in_stack(self, stack: AsyncExitStack):
        """
        AsyncExitStack を使用して接続を確立し、セッションを初期化する。
        """
        # 1. HTTP接続の確立 (streamablehttp_client は ContextManager を返す)
        self._read_stream, self._write_stream, _ = await stack.enter_async_context(
            streamablehttp_client(self.mcp_endpoint)
        )

        # 2. クライアントセッションの作成と開始
        self._client_session = await stack.enter_async_context(
            ClientSession(self._read_stream, self._write_stream)
        )

        # 3. 接続の初期化
        await self._client_session.initialize()

        return self

    def _get_session(self) -> ClientSession:
        if self._client_session is None:
            raise RuntimeError("セッションが初期化されていません。AsyncExitStack 経由で connect_in_stack を呼び出してください。")
        return self._client_session

    async def list_tools(self):
        session = self._get_session()
        return await session.list_tools()

    async def call_tool(self, *, name: str, arguments: dict):
        session = self._get_session()
        return await session.call_tool(name=name, arguments=arguments)


class MCPClientConfig(TypedDict):
    transport: Literal["streamable_http"]
    url: str


MCPClientsConfig = dict[str, MCPClientConfig]


class MCPClients:
    def __init__(self, mcp_clients_config: MCPClientsConfig):
        self._mcp_clients_config = mcp_clients_config
        self._mcp_clients: dict[str, _MCPClient] = {}
        self._stack = AsyncExitStack()

    async def __aenter__(self):
        try:
            for name, config in self._mcp_clients_config.items():
                if config["transport"] == "streamable_http":
                    mcp_client = _MCPClient(
                        name=name,
                        mcp_endpoint=str(config["url"])
                    )
                    # stack に登録して管理
                    await mcp_client.connect_in_stack(self._stack)
                    self._mcp_clients[name] = mcp_client
                else:
                    raise ValueError(f"Unsupported transport: {config['transport']}")
            return self
        except Exception:
            await self._stack.aclose()
            raise

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self._stack.aclose()

    def __iter__(self):
        return iter(self._mcp_clients.values())

    def get_client(self, name: str) -> _MCPClient:
        return self._mcp_clients[name]


if __name__ == "__main__":
    async def main():
        async with AsyncExitStack() as stack:
            # 個別テスト用
            read, write, _ = await stack.enter_async_context(
                streamablehttp_client("http://mcp-k8s.default.svc.cluster.local/mcp")
            )
            async with ClientSession(read, write) as session:
                await session.initialize()
                tools = await session.list_tools()
                print(f"Tools: {tools}")

    asyncio.run(main())
