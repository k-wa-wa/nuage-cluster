import 'dart:async';

abstract class K8sService {
  Future<Map<String, String>?> getSecretForUser(String username);
  Future<List<Map<String, dynamic>>> getServiceAccountPermissions(
    String serviceAccountName,
    String namespace,
  );
}
