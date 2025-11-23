from typing import TypedDict, Literal

from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client


class _MCPClient:
    def __init__(self, *, name: str, mcp_endpoint: str):
        self.name = name
        self.mcp_endpoint = mcp_endpoint
        self._connection_manager = streamablehttp_client(self.mcp_endpoint)
        self._client_session: ClientSession | None = None

    async def __aenter__(self):
        """
        async with ブロックに入るときに呼び出される。
        接続の確立とセッションの初期化を行う。
        """
        # 1. HTTP接続の確立 (streamablehttp_client は ContextManager を返す)
        self._read_stream, self._write_stream, _ = await self._connection_manager.__aenter__()

        # 2. クライアントセッションの作成と開始
        self._client_session = ClientSession(self._read_stream, self._write_stream)
        await self._client_session.__aenter__()

        # 3. 接続の初期化
        await self._client_session.initialize()

        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        """
        async with ブロックを抜けるときに呼び出される。
        セッションと接続の終了処理を行う。
        """
        # 1. クライアントセッションの終了
        if self._client_session:
            await self._client_session.__aexit__(exc_type, exc_val, exc_tb)

        # 2. HTTP接続の終了
        await self._connection_manager.__aexit__(exc_type, exc_val, exc_tb)
        self._client_session = None

    def _get_session(self) -> ClientSession:
        if self._client_session is None:
            raise RuntimeError("セッションが初期化されていません。クラスを async with で使用してください。")
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

    async def __aenter__(self):
        for name, config in self._mcp_clients_config.items():
            if config["transport"] == "streamable_http":
                mcp_client = _MCPClient(
                    name=name,
                    mcp_endpoint=str(config["url"])
                )
                await mcp_client.__aenter__()
                self._mcp_clients[name] = mcp_client
            else:
                raise ValueError(f"Unsupported transport: {config['transport']}")
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        for mcp_client in self._mcp_clients.values():
            await mcp_client.__aexit__(exc_type, exc_val, exc_tb)

    def __iter__(self):
        return iter(self._mcp_clients.values())

    def get_client(self, name: str) -> _MCPClient:
        return self._mcp_clients[name]


if __name__ == "__main__":
    import asyncio

    async def main():
        async with _MCPClient(
            name="mcp_client_1",
            mcp_endpoint="http://mcp-k8s.default.svc.cluster.local/mcp"
        ) as mcp_client_1:
            mcp_client_1_list = await mcp_client_1.list_tools()
            print(f"MCP Client Tools: {[t for t in mcp_client_1_list.tools]}")

    asyncio.run(main())
