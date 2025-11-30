import asyncio
import grpc
import argparse
import json
import os
from concurrent import futures

import pb.ai_service_pb2 as ai_service_pb2
import pb.ai_service_pb2_grpc as ai_service_pb2_grpc

from agent import Agent
from agent.mcp_client import MCPClients, MCPClientsConfig


class AIServiceServicer(ai_service_pb2_grpc.AIServiceServicer):
    def __init__(self, mcp_clients_config: MCPClientsConfig):
        self._mcp_clients_config = mcp_clients_config

    async def GenerateReport(self, request: ai_service_pb2.GenerateReportRequest, context):
        mcp_clients = MCPClients(mcp_clients_config=self._mcp_clients_config)

        try:
            # 2. 手動でコンテキストに入る (async with と同じ処理)
            await mcp_clients.__aenter__()

            # 3. 非同期ジェネレータを安全に実行
            async for state in Agent().generate(
                user_instructions=request.instructions,
                mcp_clients=mcp_clients
            ):
                if state["completed"]:
                    yield ai_service_pb2.GenerateReportResponse(
                        tasks=state["tasks"],
                        thinking=state["thinking"],
                        report=ai_service_pb2.Report(
                            title="Kubernetesクラスターの状態レポート",
                            body=state["completed"]
                        )
                    )
                else:
                    yield ai_service_pb2.GenerateReportResponse(
                        tasks=state["tasks"],
                        thinking=state["thinking"],
                    )
        # 4. finally ブロックで確実にリソースを解放する
        #    GeneratorExit や他の例外が発生しても、このブロックは実行される
        finally:
            if mcp_clients:
                # 5. 手動でコンテキストから出る (async with と同じクリーンアップ処理)
                await mcp_clients.__aexit__(None, None, None)


async def serve(mcp_clients_config: MCPClientsConfig):
    server = grpc.aio.server(futures.ThreadPoolExecutor(max_workers=10))
    ai_service_pb2_grpc.add_AIServiceServicer_to_server(AIServiceServicer(mcp_clients_config), server)
    server.add_insecure_port('[::]:5053')
    await server.start()
    print("AI Service server started on port 5053")
    await server.wait_for_termination()


def load_mcp_clients_config() -> MCPClientsConfig:
    parser = argparse.ArgumentParser(description="AI Service gRPC server")
    parser.add_argument(
        "--mcp_clients_config",
        type=str,
        default=None,
        help="Path to the MCP clients configuration JSON file."
    )
    args = parser.parse_args()

    config_data: MCPClientsConfig = {}
    if args.mcp_clients_config:
        if os.path.exists(args.mcp_clients_config):
            with open(args.mcp_clients_config, 'r') as f:
                config_data = json.load(f)
        else:
            print(f"Warning: MCP clients config file not found at {args.mcp_clients_config}. Using empty config.")

    return config_data


if __name__ == '__main__':
    validated_config = load_mcp_clients_config()
    asyncio.run(serve(validated_config))
