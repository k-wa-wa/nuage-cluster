import 'dart:async';
import 'package:logging/logging.dart'; // Use Dart's official logging package
import 'k8s_service.dart'; // Import the abstract class

class K8sMock implements K8sService {
  final Logger _logger;

  K8sMock(this._logger);

  // Mock user secrets
  final Map<String, Map<String, String>> _mockUserSecrets = {
    'testuser': {
      'passwordHash':
          'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3', // SHA256 of 'password'
      'serviceAccountName': 'testuser-sa',
    },
    'admin': {
      'passwordHash':
          '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918', // SHA256 of 'adminpass'
      'serviceAccountName': 'admin-sa',
    },
  };

  @override
  Future<Map<String, String>?> getSecretForUser(String username) async {
    _logger.info('Mock K8s: Fetching secret for user: $username'); // Use info
    return Future.value(_mockUserSecrets[username]);
  }

  @override
  Future<List<Map<String, dynamic>>> getServiceAccountPermissions(
    String serviceAccountName,
    String namespace,
  ) async {
    _logger.info(
      'Mock K8s: Getting permissions for service account: $serviceAccountName in namespace: $namespace',
    );

    // Return mock permissions based on serviceAccountName
    if (serviceAccountName == 'testuser-sa') {
      return Future.value([
        {
          'apiGroups': [''],
          'resources': ['pods'],
          'verbs': ['get', 'list'],
        },
        {
          'apiGroups': ['ai-reporter.myapp.com'],
          'resources': ['reports'],
          'verbs': ['get', 'list'],
        },
      ]);
    } else if (serviceAccountName == 'admin-sa') {
      return Future.value([
        {
          'apiGroups': [''],
          'resources': ['*'],
          'verbs': ['*'],
        },
        {
          'apiGroups': ['apps'],
          'resources': ['deployments'],
          'verbs': ['get', 'list', 'watch', 'create', 'update', 'delete'],
        },
        {
          'apiGroups': ['ai-reporter.myapp.com'],
          'resources': ['*'],
          'verbs': ['*'],
        },
      ]);
    }
    return Future.value([]);
  }
}
