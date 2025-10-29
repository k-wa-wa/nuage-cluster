import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart'; // Use Dart's official logging package
import 'package:postgres/postgres.dart';

import 'package:user_service/src/user_service.dart';
import 'package:user_service/src/database.dart';
import 'package:user_service/src/k8s_service.dart'; // Import the interface
import 'package:user_service/src/k8s_mock.dart'; // Import the mock implementation
import 'package:user_service/src/k8s_service_impl.dart'; // Import the real implementation

Future<void> main(List<String> args) async {
  // Configure logging
  Logger.root.level = Level.ALL; // Set to ALL to capture all log levels
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
    if (record.error != null) {
      print(record.error);
    }
    if (record.stackTrace != null) {
      print(record.stackTrace);
    }
  });

  final logger = Logger('UserService'); // Create a logger instance

  // Database connection
  late Connection dbConnection;
  try {
    dbConnection = await connectToDatabase(logger);
  } catch (e) {
    logger.severe('Failed to connect to database: $e'); // Use severe for errors
    stderr.writeln(
      'Error: Failed to connect to database. Exiting.',
    ); // Ensure output to console
    //exit(1);
  }

  // JWT Secret (for mocking purposes)
  // In a real application, this should be loaded securely from environment variables or a secret management system.
  const jwtSecret = 'your-super-secret-jwt-key';

  // Determine which K8sService implementation to use
  final bool k8sMockEnabled =
      Platform.environment['K8S_MOCK_ENABLED'] == 'true';
  late K8sService k8sService;

  if (k8sMockEnabled) {
    logger.info('Using K8sMockService'); // Use info for informational messages
    k8sService = K8sMock(logger);
  } else {
    logger.info('Using K8sServiceImpl'); // Use info for informational messages
    k8sService = K8sServiceImpl(logger);
  }

  final server = Server.create(
    services: [UserService(dbConnection, logger, k8sService, jwtSecret)],
    codecRegistry: CodecRegistry(codecs: [GzipCodec(), IdentityCodec()]),
  );

  final port = int.parse(Platform.environment['PORT'] ?? '5051');

  try {
    logger.info('Server listening on port ${server.port}...'); // Use info
    await server.serve(port: port);
  } catch (e) {
    logger.severe('Server failed to start: $e'); // Use severe
    stderr.writeln(
      'Error: Server failed to start. Exiting.',
    ); // Ensure output to console
    exit(1);
  }

  // Handle server shutdown
  ProcessSignal.sigterm.watch().listen((signal) async {
    logger.info('Received SIGTERM. Shutting down server...'); // Use info
    await server.shutdown();
    await dbConnection.close();
    logger.info('Server shut down.'); // Use info
    exit(0);
  });

  ProcessSignal.sigint.watch().listen((signal) async {
    logger.info('Received SIGINT. Shutting down server...'); // Use info
    await server.shutdown();
    await dbConnection.close();
    logger.info('Server shut down.'); // Use info
    exit(0);
  });
}
