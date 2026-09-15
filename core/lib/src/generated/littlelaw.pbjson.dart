// This is a generated file - do not edit.
//
// Generated from littlelaw.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use deviceInfoDescriptor instead')
const DeviceInfo$json = {
  '1': 'DeviceInfo',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'device_name', '3': 2, '4': 1, '5': 9, '10': 'deviceName'},
    {'1': 'platform', '3': 3, '4': 1, '5': 9, '10': 'platform'},
    {'1': 'cert_fingerprint', '3': 4, '4': 1, '5': 9, '10': 'certFingerprint'},
    {'1': 'port', '3': 5, '4': 1, '5': 5, '10': 'port'},
    {'1': 'protocol_version', '3': 6, '4': 1, '5': 9, '10': 'protocolVersion'},
    {'1': 'device_model', '3': 7, '4': 1, '5': 9, '10': 'deviceModel'},
    {'1': 'cert_der', '3': 8, '4': 1, '5': 12, '10': 'certDer'},
  ],
};

/// Descriptor for `DeviceInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceInfoDescriptor = $convert.base64Decode(
    'CgpEZXZpY2VJbmZvEhsKCWRldmljZV9pZBgBIAEoCVIIZGV2aWNlSWQSHwoLZGV2aWNlX25hbW'
    'UYAiABKAlSCmRldmljZU5hbWUSGgoIcGxhdGZvcm0YAyABKAlSCHBsYXRmb3JtEikKEGNlcnRf'
    'ZmluZ2VycHJpbnQYBCABKAlSD2NlcnRGaW5nZXJwcmludBISCgRwb3J0GAUgASgFUgRwb3J0Ei'
    'kKEHByb3RvY29sX3ZlcnNpb24YBiABKAlSD3Byb3RvY29sVmVyc2lvbhIhCgxkZXZpY2VfbW9k'
    'ZWwYByABKAlSC2RldmljZU1vZGVsEhkKCGNlcnRfZGVyGAggASgMUgdjZXJ0RGVy');

