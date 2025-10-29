import 'dart:async';
import 'dart:convert'; // For utf8
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:fixnum/fixnum.dart'; // For Int64

import 'generated/proto/user_service.pbgrpc.dart';
import 'k8s_service.dart'; // For Kubernetes service interface

class UserService extends UserServiceBase {
  final Connection _dbConnection;
  final Logger _logger;
  final K8sService _k8sService; // Use the interface
  final String _jwtSecret;

  UserService(
    this._dbConnection,
    this._logger,
    this._k8sService,
    this._jwtSecret,
  );

  @override
  Future<LoginResponse> login(ServiceCall call, LoginRequest request) async {
    _logger.info('Login request for user: ${request.username}');

    // 1. Authenticate user against Kubernetes Secret
    final userSecret = await _k8sService.getSecretForUser(request.username);
    if (userSecret == null) {
      throw GrpcError.unauthenticated('Invalid username or password.');
    }

    final hashedPassword = sha256
        .convert(utf8.encode(request.password))
        .toString();
    if (userSecret['passwordHash'] != hashedPassword) {
      throw GrpcError.unauthenticated('Invalid username or password.');
    }

    final serviceAccountName = userSecret['serviceAccountName'];
    if (serviceAccountName == null) {
      throw GrpcError.internal('Service account not found for user.');
    }

    // 2. Get permissions for the service account
    // Assuming the service account is in the 'default' namespace for now.
    // This might need to be dynamic based on user context in a real application.
    final rawPermissions = await _k8sService.getServiceAccountPermissions(
      serviceAccountName,
      'default', // Assuming 'default' namespace for service accounts
    );

    final permissions = <String>[];
    for (final rule in rawPermissions) {
      final apiGroups = (rule['apiGroups'] as List?)?.cast<String>() ?? [''];
      final resources = (rule['resources'] as List?)?.cast<String>() ?? [];
      final verbs = (rule['verbs'] as List?)?.cast<String>() ?? [];

      for (final apiGroup in apiGroups) {
        for (final resource in resources) {
          for (final verb in verbs) {
            permissions.add(
              '${apiGroup == '' ? 'core' : apiGroup}/$resource:$verb',
            );
          }
        }
      }
    }

    _logger.info('User ${request.username} has permissions: $permissions');

    // 3. Generate JWT
    final jwt = JWT(
      {
        'sub': request.username,
        'iss': 'user-service',
        'aud': ['nuage-cluster'],
        'permissions': permissions,
        'serviceAccountName': serviceAccountName,
      },
      subject: request.username,
      issuer: 'user-service',
      audience: Audience(['nuage-cluster']),
    );
    final token = jwt.sign(
      SecretKey(_jwtSecret),
      expiresIn: const Duration(hours: 1),
    );
    final expiresIn = const Duration(
      hours: 1,
    ).inSeconds; // Recalculate expiresIn

    _logger.info(
      'JWT issued for user: ${request.username}, expires in $expiresIn seconds',
    );

    return LoginResponse(token: token, expiresIn: Int64(expiresIn));
  }

  @override
  Future<UserProfile> getUserProfile(
    ServiceCall call,
    GetUserProfileRequest request,
  ) async {
    _logger.info('GetUserProfile request for user_id: ${request.userId}');

    final results = await _dbConnection.execute(
      Sql.named(
        'SELECT user_id, display_name FROM user_profiles WHERE user_id = @userId',
      ),
      parameters: {'userId': request.userId},
    );

    if (results.isEmpty) {
      throw GrpcError.notFound(
        'User profile not found for user_id: ${request.userId}',
      );
    }

    final row = results.first;
    final userProfile = UserProfile(
      userId: row[0] as String,
      displayName: row[1] as String,
    );

    final notificationSettingsResults = await _dbConnection.execute(
      Sql.named(
        'SELECT setting_key, setting_value FROM user_notification_settings WHERE user_id = @userId',
      ),
      parameters: {'userId': request.userId},
    );

    for (final settingRow in notificationSettingsResults) {
      userProfile.notificationSettings[settingRow[0] as String] =
          settingRow[1] as String;
    }

    _logger.info('Retrieved user profile for user_id: ${request.userId}');
    return userProfile;
  }

  @override
  Future<UpdateUserProfileResponse> updateUserProfile(
    ServiceCall call,
    UpdateUserProfileRequest request,
  ) async {
    _logger.info('UpdateUserProfile request for user_id: ${request.userId}');

    await _dbConnection.runTx((session) async {
      // Update display_name if provided
      if (request.hasDisplayName()) {
        await session.execute(
          Sql.named(
            'UPDATE user_profiles SET display_name = @displayName WHERE user_id = @userId',
          ),
          parameters: {
            'displayName': request.displayName,
            'userId': request.userId,
          },
        );
      }

      // Update notification_settings if provided
      if (request.notificationSettings.isNotEmpty) {
        // Delete existing settings for the user
        await session.execute(
          Sql.named(
            'DELETE FROM user_notification_settings WHERE user_id = @userId',
          ),
          parameters: {'userId': request.userId},
        );

        // Insert new settings
        for (final entry in request.notificationSettings.entries) {
          await session.execute(
            Sql.named(
              'INSERT INTO user_notification_settings (user_id, setting_key, setting_value) VALUES (@userId, @key, @value)',
            ),
            parameters: {
              'userId': request.userId,
              'key': entry.key,
              'value': entry.value,
            },
          );
        }
      }
    });

    _logger.info('Updated user profile for user_id: ${request.userId}');
    return UpdateUserProfileResponse(success: true);
  }
}
