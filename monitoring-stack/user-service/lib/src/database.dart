import 'dart:io'; // Import for Platform.environment
import 'package:postgres/postgres.dart';
import 'package:logging/logging.dart'; // Use Dart's official logging package

Future<Connection> connectToDatabase(Logger logger) async {
  final host = Platform.environment['DB_HOST'];
  final databaseName = Platform.environment['DB_NAME'];
  final username = Platform.environment['DB_USER'];
  final password = Platform.environment['DB_PASSWORD'];

  if (host == null ||
      databaseName == null ||
      username == null ||
      password == null) {
    logger.severe(
      'Missing one or more database environment variables (DB_HOST, DB_NAME, DB_USER, DB_PASSWORD).',
    ); // Use severe for errors
    throw StateError(
      'Missing database connection environment variables. Please set DB_HOST, DB_NAME, DB_USER, DB_PASSWORD.',
    );
  }

  final port = int.tryParse(Platform.environment['DB_PORT'] ?? '') ?? 5432;

  final connection = await Connection.open(
    Endpoint(
      host: host,
      port: port,
      database: databaseName,
      username: username,
      password: password,
    ),
    settings: ConnectionSettings(
      sslMode: SslMode.disable,
    ), // Disable SSL mode as requested
  );

  try {
    logger.info('Connected to PostgreSQL database: $databaseName'); // Use info
    return connection;
  } catch (e) {
    logger.severe('Failed to connect to PostgreSQL database: $e'); // Use severe
    rethrow;
  }
}
