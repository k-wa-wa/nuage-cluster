import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart'; // Use Dart's official logging package
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart'; // Import for IOClient
import 'k8s_service.dart'; // Import the abstract class

class K8sServiceImpl implements K8sService {
  final Logger _logger;
  final String _k8sApiUrl;
  final String _k8sToken;
  final http.Client _httpClient;

  K8sServiceImpl(this._logger)
    : _k8sApiUrl = _getK8sApiUrl(_logger),
      _k8sToken = _getK8sToken(_logger),
      _httpClient = _createHttpClient(_logger, _getCaCertPath());

  static String _getK8sApiUrl(Logger logger) {
    final k8sServiceHost = Platform.environment['KUBERNETES_SERVICE_HOST'];
    final k8sServicePort = Platform.environment['KUBERNETES_SERVICE_PORT'];

    if (k8sServiceHost == null || k8sServicePort == null) {
      logger.severe(
        'KUBERNETES_SERVICE_HOST or KUBERNETES_SERVICE_PORT not found in environment.',
      );
      throw StateError(
        'KUBERNETES_SERVICE_HOST or KUBERNETES_SERVICE_PORT not set.',
      );
    }
    return 'https://$k8sServiceHost:$k8sServicePort';
  }

  static String _getK8sToken(Logger logger) {
    const k8sTokenPath = '/var/run/secrets/kubernetes.io/serviceaccount/token';
    try {
      final k8sToken = File(k8sTokenPath).readAsStringSync();
      if (k8sToken.isEmpty) {
        logger.severe('K8s service account token file is empty: $k8sTokenPath');
        throw StateError('K8s service account token file is empty.');
      }
      return k8sToken.trim();
    } catch (e) {
      logger.severe(
        'Failed to read K8s service account token from $k8sTokenPath: $e',
      );
      throw StateError('Failed to read K8s service account token.');
    }
  }

  static String _getCaCertPath() {
    return '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt';
  }

  static http.Client _createHttpClient(Logger logger, String caCertPath) {
    final securityContext = SecurityContext.defaultContext;
    try {
      securityContext.setTrustedCertificates(caCertPath);
    } catch (e) {
      logger.severe('Error loading CA certificate from $caCertPath: $e');
      // Depending on the desired behavior, you might want to throw an error
      // or proceed with a client that doesn't trust the custom CA.
      // For now, we'll just log and proceed, which might lead to SSL errors.
    }
    final httpClient = HttpClient(context: securityContext);
    return IOClient(httpClient);
  }