@$core.Deprecated('Use discoveryPacketDescriptor instead')
const DiscoveryPacket$json = {
  '1': 'DiscoveryPacket',
  '2': [
    {'1': 'magic', '3': 1, '4': 1, '5': 7, '10': 'magic'},
    {
      '1': 'device',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.DeviceInfo',
      '10': 'device'
    },
    {'1': 'timestamp_ms', '3': 3, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'cert_der', '3': 4, '4': 1, '5': 12, '10': 'certDer'},
    {'1': 'signature', '3': 5, '4': 1, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `DiscoveryPacket`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List discoveryPacketDescriptor = $convert.base64Decode(
    'Cg9EaXNjb3ZlcnlQYWNrZXQSFAoFbWFnaWMYASABKAdSBW1hZ2ljEjAKBmRldmljZRgCIAEoCz'
    'IYLmxpdHRsZWxhdy52MS5EZXZpY2VJbmZvUgZkZXZpY2USIQoMdGltZXN0YW1wX21zGAMgASgD'
    'Ugt0aW1lc3RhbXBNcxIZCghjZXJ0X2RlchgEIAEoDFIHY2VydERlchIcCglzaWduYXR1cmUYBS'
    'ABKAxSCXNpZ25hdHVyZQ==');

@$core.Deprecated('Use deliverAnswerRequestDescriptor instead')
const DeliverAnswerRequest$json = {
  '1': 'DeliverAnswerRequest',
  '2': [
    {
      '1': 'requester',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.DeviceInfo',
      '10': 'requester'
    },
    {'1': 'offer_token', '3': 2, '4': 1, '5': 9, '10': 'offerToken'},
    {'1': 'answer_blob', '3': 3, '4': 1, '5': 9, '10': 'answerBlob'},
  ],
};

/// Descriptor for `DeliverAnswerRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deliverAnswerRequestDescriptor = $convert.base64Decode(
    'ChREZWxpdmVyQW5zd2VyUmVxdWVzdBI2CglyZXF1ZXN0ZXIYASABKAsyGC5saXR0bGVsYXcudj'
    'EuRGV2aWNlSW5mb1IJcmVxdWVzdGVyEh8KC29mZmVyX3Rva2VuGAIgASgJUgpvZmZlclRva2Vu'
    'Eh8KC2Fuc3dlcl9ibG9iGAMgASgJUgphbnN3ZXJCbG9i');

@$core.Deprecated('Use deliverAnswerResponseDescriptor instead')
const DeliverAnswerResponse$json = {
  '1': 'DeliverAnswerResponse',
  '2': [
    {'1': 'ok', '3': 1, '4': 1, '5': 8, '10': 'ok'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `DeliverAnswerResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deliverAnswerResponseDescriptor = $convert.base64Decode(
    'ChVEZWxpdmVyQW5zd2VyUmVzcG9uc2USDgoCb2sYASABKAhSAm9rEhgKB21lc3NhZ2UYAiABKA'
    'lSB21lc3NhZ2U=');

@$core.Deprecated('Use tapPairRequestDescriptor instead')
const TapPairRequest$json = {
  '1': 'TapPairRequest',
  '2': [
    {
      '1': 'requester',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.DeviceInfo',
      '10': 'requester'
    },
    {'1': 'tap_token', '3': 2, '4': 1, '5': 9, '10': 'tapToken'},
  ],
};

/// Descriptor for `TapPairRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tapPairRequestDescriptor = $convert.base64Decode(
    'Cg5UYXBQYWlyUmVxdWVzdBI2CglyZXF1ZXN0ZXIYASABKAsyGC5saXR0bGVsYXcudjEuRGV2aW'
    'NlSW5mb1IJcmVxdWVzdGVyEhsKCXRhcF90b2tlbhgCIAEoCVIIdGFwVG9rZW4=');

@$core.Deprecated('Use tapPairResponseDescriptor instead')
const TapPairResponse$json = {
  '1': 'TapPairResponse',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {
      '1': 'responder',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.DeviceInfo',
      '10': 'responder'
    },
    {'1': 'session_token', '3': 3, '4': 1, '5': 12, '10': 'sessionToken'},
    {'1': 'message', '3': 4, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `TapPairResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tapPairResponseDescriptor = $convert.base64Decode(
    'Cg9UYXBQYWlyUmVzcG9uc2USGgoIYWNjZXB0ZWQYASABKAhSCGFjY2VwdGVkEjYKCXJlc3Bvbm'
    'RlchgCIAEoCzIYLmxpdHRsZWxhdy52MS5EZXZpY2VJbmZvUglyZXNwb25kZXISIwoNc2Vzc2lv'
    'bl90b2tlbhgDIAEoDFIMc2Vzc2lvblRva2VuEhgKB21lc3NhZ2UYBCABKAlSB21lc3NhZ2U=');

@$core.Deprecated('Use pairRequestDescriptor instead')
const PairRequest$json = {
  '1': 'PairRequest',
  '2': [
    {
      '1': 'requester',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.DeviceInfo',
      '10': 'requester'
    },
    {'1': 'request_id', '3': 2, '4': 1, '5': 9, '10': 'requestId'},
  ],
};

/// Descriptor for `PairRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairRequestDescriptor = $convert.base64Decode(
    'CgtQYWlyUmVxdWVzdBI2CglyZXF1ZXN0ZXIYASABKAsyGC5saXR0bGVsYXcudjEuRGV2aWNlSW'
    '5mb1IJcmVxdWVzdGVyEh0KCnJlcXVlc3RfaWQYAiABKAlSCXJlcXVlc3RJZA==');

@$core.Deprecated('Use pairCancelRequestDescriptor instead')
const PairCancelRequest$json = {
  '1': 'PairCancelRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'requester_id', '3': 2, '4': 1, '5': 9, '10': 'requesterId'},
  ],
};

/// Descriptor for `PairCancelRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairCancelRequestDescriptor = $convert.base64Decode(
    'ChFQYWlyQ2FuY2VsUmVxdWVzdBIdCgpyZXF1ZXN0X2lkGAEgASgJUglyZXF1ZXN0SWQSIQoMcm'
    'VxdWVzdGVyX2lkGAIgASgJUgtyZXF1ZXN0ZXJJZA==');

@$core.Deprecated('Use pairCancelResponseDescriptor instead')
const PairCancelResponse$json = {
  '1': 'PairCancelResponse',
  '2': [
    {'1': 'ok', '3': 1, '4': 1, '5': 8, '10': 'ok'},
  ],
};

/// Descriptor for `PairCancelResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairCancelResponseDescriptor =
    $convert.base64Decode('ChJQYWlyQ2FuY2VsUmVzcG9uc2USDgoCb2sYASABKAhSAm9r');

@$core.Deprecated('Use pairResponseDescriptor instead')
const PairResponse$json = {
  '1': 'PairResponse',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {
      '1': 'responder',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.DeviceInfo',
      '10': 'responder'
    },
    {'1': 'session_token', '3': 3, '4': 1, '5': 12, '10': 'sessionToken'},
    {'1': 'message', '3': 4, '4': 1, '5': 9, '10': 'message'},
    {'1': 'confirm_nonce', '3': 5, '4': 1, '5': 9, '10': 'confirmNonce'},
  ],
};

/// Descriptor for `PairResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairResponseDescriptor = $convert.base64Decode(
    'CgxQYWlyUmVzcG9uc2USGgoIYWNjZXB0ZWQYASABKAhSCGFjY2VwdGVkEjYKCXJlc3BvbmRlch'
    'gCIAEoCzIYLmxpdHRsZWxhdy52MS5EZXZpY2VJbmZvUglyZXNwb25kZXISIwoNc2Vzc2lvbl90'
    'b2tlbhgDIAEoDFIMc2Vzc2lvblRva2VuEhgKB21lc3NhZ2UYBCABKAlSB21lc3NhZ2USIwoNY2'
    '9uZmlybV9ub25jZRgFIAEoCVIMY29uZmlybU5vbmNl');

@$core.Deprecated('Use pairConfirmRequestDescriptor instead')
const PairConfirmRequest$json = {
  '1': 'PairConfirmRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'requester_id', '3': 2, '4': 1, '5': 9, '10': 'requesterId'},
    {'1': 'signature', '3': 3, '4': 1, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `PairConfirmRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairConfirmRequestDescriptor = $convert.base64Decode(
    'ChJQYWlyQ29uZmlybVJlcXVlc3QSHQoKcmVxdWVzdF9pZBgBIAEoCVIJcmVxdWVzdElkEiEKDH'
    'JlcXVlc3Rlcl9pZBgCIAEoCVILcmVxdWVzdGVySWQSHAoJc2lnbmF0dXJlGAMgASgMUglzaWdu'
    'YXR1cmU=');

@$core.Deprecated('Use pairConfirmResponseDescriptor instead')
const PairConfirmResponse$json = {
  '1': 'PairConfirmResponse',
  '2': [
    {'1': 'ok', '3': 1, '4': 1, '5': 8, '10': 'ok'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `PairConfirmResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairConfirmResponseDescriptor = $convert.base64Decode(
    'ChNQYWlyQ29uZmlybVJlc3BvbnNlEg4KAm9rGAEgASgIUgJvaxIYCgdtZXNzYWdlGAIgASgJUg'
    'dtZXNzYWdl');

@$core.Deprecated('Use unpairRequestDescriptor instead')
const UnpairRequest$json = {
  '1': 'UnpairRequest',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
  ],
};

/// Descriptor for `UnpairRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List unpairRequestDescriptor = $convert.base64Decode(
    'Cg1VbnBhaXJSZXF1ZXN0EhsKCWRldmljZV9pZBgBIAEoCVIIZGV2aWNlSWQ=');

@$core.Deprecated('Use unpairResponseDescriptor instead')
const UnpairResponse$json = {
  '1': 'UnpairResponse',
  '2': [
    {'1': 'ok', '3': 1, '4': 1, '5': 8, '10': 'ok'},
  ],
};

/// Descriptor for `UnpairResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List unpairResponseDescriptor =
    $convert.base64Decode('Cg5VbnBhaXJSZXNwb25zZRIOCgJvaxgBIAEoCFICb2s=');

@$core.Deprecated('Use envelopeDescriptor instead')
const Envelope$json = {
  '1': 'Envelope',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {
      '1': 'hello',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.Hello',
      '9': 0,
      '10': 'hello'
    },
    {
      '1': 'chat',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.ChatMessage',
      '9': 0,
      '10': 'chat'
    },
    {
      '1': 'chat_deleted',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.ChatDeleted',
      '9': 0,
      '10': 'chatDeleted'
    },
    {
      '1': 'clipboard',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.ClipboardSync',
      '9': 0,
      '10': 'clipboard'
    },
    {
      '1': 'file_offer',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.FileOffer',
      '9': 0,
      '10': 'fileOffer'
    },
    {
      '1': 'file_answer',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.FileAnswer',
      '9': 0,
      '10': 'fileAnswer'
    },
    {
      '1': 'file_cancel',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.FileCancel',
      '9': 0,
      '10': 'fileCancel'
    },
    {
      '1': 'sync_ack',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.SyncAck',
      '9': 0,
      '10': 'syncAck'
    },
    {
      '1': 'heartbeat',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.Heartbeat',
      '9': 0,
      '10': 'heartbeat'
    },
    {
      '1': 'link_auth',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.LinkAuth',
      '9': 0,
      '10': 'linkAuth'
    },
    {
      '1': 'file_fetch',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.FileFetchRequest',
      '9': 0,
      '10': 'fileFetch'
    },
    {
      '1': 'file_data',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.FileData',
      '9': 0,
      '10': 'fileData'
    },
    {
      '1': 'file_data_ack',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.FileDataAck',
      '9': 0,
      '10': 'fileDataAck'
    },
    {
      '1': 'call_offer',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.CallOffer',
      '9': 0,
      '10': 'callOffer'
    },
    {
      '1': 'call_answer',
      '3': 16,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.CallAnswer',
      '9': 0,
      '10': 'callAnswer'
    },
    {
      '1': 'call_candidate',
      '3': 17,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.CallCandidate',
      '9': 0,
      '10': 'callCandidate'
    },
    {
      '1': 'call_end',
      '3': 18,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.CallEnd',
      '9': 0,
      '10': 'callEnd'
    },
    {
      '1': 'group_sync',
      '3': 19,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.GroupSync',
      '9': 0,
      '10': 'groupSync'
    },
    {
      '1': 'read_receipt',
      '3': 20,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.ReadReceipt',
      '9': 0,
      '10': 'readReceipt'
    },
    {
      '1': 'reaction',
      '3': 21,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.ReactionUpdate',
      '9': 0,
      '10': 'reaction'
    },
    {
      '1': 'profile_update',
      '3': 22,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.ProfileUpdate',
      '9': 0,
      '10': 'profileUpdate'
    },
    {
      '1': 'noop',
      '3': 23,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.Noop',
      '9': 0,
      '10': 'noop'
    },
    {
      '1': 'unpair_notice',
      '3': 24,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.UnpairNotice',
      '9': 0,
      '10': 'unpairNotice'
    },
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `Envelope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List envelopeDescriptor = $convert.base64Decode(
    'CghFbnZlbG9wZRIOCgJpZBgBIAEoCVICaWQSKwoFaGVsbG8YAiABKAsyEy5saXR0bGVsYXcudj'
    'EuSGVsbG9IAFIFaGVsbG8SLwoEY2hhdBgDIAEoCzIZLmxpdHRsZWxhdy52MS5DaGF0TWVzc2Fn'
    'ZUgAUgRjaGF0Ej4KDGNoYXRfZGVsZXRlZBgEIAEoCzIZLmxpdHRsZWxhdy52MS5DaGF0RGVsZX'
    'RlZEgAUgtjaGF0RGVsZXRlZBI7CgljbGlwYm9hcmQYBSABKAsyGy5saXR0bGVsYXcudjEuQ2xp'
    'cGJvYXJkU3luY0gAUgljbGlwYm9hcmQSOAoKZmlsZV9vZmZlchgGIAEoCzIXLmxpdHRsZWxhdy'
    '52MS5GaWxlT2ZmZXJIAFIJZmlsZU9mZmVyEjsKC2ZpbGVfYW5zd2VyGAcgASgLMhgubGl0dGxl'
    'bGF3LnYxLkZpbGVBbnN3ZXJIAFIKZmlsZUFuc3dlchI7CgtmaWxlX2NhbmNlbBgIIAEoCzIYLm'
    'xpdHRsZWxhdy52MS5GaWxlQ2FuY2VsSABSCmZpbGVDYW5jZWwSMgoIc3luY19hY2sYCSABKAsy'
    'FS5saXR0bGVsYXcudjEuU3luY0Fja0gAUgdzeW5jQWNrEjcKCWhlYXJ0YmVhdBgKIAEoCzIXLm'
    'xpdHRsZWxhdy52MS5IZWFydGJlYXRIAFIJaGVhcnRiZWF0EjUKCWxpbmtfYXV0aBgLIAEoCzIW'
    'LmxpdHRsZWxhdy52MS5MaW5rQXV0aEgAUghsaW5rQXV0aBI/CgpmaWxlX2ZldGNoGAwgASgLMh'
    '4ubGl0dGxlbGF3LnYxLkZpbGVGZXRjaFJlcXVlc3RIAFIJZmlsZUZldGNoEjUKCWZpbGVfZGF0'
    'YRgNIAEoCzIWLmxpdHRsZWxhdy52MS5GaWxlRGF0YUgAUghmaWxlRGF0YRI/Cg1maWxlX2RhdG'
    'FfYWNrGA4gASgLMhkubGl0dGxlbGF3LnYxLkZpbGVEYXRhQWNrSABSC2ZpbGVEYXRhQWNrEjgK'
    'CmNhbGxfb2ZmZXIYDyABKAsyFy5saXR0bGVsYXcudjEuQ2FsbE9mZmVySABSCWNhbGxPZmZlch'
    'I7CgtjYWxsX2Fuc3dlchgQIAEoCzIYLmxpdHRsZWxhdy52MS5DYWxsQW5zd2VySABSCmNhbGxB'
    'bnN3ZXISRAoOY2FsbF9jYW5kaWRhdGUYESABKAsyGy5saXR0bGVsYXcudjEuQ2FsbENhbmRpZG'
    'F0ZUgAUg1jYWxsQ2FuZGlkYXRlEjIKCGNhbGxfZW5kGBIgASgLMhUubGl0dGxlbGF3LnYxLkNh'
    'bGxFbmRIAFIHY2FsbEVuZBI4Cgpncm91cF9zeW5jGBMgASgLMhcubGl0dGxlbGF3LnYxLkdyb3'
    'VwU3luY0gAUglncm91cFN5bmMSPgoMcmVhZF9yZWNlaXB0GBQgASgLMhkubGl0dGxlbGF3LnYx'
    'LlJlYWRSZWNlaXB0SABSC3JlYWRSZWNlaXB0EjoKCHJlYWN0aW9uGBUgASgLMhwubGl0dGxlbG'
    'F3LnYxLlJlYWN0aW9uVXBkYXRlSABSCHJlYWN0aW9uEkQKDnByb2ZpbGVfdXBkYXRlGBYgASgL'
    'MhsubGl0dGxlbGF3LnYxLlByb2ZpbGVVcGRhdGVIAFINcHJvZmlsZVVwZGF0ZRIoCgRub29wGB'
    'cgASgLMhIubGl0dGxlbGF3LnYxLk5vb3BIAFIEbm9vcBJBCg11bnBhaXJfbm90aWNlGBggASgL'
    'MhoubGl0dGxlbGF3LnYxLlVucGFpck5vdGljZUgAUgx1bnBhaXJOb3RpY2VCCQoHcGF5bG9hZA'
    '==');

@$core.Deprecated('Use noopDescriptor instead')
const Noop$json = {
  '1': 'Noop',
  '2': [
    {'1': 'op_seq', '3': 1, '4': 1, '5': 3, '10': 'opSeq'},
  ],
};

/// Descriptor for `Noop`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List noopDescriptor =
    $convert.base64Decode('CgROb29wEhUKBm9wX3NlcRgBIAEoA1IFb3BTZXE=');

@$core.Deprecated('Use unpairNoticeDescriptor instead')
const UnpairNotice$json = {
  '1': 'UnpairNotice',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
  ],
};

/// Descriptor for `UnpairNotice`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List unpairNoticeDescriptor = $convert.base64Decode(
    'CgxVbnBhaXJOb3RpY2USGwoJZGV2aWNlX2lkGAEgASgJUghkZXZpY2VJZA==');

@$core.Deprecated('Use profileUpdateDescriptor instead')
const ProfileUpdate$json = {
  '1': 'ProfileUpdate',
  '2': [
    {'1': 'device_name', '3': 1, '4': 1, '5': 9, '10': 'deviceName'},
    {'1': 'avatar_png', '3': 2, '4': 1, '5': 12, '10': 'avatarPng'},
    {'1': 'op_seq', '3': 3, '4': 1, '5': 3, '10': 'opSeq'},
  ],
};

/// Descriptor for `ProfileUpdate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List profileUpdateDescriptor = $convert.base64Decode(
    'Cg1Qcm9maWxlVXBkYXRlEh8KC2RldmljZV9uYW1lGAEgASgJUgpkZXZpY2VOYW1lEh0KCmF2YX'
    'Rhcl9wbmcYAiABKAxSCWF2YXRhclBuZxIVCgZvcF9zZXEYAyABKANSBW9wU2Vx');

@$core.Deprecated('Use readReceiptDescriptor instead')
const ReadReceipt$json = {
  '1': 'ReadReceipt',
  '2': [
    {'1': 'reader', '3': 1, '4': 1, '5': 9, '10': 'reader'},
    {'1': 'conv_peer', '3': 2, '4': 1, '5': 9, '10': 'convPeer'},
    {'1': 'group_id', '3': 3, '4': 1, '5': 9, '10': 'groupId'},
    {'1': 'msg_ids', '3': 4, '4': 3, '5': 9, '10': 'msgIds'},
    {'1': 'op_seq', '3': 5, '4': 1, '5': 3, '10': 'opSeq'},
  ],
};

/// Descriptor for `ReadReceipt`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readReceiptDescriptor = $convert.base64Decode(
    'CgtSZWFkUmVjZWlwdBIWCgZyZWFkZXIYASABKAlSBnJlYWRlchIbCgljb252X3BlZXIYAiABKA'
    'lSCGNvbnZQZWVyEhkKCGdyb3VwX2lkGAMgASgJUgdncm91cElkEhcKB21zZ19pZHMYBCADKAlS'
    'Bm1zZ0lkcxIVCgZvcF9zZXEYBSABKANSBW9wU2Vx');

@$core.Deprecated('Use reactionUpdateDescriptor instead')
const ReactionUpdate$json = {
  '1': 'ReactionUpdate',
  '2': [
    {'1': 'msg_id', '3': 1, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'group_id', '3': 2, '4': 1, '5': 9, '10': 'groupId'},
    {'1': 'conv_peer', '3': 3, '4': 1, '5': 9, '10': 'convPeer'},
    {'1': 'device_id', '3': 4, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'emoji', '3': 5, '4': 1, '5': 9, '10': 'emoji'},
    {'1': 'op_seq', '3': 6, '4': 1, '5': 3, '10': 'opSeq'},
  ],
};

/// Descriptor for `ReactionUpdate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reactionUpdateDescriptor = $convert.base64Decode(
    'Cg5SZWFjdGlvblVwZGF0ZRIVCgZtc2dfaWQYASABKAlSBW1zZ0lkEhkKCGdyb3VwX2lkGAIgAS'
    'gJUgdncm91cElkEhsKCWNvbnZfcGVlchgDIAEoCVIIY29udlBlZXISGwoJZGV2aWNlX2lkGAQg'
    'ASgJUghkZXZpY2VJZBIUCgVlbW9qaRgFIAEoCVIFZW1vamkSFQoGb3Bfc2VxGAYgASgDUgVvcF'
    'NlcQ==');

@$core.Deprecated('Use groupSyncDescriptor instead')
const GroupSync$json = {
  '1': 'GroupSync',
  '2': [
    {'1': 'group_id', '3': 1, '4': 1, '5': 9, '10': 'groupId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'member_ids', '3': 3, '4': 3, '5': 9, '10': 'memberIds'},
    {'1': 'created_at_ms', '3': 4, '4': 1, '5': 3, '10': 'createdAtMs'},
    {'1': 'dissolved', '3': 5, '4': 1, '5': 8, '10': 'dissolved'},
    {'1': 'avatar_png', '3': 6, '4': 1, '5': 12, '10': 'avatarPng'},
    {'1': 'op_seq', '3': 7, '4': 1, '5': 3, '10': 'opSeq'},
  ],
};

/// Descriptor for `GroupSync`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupSyncDescriptor = $convert.base64Decode(
    'CglHcm91cFN5bmMSGQoIZ3JvdXBfaWQYASABKAlSB2dyb3VwSWQSEgoEbmFtZRgCIAEoCVIEbm'
    'FtZRIdCgptZW1iZXJfaWRzGAMgAygJUgltZW1iZXJJZHMSIgoNY3JlYXRlZF9hdF9tcxgEIAEo'
    'A1ILY3JlYXRlZEF0TXMSHAoJZGlzc29sdmVkGAUgASgIUglkaXNzb2x2ZWQSHQoKYXZhdGFyX3'
    'BuZxgGIAEoDFIJYXZhdGFyUG5nEhUKBm9wX3NlcRgHIAEoA1IFb3BTZXE=');

@$core.Deprecated('Use fileDataAckDescriptor instead')
const FileDataAck$json = {
  '1': 'FileDataAck',
  '2': [
    {'1': 'file_id', '3': 1, '4': 1, '5': 9, '10': 'fileId'},
    {'1': 'acked_offset', '3': 2, '4': 1, '5': 3, '10': 'ackedOffset'},
    {'1': 'attempt', '3': 3, '4': 1, '5': 13, '10': 'attempt'},
  ],
};

/// Descriptor for `FileDataAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileDataAckDescriptor = $convert.base64Decode(
    'CgtGaWxlRGF0YUFjaxIXCgdmaWxlX2lkGAEgASgJUgZmaWxlSWQSIQoMYWNrZWRfb2Zmc2V0GA'
    'IgASgDUgthY2tlZE9mZnNldBIYCgdhdHRlbXB0GAMgASgNUgdhdHRlbXB0');

@$core.Deprecated('Use callOfferDescriptor instead')
const CallOffer$json = {
  '1': 'CallOffer',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 9, '10': 'callId'},
    {'1': 'sdp', '3': 2, '4': 1, '5': 9, '10': 'sdp'},
    {'1': 'video', '3': 3, '4': 1, '5': 8, '10': 'video'},
  ],
};

