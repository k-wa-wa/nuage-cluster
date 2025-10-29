// This is a generated file - do not edit.
//
// Generated from proto/user_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use loginRequestDescriptor instead')
const LoginRequest$json = {
  '1': 'LoginRequest',
  '2': [
    {'1': 'username', '3': 1, '4': 1, '5': 9, '10': 'username'},
    {'1': 'password', '3': 2, '4': 1, '5': 9, '10': 'password'},
  ],
};

/// Descriptor for `LoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loginRequestDescriptor = $convert.base64Decode(
    'CgxMb2dpblJlcXVlc3QSGgoIdXNlcm5hbWUYASABKAlSCHVzZXJuYW1lEhoKCHBhc3N3b3JkGA'
    'IgASgJUghwYXNzd29yZA==');

@$core.Deprecated('Use loginResponseDescriptor instead')
const LoginResponse$json = {
  '1': 'LoginResponse',
  '2': [
    {'1': 'token', '3': 1, '4': 1, '5': 9, '10': 'token'},
    {'1': 'expires_in', '3': 2, '4': 1, '5': 3, '10': 'expiresIn'},
  ],
};

/// Descriptor for `LoginResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loginResponseDescriptor = $convert.base64Decode(
    'Cg1Mb2dpblJlc3BvbnNlEhQKBXRva2VuGAEgASgJUgV0b2tlbhIdCgpleHBpcmVzX2luGAIgAS'
    'gDUglleHBpcmVzSW4=');

@$core.Deprecated('Use getUserProfileRequestDescriptor instead')
const GetUserProfileRequest$json = {
  '1': 'GetUserProfileRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `GetUserProfileRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getUserProfileRequestDescriptor =
    $convert.base64Decode(
        'ChVHZXRVc2VyUHJvZmlsZVJlcXVlc3QSFwoHdXNlcl9pZBgBIAEoCVIGdXNlcklk');

@$core.Deprecated('Use updateUserProfileRequestDescriptor instead')
const UpdateUserProfileRequest$json = {
  '1': 'UpdateUserProfileRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {
      '1': 'display_name',
      '3': 2,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'displayName',
      '17': true
    },
    {
      '1': 'notification_settings',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.user_service.UpdateUserProfileRequest.NotificationSettingsEntry',
      '10': 'notificationSettings'
    },
  ],
  '3': [UpdateUserProfileRequest_NotificationSettingsEntry$json],
  '8': [
    {'1': '_display_name'},
  ],
};

@$core.Deprecated('Use updateUserProfileRequestDescriptor instead')
const UpdateUserProfileRequest_NotificationSettingsEntry$json = {
  '1': 'NotificationSettingsEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `UpdateUserProfileRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateUserProfileRequestDescriptor = $convert.base64Decode(
    'ChhVcGRhdGVVc2VyUHJvZmlsZVJlcXVlc3QSFwoHdXNlcl9pZBgBIAEoCVIGdXNlcklkEiYKDG'
    'Rpc3BsYXlfbmFtZRgCIAEoCUgAUgtkaXNwbGF5TmFtZYgBARJ1ChVub3RpZmljYXRpb25fc2V0'
    'dGluZ3MYAyADKAsyQC51c2VyX3NlcnZpY2UuVXBkYXRlVXNlclByb2ZpbGVSZXF1ZXN0Lk5vdG'
    'lmaWNhdGlvblNldHRpbmdzRW50cnlSFG5vdGlmaWNhdGlvblNldHRpbmdzGkcKGU5vdGlmaWNh'
    'dGlvblNldHRpbmdzRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbH'
    'VlOgI4AUIPCg1fZGlzcGxheV9uYW1l');

@$core.Deprecated('Use updateUserProfileResponseDescriptor instead')
const UpdateUserProfileResponse$json = {
  '1': 'UpdateUserProfileResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `UpdateUserProfileResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateUserProfileResponseDescriptor =
    $convert.base64Decode(
        'ChlVcGRhdGVVc2VyUHJvZmlsZVJlc3BvbnNlEhgKB3N1Y2Nlc3MYASABKAhSB3N1Y2Nlc3M=');

@$core.Deprecated('Use userProfileDescriptor instead')
const UserProfile$json = {
  '1': 'UserProfile',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {
      '1': 'notification_settings',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.user_service.UserProfile.NotificationSettingsEntry',
      '10': 'notificationSettings'
    },
  ],
  '3': [UserProfile_NotificationSettingsEntry$json],
};

@$core.Deprecated('Use userProfileDescriptor instead')
const UserProfile_NotificationSettingsEntry$json = {
  '1': 'NotificationSettingsEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `UserProfile`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userProfileDescriptor = $convert.base64Decode(
    'CgtVc2VyUHJvZmlsZRIXCgd1c2VyX2lkGAEgASgJUgZ1c2VySWQSIQoMZGlzcGxheV9uYW1lGA'
    'IgASgJUgtkaXNwbGF5TmFtZRJoChVub3RpZmljYXRpb25fc2V0dGluZ3MYAyADKAsyMy51c2Vy'
    'X3NlcnZpY2UuVXNlclByb2ZpbGUuTm90aWZpY2F0aW9uU2V0dGluZ3NFbnRyeVIUbm90aWZpY2'
    'F0aW9uU2V0dGluZ3MaRwoZTm90aWZpY2F0aW9uU2V0dGluZ3NFbnRyeRIQCgNrZXkYASABKAlS'
    'A2tleRIUCgV2YWx1ZRgCIAEoCVIFdmFsdWU6AjgB');
