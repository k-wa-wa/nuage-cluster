import asyncio
import grpc
from concurrent import futures

import pb.ai_service_pb2 as ai_service_pb2
import pb.ai_service_pb2_grpc as ai_service_pb2_grpc

from agent import Agent, MCPClients


class AIServiceServicer(ai_service_pb2_grpc.AIServiceServicer):

    async def GenerateReport(self, request: ai_service_pb2.GenerateReportRequest, context):
        async with MCPClients(
            mcp_clients_config={
                "mcp_client_1": {
                    "transport": "streamable_http",
                    "url": "http://mcp-k8s.default.svc.cluster.local/mcp"
                },
            }
        ) as mcp_clients:
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
                    return
                else:
                    yield ai_service_pb2.GenerateReportResponse(
                        tasks=state["tasks"],
                        thinking=state["thinking"],
                    )


async def serve():
    server = grpc.aio.server(futures.ThreadPoolExecutor(max_workers=10))
    ai_service_pb2_grpc.add_AIServiceServicer_to_server(AIServiceServicer(), server)
    server.add_insecure_port('[::]:5053')
    await server.start()
    print("AI Service server started on port 5053")
    await server.wait_for_termination()


if __name__ == '__main__':
    asyncio.run(serve())