/// Descriptor for `CallOffer`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callOfferDescriptor = $convert.base64Decode(
    'CglDYWxsT2ZmZXISFwoHY2FsbF9pZBgBIAEoCVIGY2FsbElkEhAKA3NkcBgCIAEoCVIDc2RwEh'
    'QKBXZpZGVvGAMgASgIUgV2aWRlbw==');

@$core.Deprecated('Use callAnswerDescriptor instead')
const CallAnswer$json = {
  '1': 'CallAnswer',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 9, '10': 'callId'},
    {'1': 'sdp', '3': 2, '4': 1, '5': 9, '10': 'sdp'},
    {'1': 'accepted', '3': 3, '4': 1, '5': 8, '10': 'accepted'},
  ],
};

/// Descriptor for `CallAnswer`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callAnswerDescriptor = $convert.base64Decode(
    'CgpDYWxsQW5zd2VyEhcKB2NhbGxfaWQYASABKAlSBmNhbGxJZBIQCgNzZHAYAiABKAlSA3NkcB'
    'IaCghhY2NlcHRlZBgDIAEoCFIIYWNjZXB0ZWQ=');

@$core.Deprecated('Use callCandidateDescriptor instead')
const CallCandidate$json = {
  '1': 'CallCandidate',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 9, '10': 'callId'},
    {'1': 'candidate', '3': 2, '4': 1, '5': 9, '10': 'candidate'},
    {'1': 'sdp_mid', '3': 3, '4': 1, '5': 9, '10': 'sdpMid'},
    {'1': 'sdp_mline_index', '3': 4, '4': 1, '5': 5, '10': 'sdpMlineIndex'},
  ],
};