  @override
  Future<Map<String, String>?> getSecretForUser(String username) async {
    _logger.info('Real K8s: Fetching secret for user: $username'); // Use info
    final url = Uri.parse(
      '$_k8sApiUrl/api/v1/namespaces/default/secrets/$username-secret',
    );
    final response = await _httpClient.get(
      url,
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $_k8sToken',
        HttpHeaders.acceptHeader: 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final secretData = data['data'] as Map<String, dynamic>;
      return secretData.map(
        (key, value) => MapEntry(key, utf8.decode(base64.decode(value))),
      );
    } else {
      _logger.severe(
        'Failed to fetch secret for user $username: ${response.statusCode} ${response.body}',
      ); // Use severe for errors
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getServiceAccountPermissions(
    String serviceAccountName,
    String namespace,
  ) async {
    _logger.info(
      'K8s: Getting permissions for service account: $serviceAccountName in namespace: $namespace',
    );

    final allRules = <Map<String, dynamic>>{};

    // 1. Get RoleBindings in the specified namespace
    final roleBindingsUrl = Uri.parse(
      '$_k8sApiUrl/apis/rbac.authorization.k8s.io/v1/namespaces/$namespace/rolebindings',
    );
    final roleBindingsResponse = await _httpClient.get(
      roleBindingsUrl,
      headers: {HttpHeaders.authorizationHeader: 'Bearer $_k8sToken'},
    );

    if (roleBindingsResponse.statusCode == 200) {
      final roleBindingsData = json.decode(roleBindingsResponse.body);
      for (final item in roleBindingsData['items'] ?? []) {
        final subjects = item['subjects'] ?? [];
        for (final subject in subjects) {
          if (subject['kind'] == 'ServiceAccount' &&
              subject['name'] == serviceAccountName &&
              (subject['namespace'] == null ||
                  subject['namespace'] == namespace)) {
            final roleRef = item['roleRef'];
            if (roleRef != null && roleRef['kind'] == 'Role') {
              // Fetch the Role
              final roleUrl = Uri.parse(
                '$_k8sApiUrl/apis/rbac.authorization.k8s.io/v1/namespaces/$namespace/roles/${roleRef['name']}',
              );
              final roleResponse = await _httpClient.get(
                roleUrl,
                headers: {HttpHeaders.authorizationHeader: 'Bearer $_k8sToken'},
              );
              if (roleResponse.statusCode == 200) {
                final roleData = json.decode(roleResponse.body);
                for (final rule in roleData['rules'] ?? []) {
                  allRules.add(rule);
                }
              } else {
                _logger.warning(
                  'K8s: Failed to fetch Role ${roleRef['name']}: ${roleResponse.statusCode} ${roleResponse.body}',
                );
              }
            } else if (roleRef != null && roleRef['kind'] == 'ClusterRole') {
              // Fetch the ClusterRole (can be bound by RoleBinding)
              final clusterRoleUrl = Uri.parse(
                '$_k8sApiUrl/apis/rbac.authorization.k8s.io/v1/clusterroles/${roleRef['name']}',
              );
              final clusterRoleResponse = await _httpClient.get(
                clusterRoleUrl,
                headers: {HttpHeaders.authorizationHeader: 'Bearer $_k8sToken'},
              );
              if (clusterRoleResponse.statusCode == 200) {
                final clusterRoleData = json.decode(clusterRoleResponse.body);
                for (final rule in clusterRoleData['rules'] ?? []) {
                  allRules.add(rule);
                }
              } else {
                _logger.warning(
                  'K8s: Failed to fetch ClusterRole ${roleRef['name']}: ${clusterRoleResponse.statusCode} ${clusterRoleResponse.body}',
                );
              }
            }
          }
        }
      }
    } else {
      _logger.warning(
        'K8s: Failed to list RoleBindings in namespace $namespace: ${roleBindingsResponse.statusCode} ${roleBindingsResponse.body}',
      );
    }

    // 2. Get ClusterRoleBindings (cluster-wide)
    final clusterRoleBindingsUrl = Uri.parse(
      '$_k8sApiUrl/apis/rbac.authorization.k8s.io/v1/clusterrolebindings',
    );
    final clusterRoleBindingsResponse = await _httpClient.get(
      clusterRoleBindingsUrl,
      headers: {HttpHeaders.authorizationHeader: 'Bearer $_k8sToken'},
    );

    if (clusterRoleBindingsResponse.statusCode == 200) {
      final clusterRoleBindingsData = json.decode(
        clusterRoleBindingsResponse.body,
      );
      for (final item in clusterRoleBindingsData['items'] ?? []) {
        final subjects = item['subjects'] ?? [];
        for (final subject in subjects) {
          if (subject['kind'] == 'ServiceAccount' &&
              subject['name'] == serviceAccountName &&
              (subject['namespace'] == null ||
                  subject['namespace'] == namespace)) {
            final roleRef = item['roleRef'];
            if (roleRef != null && roleRef['kind'] == 'ClusterRole') {
              // Fetch the ClusterRole
              final clusterRoleUrl = Uri.parse(
                '$_k8sApiUrl/apis/rbac.authorization.k8s.io/v1/clusterroles/${roleRef['name']}',
              );
              final clusterRoleResponse = await _httpClient.get(
                clusterRoleUrl,
                headers: {HttpHeaders.authorizationHeader: 'Bearer $_k8sToken'},
              );
              if (clusterRoleResponse.statusCode == 200) {
                final clusterRoleData = json.decode(clusterRoleResponse.body);
                for (final rule in clusterRoleData['rules'] ?? []) {
                  allRules.add(rule);
                }
              } else {
                _logger.warning(
                  'K8s: Failed to fetch ClusterRole ${roleRef['name']}: ${clusterRoleResponse.statusCode} ${clusterRoleResponse.body}',
                );
              }
            }
          }
        }
      }
    } else {
      _logger.warning(
        'K8s: Failed to list ClusterRoleBindings: ${clusterRoleBindingsResponse.statusCode} ${clusterRoleBindingsResponse.body}',
      );
    }

    return allRules.toList();
  }
}
