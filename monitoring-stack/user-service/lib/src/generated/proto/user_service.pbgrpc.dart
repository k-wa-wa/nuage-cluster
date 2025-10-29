// This is a generated file - do not edit.
//
// Generated from proto/user_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'user_service.pb.dart' as $0;

export 'user_service.pb.dart';

/// User Service は、認証、権限キャッシュJWTの発行、およびユーザープロファイル管理を担当するgRPCサービスです。
@$pb.GrpcServiceName('user_service.UserService')
class UserServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  UserServiceClient(super.channel, {super.options, super.interceptors});

  /// Login はユーザー名とパスワードを受け取り、認証を行い、権限情報を含むJWTを発行します。
  $grpc.ResponseFuture<$0.LoginResponse> login(
    $0.LoginRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$login, request, options: options);
  }

  /// GetUserProfile は指定されたユーザーIDのプロファイル情報を取得します。
  $grpc.ResponseFuture<$0.UserProfile> getUserProfile(
    $0.GetUserProfileRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getUserProfile, request, options: options);
  }

  /// UpdateUserProfile はユーザープロファイル情報を更新します。
  $grpc.ResponseFuture<$0.UpdateUserProfileResponse> updateUserProfile(
    $0.UpdateUserProfileRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateUserProfile, request, options: options);
  }

  // method descriptors

  static final _$login = $grpc.ClientMethod<$0.LoginRequest, $0.LoginResponse>(
      '/user_service.UserService/Login',
      ($0.LoginRequest value) => value.writeToBuffer(),
      $0.LoginResponse.fromBuffer);
  static final _$getUserProfile =
      $grpc.ClientMethod<$0.GetUserProfileRequest, $0.UserProfile>(
          '/user_service.UserService/GetUserProfile',
          ($0.GetUserProfileRequest value) => value.writeToBuffer(),
          $0.UserProfile.fromBuffer);
  static final _$updateUserProfile = $grpc.ClientMethod<
          $0.UpdateUserProfileRequest, $0.UpdateUserProfileResponse>(
      '/user_service.UserService/UpdateUserProfile',
      ($0.UpdateUserProfileRequest value) => value.writeToBuffer(),
      $0.UpdateUserProfileResponse.fromBuffer);
}

@$pb.GrpcServiceName('user_service.UserService')
abstract class UserServiceBase extends $grpc.Service {
  $core.String get $name => 'user_service.UserService';

  UserServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.LoginRequest, $0.LoginResponse>(
        'Login',
        login_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.LoginRequest.fromBuffer(value),
        ($0.LoginResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetUserProfileRequest, $0.UserProfile>(
        'GetUserProfile',
        getUserProfile_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetUserProfileRequest.fromBuffer(value),
        ($0.UserProfile value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpdateUserProfileRequest,
            $0.UpdateUserProfileResponse>(
        'UpdateUserProfile',
        updateUserProfile_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UpdateUserProfileRequest.fromBuffer(value),
        ($0.UpdateUserProfileResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.LoginResponse> login_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.LoginRequest> $request) async {
    return login($call, await $request);
  }

  $async.Future<$0.LoginResponse> login(
      $grpc.ServiceCall call, $0.LoginRequest request);

  $async.Future<$0.UserProfile> getUserProfile_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetUserProfileRequest> $request) async {
    return getUserProfile($call, await $request);
  }

  $async.Future<$0.UserProfile> getUserProfile(
      $grpc.ServiceCall call, $0.GetUserProfileRequest request);

  $async.Future<$0.UpdateUserProfileResponse> updateUserProfile_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateUserProfileRequest> $request) async {
    return updateUserProfile($call, await $request);
  }

  $async.Future<$0.UpdateUserProfileResponse> updateUserProfile(
      $grpc.ServiceCall call, $0.UpdateUserProfileRequest request);
}