/// Descriptor for `CallCandidate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callCandidateDescriptor = $convert.base64Decode(
    'Cg1DYWxsQ2FuZGlkYXRlEhcKB2NhbGxfaWQYASABKAlSBmNhbGxJZBIcCgljYW5kaWRhdGUYAi'
    'ABKAlSCWNhbmRpZGF0ZRIXCgdzZHBfbWlkGAMgASgJUgZzZHBNaWQSJgoPc2RwX21saW5lX2lu'
    'ZGV4GAQgASgFUg1zZHBNbGluZUluZGV4');

@$core.Deprecated('Use callEndDescriptor instead')
const CallEnd$json = {
  '1': 'CallEnd',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 9, '10': 'callId'},
    {'1': 'reason', '3': 2, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `CallEnd`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callEndDescriptor = $convert.base64Decode(
    'CgdDYWxsRW5kEhcKB2NhbGxfaWQYASABKAlSBmNhbGxJZBIWCgZyZWFzb24YAiABKAlSBnJlYX'
    'Nvbg==');

@$core.Deprecated('Use linkAuthDescriptor instead')
const LinkAuth$json = {
  '1': 'LinkAuth',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'token', '3': 2, '4': 1, '5': 9, '10': 'token'},
  ],
};

/// Descriptor for `LinkAuth`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List linkAuthDescriptor = $convert.base64Decode(
    'CghMaW5rQXV0aBIbCglkZXZpY2VfaWQYASABKAlSCGRldmljZUlkEhQKBXRva2VuGAIgASgJUg'
    'V0b2tlbg==');

