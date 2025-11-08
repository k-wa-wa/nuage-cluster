import grpc
from concurrent import futures

import pb.ai_service_pb2 as ai_service_pb2
import pb.ai_service_pb2_grpc as ai_service_pb2_grpc


class AIServiceServicer(ai_service_pb2_grpc.AIServiceServicer):

    def GenerateReport(self, request, context):
        return ai_service_pb2.GenerateReportResponse()


def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    ai_service_pb2_grpc.add_AIServiceServicer_to_server(AIServiceServicer(), server)
    server.add_insecure_port('[::]:5053')
    server.start()
    print("AI Service server started on port 5053")
    server.wait_for_termination()


if __name__ == '__main__':
    serve()