@$core.Deprecated('Use fileFetchRequestDescriptor instead')
const FileFetchRequest$json = {
  '1': 'FileFetchRequest',
  '2': [
    {'1': 'file_id', '3': 1, '4': 1, '5': 9, '10': 'fileId'},
    {'1': 'offset', '3': 2, '4': 1, '5': 3, '10': 'offset'},
    {'1': 'attempt', '3': 3, '4': 1, '5': 13, '10': 'attempt'},
  ],
};

/// Descriptor for `FileFetchRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileFetchRequestDescriptor = $convert.base64Decode(
    'ChBGaWxlRmV0Y2hSZXF1ZXN0EhcKB2ZpbGVfaWQYASABKAlSBmZpbGVJZBIWCgZvZmZzZXQYAi'
    'ABKANSBm9mZnNldBIYCgdhdHRlbXB0GAMgASgNUgdhdHRlbXB0');

@$core.Deprecated('Use fileDataDescriptor instead')
const FileData$json = {
  '1': 'FileData',
  '2': [
    {'1': 'file_id', '3': 1, '4': 1, '5': 9, '10': 'fileId'},
    {'1': 'offset', '3': 2, '4': 1, '5': 3, '10': 'offset'},
    {'1': 'data', '3': 3, '4': 1, '5': 12, '10': 'data'},
    {'1': 'last', '3': 4, '4': 1, '5': 8, '10': 'last'},
    {'1': 'attempt', '3': 5, '4': 1, '5': 13, '10': 'attempt'},
  ],
};

/// Descriptor for `FileData`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileDataDescriptor = $convert.base64Decode(
    'CghGaWxlRGF0YRIXCgdmaWxlX2lkGAEgASgJUgZmaWxlSWQSFgoGb2Zmc2V0GAIgASgDUgZvZm'
    'ZzZXQSEgoEZGF0YRgDIAEoDFIEZGF0YRISCgRsYXN0GAQgASgIUgRsYXN0EhgKB2F0dGVtcHQY'
    'BSABKA1SB2F0dGVtcHQ=');

@$core.Deprecated('Use helloDescriptor instead')
const Hello$json = {
  '1': 'Hello',
  '2': [
    {'1': 'applied_peer_seq', '3': 1, '4': 1, '5': 3, '10': 'appliedPeerSeq'},
  ],
};

/// Descriptor for `Hello`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List helloDescriptor = $convert.base64Decode(
    'CgVIZWxsbxIoChBhcHBsaWVkX3BlZXJfc2VxGAEgASgDUg5hcHBsaWVkUGVlclNlcQ==');

@$core.Deprecated('Use chatMessageDescriptor instead')
const ChatMessage$json = {
  '1': 'ChatMessage',
  '2': [
    {'1': 'msg_id', '3': 1, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'op_seq', '3': 2, '4': 1, '5': 3, '10': 'opSeq'},
    {'1': 'lamport', '3': 3, '4': 1, '5': 3, '10': 'lamport'},
    {'1': 'created_at_ms', '3': 4, '4': 1, '5': 3, '10': 'createdAtMs'},
    {'1': 'kind', '3': 5, '4': 1, '5': 5, '10': 'kind'},
    {'1': 'text', '3': 6, '4': 1, '5': 9, '10': 'text'},
    {'1': 'file_id', '3': 7, '4': 1, '5': 9, '10': 'fileId'},
    {'1': 'file_name', '3': 8, '4': 1, '5': 9, '10': 'fileName'},
    {'1': 'file_size', '3': 9, '4': 1, '5': 3, '10': 'fileSize'},
    {'1': 'file_sha256', '3': 10, '4': 1, '5': 9, '10': 'fileSha256'},
    {'1': 'conv_peer', '3': 11, '4': 1, '5': 9, '10': 'convPeer'},
    {'1': 'sender', '3': 12, '4': 1, '5': 9, '10': 'sender'},
    {'1': 'group_id', '3': 13, '4': 1, '5': 9, '10': 'groupId'},
    {'1': 'duration_ms', '3': 14, '4': 1, '5': 5, '10': 'durationMs'},
    {'1': 'read', '3': 15, '4': 1, '5': 8, '10': 'read'},
  ],
};

/// Descriptor for `ChatMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatMessageDescriptor = $convert.base64Decode(
    'CgtDaGF0TWVzc2FnZRIVCgZtc2dfaWQYASABKAlSBW1zZ0lkEhUKBm9wX3NlcRgCIAEoA1IFb3'
    'BTZXESGAoHbGFtcG9ydBgDIAEoA1IHbGFtcG9ydBIiCg1jcmVhdGVkX2F0X21zGAQgASgDUgtj'
    'cmVhdGVkQXRNcxISCgRraW5kGAUgASgFUgRraW5kEhIKBHRleHQYBiABKAlSBHRleHQSFwoHZm'
    'lsZV9pZBgHIAEoCVIGZmlsZUlkEhsKCWZpbGVfbmFtZRgIIAEoCVIIZmlsZU5hbWUSGwoJZmls'
    'ZV9zaXplGAkgASgDUghmaWxlU2l6ZRIfCgtmaWxlX3NoYTI1NhgKIAEoCVIKZmlsZVNoYTI1Nh'
    'IbCgljb252X3BlZXIYCyABKAlSCGNvbnZQZWVyEhYKBnNlbmRlchgMIAEoCVIGc2VuZGVyEhkK'
    'CGdyb3VwX2lkGA0gASgJUgdncm91cElkEh8KC2R1cmF0aW9uX21zGA4gASgFUgpkdXJhdGlvbk'
    '1zEhIKBHJlYWQYDyABKAhSBHJlYWQ=');

@$core.Deprecated('Use chatDeletedDescriptor instead')
const ChatDeleted$json = {
  '1': 'ChatDeleted',
  '2': [
    {'1': 'op_seq', '3': 1, '4': 1, '5': 3, '10': 'opSeq'},
    {'1': 'msg_ids', '3': 2, '4': 3, '5': 9, '10': 'msgIds'},
    {'1': 'clear_all', '3': 3, '4': 1, '5': 8, '10': 'clearAll'},
    {'1': 'conv_peer', '3': 4, '4': 1, '5': 9, '10': 'convPeer'},
    {'1': 'group_id', '3': 5, '4': 1, '5': 9, '10': 'groupId'},
  ],
};

/// Descriptor for `ChatDeleted`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatDeletedDescriptor = $convert.base64Decode(
    'CgtDaGF0RGVsZXRlZBIVCgZvcF9zZXEYASABKANSBW9wU2VxEhcKB21zZ19pZHMYAiADKAlSBm'
    '1zZ0lkcxIbCgljbGVhcl9hbGwYAyABKAhSCGNsZWFyQWxsEhsKCWNvbnZfcGVlchgEIAEoCVII'
    'Y29udlBlZXISGQoIZ3JvdXBfaWQYBSABKAlSB2dyb3VwSWQ=');

@$core.Deprecated('Use clipboardSyncDescriptor instead')
const ClipboardSync$json = {
  '1': 'ClipboardSync',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'at_ms', '3': 2, '4': 1, '5': 3, '10': 'atMs'},
  ],
};

/// Descriptor for `ClipboardSync`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clipboardSyncDescriptor = $convert.base64Decode(
    'Cg1DbGlwYm9hcmRTeW5jEhIKBHRleHQYASABKAlSBHRleHQSEwoFYXRfbXMYAiABKANSBGF0TX'
    'M=');

@$core.Deprecated('Use fileOfferDescriptor instead')
const FileOffer$json = {
  '1': 'FileOffer',
  '2': [
    {'1': 'file_id', '3': 1, '4': 1, '5': 9, '10': 'fileId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'size', '3': 3, '4': 1, '5': 3, '10': 'size'},
    {'1': 'sha256_hex', '3': 4, '4': 1, '5': 9, '10': 'sha256Hex'},
    {'1': 'mime', '3': 5, '4': 1, '5': 9, '10': 'mime'},
  ],
};

/// Descriptor for `FileOffer`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileOfferDescriptor = $convert.base64Decode(
    'CglGaWxlT2ZmZXISFwoHZmlsZV9pZBgBIAEoCVIGZmlsZUlkEhIKBG5hbWUYAiABKAlSBG5hbW'
    'USEgoEc2l6ZRgDIAEoA1IEc2l6ZRIdCgpzaGEyNTZfaGV4GAQgASgJUglzaGEyNTZIZXgSEgoE'
    'bWltZRgFIAEoCVIEbWltZQ==');

@$core.Deprecated('Use fileAnswerDescriptor instead')
const FileAnswer$json = {
  '1': 'FileAnswer',
  '2': [
    {'1': 'file_id', '3': 1, '4': 1, '5': 9, '10': 'fileId'},
    {'1': 'accept', '3': 2, '4': 1, '5': 8, '10': 'accept'},
    {'1': 'offset', '3': 3, '4': 1, '5': 3, '10': 'offset'},
  ],
};

/// Descriptor for `FileAnswer`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileAnswerDescriptor = $convert.base64Decode(
    'CgpGaWxlQW5zd2VyEhcKB2ZpbGVfaWQYASABKAlSBmZpbGVJZBIWCgZhY2NlcHQYAiABKAhSBm'
    'FjY2VwdBIWCgZvZmZzZXQYAyABKANSBm9mZnNldA==');

@$core.Deprecated('Use fileCancelDescriptor instead')
const FileCancel$json = {
  '1': 'FileCancel',
  '2': [
    {'1': 'file_id', '3': 1, '4': 1, '5': 9, '10': 'fileId'},
    {'1': 'reason', '3': 2, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `FileCancel`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileCancelDescriptor = $convert.base64Decode(
    'CgpGaWxlQ2FuY2VsEhcKB2ZpbGVfaWQYASABKAlSBmZpbGVJZBIWCgZyZWFzb24YAiABKAlSBn'
    'JlYXNvbg==');

@$core.Deprecated('Use syncAckDescriptor instead')
const SyncAck$json = {
  '1': 'SyncAck',
  '2': [
    {'1': 'envelope_ids', '3': 1, '4': 3, '5': 9, '10': 'envelopeIds'},
    {'1': 'applied_peer_seq', '3': 2, '4': 1, '5': 3, '10': 'appliedPeerSeq'},
  ],
};

/// Descriptor for `SyncAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List syncAckDescriptor = $convert.base64Decode(
    'CgdTeW5jQWNrEiEKDGVudmVsb3BlX2lkcxgBIAMoCVILZW52ZWxvcGVJZHMSKAoQYXBwbGllZF'
    '9wZWVyX3NlcRgCIAEoA1IOYXBwbGllZFBlZXJTZXE=');

@$core.Deprecated('Use heartbeatDescriptor instead')
const Heartbeat$json = {
  '1': 'Heartbeat',
  '2': [
    {'1': 'at_ms', '3': 1, '4': 1, '5': 3, '10': 'atMs'},
    {'1': 'reply', '3': 2, '4': 1, '5': 8, '10': 'reply'},
  ],
};

/// Descriptor for `Heartbeat`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List heartbeatDescriptor = $convert.base64Decode(
    'CglIZWFydGJlYXQSEwoFYXRfbXMYASABKANSBGF0TXMSFAoFcmVwbHkYAiABKAhSBXJlcGx5');

@$core.Deprecated('Use fileChunkDescriptor instead')
const FileChunk$json = {
  '1': 'FileChunk',
  '2': [
    {
      '1': 'head',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.littlelaw.v1.FileHead',
      '9': 0,
      '10': 'head'
    },
    {'1': 'data', '3': 2, '4': 1, '5': 12, '9': 0, '10': 'data'},
  ],
  '8': [
    {'1': 'part'},
  ],
};

/// Descriptor for `FileChunk`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileChunkDescriptor = $convert.base64Decode(
    'CglGaWxlQ2h1bmsSLAoEaGVhZBgBIAEoCzIWLmxpdHRsZWxhdy52MS5GaWxlSGVhZEgAUgRoZW'
    'FkEhQKBGRhdGEYAiABKAxIAFIEZGF0YUIGCgRwYXJ0');

@$core.Deprecated('Use fileHeadDescriptor instead')
const FileHead$json = {
  '1': 'FileHead',
  '2': [
    {'1': 'file_id', '3': 1, '4': 1, '5': 9, '10': 'fileId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'offset', '3': 3, '4': 1, '5': 3, '10': 'offset'},
    {'1': 'total_size', '3': 4, '4': 1, '5': 3, '10': 'totalSize'},
    {'1': 'sha256_hex', '3': 5, '4': 1, '5': 9, '10': 'sha256Hex'},
  ],
};

/// Descriptor for `FileHead`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileHeadDescriptor = $convert.base64Decode(
    'CghGaWxlSGVhZBIXCgdmaWxlX2lkGAEgASgJUgZmaWxlSWQSEgoEbmFtZRgCIAEoCVIEbmFtZR'
    'IWCgZvZmZzZXQYAyABKANSBm9mZnNldBIdCgp0b3RhbF9zaXplGAQgASgDUgl0b3RhbFNpemUS'
    'HQoKc2hhMjU2X2hleBgFIAEoCVIJc2hhMjU2SGV4');

@$core.Deprecated('Use fetchRequestDescriptor instead')
const FetchRequest$json = {
  '1': 'FetchRequest',
  '2': [
    {'1': 'file_id', '3': 1, '4': 1, '5': 9, '10': 'fileId'},
    {'1': 'offset', '3': 2, '4': 1, '5': 3, '10': 'offset'},
    {'1': 'attempt', '3': 3, '4': 1, '5': 13, '10': 'attempt'},
  ],
};

/// Descriptor for `FetchRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fetchRequestDescriptor = $convert.base64Decode(
    'CgxGZXRjaFJlcXVlc3QSFwoHZmlsZV9pZBgBIAEoCVIGZmlsZUlkEhYKBm9mZnNldBgCIAEoA1'
    'IGb2Zmc2V0EhgKB2F0dGVtcHQYAyABKA1SB2F0dGVtcHQ=');

@$core.Deprecated('Use fileResultDescriptor instead')
const FileResult$json = {
  '1': 'FileResult',
  '2': [
    {'1': 'ok', '3': 1, '4': 1, '5': 8, '10': 'ok'},
    {'1': 'received_bytes', '3': 2, '4': 1, '5': 3, '10': 'receivedBytes'},
    {'1': 'sha256_ok', '3': 3, '4': 1, '5': 8, '10': 'sha256Ok'},
    {'1': 'message', '3': 4, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `FileResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileResultDescriptor = $convert.base64Decode(
    'CgpGaWxlUmVzdWx0Eg4KAm9rGAEgASgIUgJvaxIlCg5yZWNlaXZlZF9ieXRlcxgCIAEoA1INcm'
    'VjZWl2ZWRCeXRlcxIbCglzaGEyNTZfb2sYAyABKAhSCHNoYTI1Nk9rEhgKB21lc3NhZ2UYBCAB'
    'KAlSB21lc3NhZ2U=');
