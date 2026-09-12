// This is a generated file - do not edit.
//
// Generated from littlelaw.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// 设备身份信息。device_id 与证书在首次启动时生成,终身不变。
class DeviceInfo extends $pb.GeneratedMessage {
  factory DeviceInfo({
    $core.String? deviceId,
    $core.String? deviceName,
    $core.String? platform,
    $core.String? certFingerprint,
    $core.int? port,
    $core.String? protocolVersion,
    $core.String? deviceModel,
  }) {
    final result = create();
    if (deviceId != null) result.deviceId = deviceId;
    if (deviceName != null) result.deviceName = deviceName;
    if (platform != null) result.platform = platform;
    if (certFingerprint != null) result.certFingerprint = certFingerprint;
    if (port != null) result.port = port;
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    if (deviceModel != null) result.deviceModel = deviceModel;
    return result;
  }

  DeviceInfo._();

  factory DeviceInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeviceInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..aOS(2, _omitFieldNames ? '' : 'deviceName')
    ..aOS(3, _omitFieldNames ? '' : 'platform')
    ..aOS(4, _omitFieldNames ? '' : 'certFingerprint')
    ..aI(5, _omitFieldNames ? '' : 'port')
    ..aOS(6, _omitFieldNames ? '' : 'protocolVersion')
    ..aOS(7, _omitFieldNames ? '' : 'deviceModel')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceInfo copyWith(void Function(DeviceInfo) updates) =>
      super.copyWith((message) => updates(message as DeviceInfo)) as DeviceInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceInfo create() => DeviceInfo._();
  @$core.override
  DeviceInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeviceInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeviceInfo>(create);
  static DeviceInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get deviceName => $_getSZ(1);
  @$pb.TagNumber(2)
  set deviceName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeviceName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get platform => $_getSZ(2);
  @$pb.TagNumber(3)
  set platform($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPlatform() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlatform() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get certFingerprint => $_getSZ(3);
  @$pb.TagNumber(4)
  set certFingerprint($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCertFingerprint() => $_has(3);
  @$pb.TagNumber(4)
  void clearCertFingerprint() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get port => $_getIZ(4);
  @$pb.TagNumber(5)
  set port($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPort() => $_has(4);
  @$pb.TagNumber(5)
  void clearPort() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get protocolVersion => $_getSZ(5);
  @$pb.TagNumber(6)
  set protocolVersion($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasProtocolVersion() => $_has(5);
  @$pb.TagNumber(6)
  void clearProtocolVersion() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get deviceModel => $_getSZ(6);
  @$pb.TagNumber(7)
  set deviceModel($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDeviceModel() => $_has(6);
  @$pb.TagNumber(7)
  void clearDeviceModel() => $_clearField(7);
}

/// UDP 发现报文。序列化后作为 UDP payload 直接发送。
class DiscoveryPacket extends $pb.GeneratedMessage {
  factory DiscoveryPacket({
    $core.int? magic,
    DeviceInfo? device,
    $fixnum.Int64? timestampMs,
  }) {
    final result = create();
    if (magic != null) result.magic = magic;
    if (device != null) result.device = device;
    if (timestampMs != null) result.timestampMs = timestampMs;
    return result;
  }

  DiscoveryPacket._();

  factory DiscoveryPacket.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiscoveryPacket.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiscoveryPacket',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'magic', fieldType: $pb.PbFieldType.OF3)
    ..aOM<DeviceInfo>(2, _omitFieldNames ? '' : 'device',
        subBuilder: DeviceInfo.create)
    ..aInt64(3, _omitFieldNames ? '' : 'timestampMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiscoveryPacket clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiscoveryPacket copyWith(void Function(DiscoveryPacket) updates) =>
      super.copyWith((message) => updates(message as DiscoveryPacket))
          as DiscoveryPacket;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiscoveryPacket create() => DiscoveryPacket._();
  @$core.override
  DiscoveryPacket createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiscoveryPacket getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiscoveryPacket>(create);
  static DiscoveryPacket? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get magic => $_getIZ(0);
  @$pb.TagNumber(1)
  set magic($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMagic() => $_has(0);
  @$pb.TagNumber(1)
  void clearMagic() => $_clearField(1);

  @$pb.TagNumber(2)
  DeviceInfo get device => $_getN(1);
  @$pb.TagNumber(2)
  set device(DeviceInfo value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasDevice() => $_has(1);
  @$pb.TagNumber(2)
  void clearDevice() => $_clearField(2);
  @$pb.TagNumber(2)
  DeviceInfo ensureDevice() => $_ensure(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get timestampMs => $_getI64(2);
  @$pb.TagNumber(3)
  set timestampMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTimestampMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestampMs() => $_clearField(3);
}

class DeliverAnswerRequest extends $pb.GeneratedMessage {
  factory DeliverAnswerRequest({
    DeviceInfo? requester,
    $core.String? offerToken,
    $core.String? answerBlob,
  }) {
    final result = create();
    if (requester != null) result.requester = requester;
    if (offerToken != null) result.offerToken = offerToken;
    if (answerBlob != null) result.answerBlob = answerBlob;
    return result;
  }

  DeliverAnswerRequest._();

  factory DeliverAnswerRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeliverAnswerRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeliverAnswerRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOM<DeviceInfo>(1, _omitFieldNames ? '' : 'requester',
        subBuilder: DeviceInfo.create)
    ..aOS(2, _omitFieldNames ? '' : 'offerToken')
    ..aOS(3, _omitFieldNames ? '' : 'answerBlob')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeliverAnswerRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeliverAnswerRequest copyWith(void Function(DeliverAnswerRequest) updates) =>
      super.copyWith((message) => updates(message as DeliverAnswerRequest))
          as DeliverAnswerRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeliverAnswerRequest create() => DeliverAnswerRequest._();
  @$core.override
  DeliverAnswerRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeliverAnswerRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeliverAnswerRequest>(create);
  static DeliverAnswerRequest? _defaultInstance;

  @$pb.TagNumber(1)
  DeviceInfo get requester => $_getN(0);
  @$pb.TagNumber(1)
  set requester(DeviceInfo value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRequester() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequester() => $_clearField(1);
  @$pb.TagNumber(1)
  DeviceInfo ensureRequester() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get offerToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set offerToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOfferToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearOfferToken() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get answerBlob => $_getSZ(2);
  @$pb.TagNumber(3)
  set answerBlob($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAnswerBlob() => $_has(2);
  @$pb.TagNumber(3)
  void clearAnswerBlob() => $_clearField(3);
}

class DeliverAnswerResponse extends $pb.GeneratedMessage {
  factory DeliverAnswerResponse({
    $core.bool? ok,
    $core.String? message,
  }) {
    final result = create();
    if (ok != null) result.ok = ok;
    if (message != null) result.message = message;
    return result;
  }

  DeliverAnswerResponse._();

  factory DeliverAnswerResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeliverAnswerResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeliverAnswerResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'ok')
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeliverAnswerResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeliverAnswerResponse copyWith(
          void Function(DeliverAnswerResponse) updates) =>
      super.copyWith((message) => updates(message as DeliverAnswerResponse))
          as DeliverAnswerResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeliverAnswerResponse create() => DeliverAnswerResponse._();
  @$core.override
  DeliverAnswerResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeliverAnswerResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeliverAnswerResponse>(create);
  static DeliverAnswerResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get ok => $_getBF(0);
  @$pb.TagNumber(1)
  set ok($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOk() => $_has(0);
  @$pb.TagNumber(1)
  void clearOk() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);
}

class TapPairRequest extends $pb.GeneratedMessage {
  factory TapPairRequest({
    DeviceInfo? requester,
    $core.String? tapToken,
  }) {
    final result = create();
    if (requester != null) result.requester = requester;
    if (tapToken != null) result.tapToken = tapToken;
    return result;
  }

  TapPairRequest._();

  factory TapPairRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TapPairRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TapPairRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOM<DeviceInfo>(1, _omitFieldNames ? '' : 'requester',
        subBuilder: DeviceInfo.create)
    ..aOS(2, _omitFieldNames ? '' : 'tapToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TapPairRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TapPairRequest copyWith(void Function(TapPairRequest) updates) =>
      super.copyWith((message) => updates(message as TapPairRequest))
          as TapPairRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TapPairRequest create() => TapPairRequest._();
  @$core.override
  TapPairRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TapPairRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TapPairRequest>(create);
  static TapPairRequest? _defaultInstance;

  @$pb.TagNumber(1)
  DeviceInfo get requester => $_getN(0);
  @$pb.TagNumber(1)
  set requester(DeviceInfo value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRequester() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequester() => $_clearField(1);
  @$pb.TagNumber(1)
  DeviceInfo ensureRequester() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get tapToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set tapToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTapToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearTapToken() => $_clearField(2);
}

class TapPairResponse extends $pb.GeneratedMessage {
  factory TapPairResponse({
    $core.bool? accepted,
    DeviceInfo? responder,
    $core.List<$core.int>? sessionToken,
    $core.String? message,
  }) {
    final result = create();
    if (accepted != null) result.accepted = accepted;
    if (responder != null) result.responder = responder;
    if (sessionToken != null) result.sessionToken = sessionToken;
    if (message != null) result.message = message;
    return result;
  }

  TapPairResponse._();

  factory TapPairResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TapPairResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TapPairResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOM<DeviceInfo>(2, _omitFieldNames ? '' : 'responder',
        subBuilder: DeviceInfo.create)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'sessionToken', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TapPairResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TapPairResponse copyWith(void Function(TapPairResponse) updates) =>
      super.copyWith((message) => updates(message as TapPairResponse))
          as TapPairResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TapPairResponse create() => TapPairResponse._();
  @$core.override
  TapPairResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TapPairResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TapPairResponse>(create);
  static TapPairResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => $_clearField(1);

  @$pb.TagNumber(2)
  DeviceInfo get responder => $_getN(1);
  @$pb.TagNumber(2)
  set responder(DeviceInfo value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasResponder() => $_has(1);
  @$pb.TagNumber(2)
  void clearResponder() => $_clearField(2);
  @$pb.TagNumber(2)
  DeviceInfo ensureResponder() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.List<$core.int> get sessionToken => $_getN(2);
  @$pb.TagNumber(3)
  set sessionToken($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSessionToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearSessionToken() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get message => $_getSZ(3);
  @$pb.TagNumber(4)
  set message($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearMessage() => $_clearField(4);
}

class PairRequest extends $pb.GeneratedMessage {
  factory PairRequest({
    DeviceInfo? requester,
  }) {
    final result = create();
    if (requester != null) result.requester = requester;
    return result;
  }

  PairRequest._();

  factory PairRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PairRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PairRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOM<DeviceInfo>(1, _omitFieldNames ? '' : 'requester',
        subBuilder: DeviceInfo.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairRequest copyWith(void Function(PairRequest) updates) =>
      super.copyWith((message) => updates(message as PairRequest))
          as PairRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PairRequest create() => PairRequest._();
  @$core.override
  PairRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PairRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PairRequest>(create);
  static PairRequest? _defaultInstance;

  @$pb.TagNumber(1)
  DeviceInfo get requester => $_getN(0);
  @$pb.TagNumber(1)
  set requester(DeviceInfo value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRequester() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequester() => $_clearField(1);
  @$pb.TagNumber(1)
  DeviceInfo ensureRequester() => $_ensure(0);
}

class PairResponse extends $pb.GeneratedMessage {
  factory PairResponse({
    $core.bool? accepted,
    DeviceInfo? responder,
    $core.List<$core.int>? sessionToken,
    $core.String? message,
  }) {
    final result = create();
    if (accepted != null) result.accepted = accepted;
    if (responder != null) result.responder = responder;
    if (sessionToken != null) result.sessionToken = sessionToken;
    if (message != null) result.message = message;
    return result;
  }

  PairResponse._();

  factory PairResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PairResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PairResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOM<DeviceInfo>(2, _omitFieldNames ? '' : 'responder',
        subBuilder: DeviceInfo.create)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'sessionToken', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairResponse copyWith(void Function(PairResponse) updates) =>
      super.copyWith((message) => updates(message as PairResponse))
          as PairResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PairResponse create() => PairResponse._();
  @$core.override
  PairResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PairResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PairResponse>(create);
  static PairResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => $_clearField(1);

  @$pb.TagNumber(2)
  DeviceInfo get responder => $_getN(1);
  @$pb.TagNumber(2)
  set responder(DeviceInfo value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasResponder() => $_has(1);
  @$pb.TagNumber(2)
  void clearResponder() => $_clearField(2);
  @$pb.TagNumber(2)
  DeviceInfo ensureResponder() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.List<$core.int> get sessionToken => $_getN(2);
  @$pb.TagNumber(3)
  set sessionToken($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSessionToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearSessionToken() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get message => $_getSZ(3);
  @$pb.TagNumber(4)
  set message($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearMessage() => $_clearField(4);
}

class UnpairRequest extends $pb.GeneratedMessage {
  factory UnpairRequest({
    $core.String? deviceId,
  }) {
    final result = create();
    if (deviceId != null) result.deviceId = deviceId;
    return result;
  }

  UnpairRequest._();

  factory UnpairRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UnpairRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UnpairRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnpairRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnpairRequest copyWith(void Function(UnpairRequest) updates) =>
      super.copyWith((message) => updates(message as UnpairRequest))
          as UnpairRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UnpairRequest create() => UnpairRequest._();
  @$core.override
  UnpairRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UnpairRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UnpairRequest>(create);
  static UnpairRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => $_clearField(1);
}

class UnpairResponse extends $pb.GeneratedMessage {
  factory UnpairResponse({
    $core.bool? ok,
  }) {
    final result = create();
    if (ok != null) result.ok = ok;
    return result;
  }

  UnpairResponse._();

  factory UnpairResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UnpairResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UnpairResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'ok')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnpairResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnpairResponse copyWith(void Function(UnpairResponse) updates) =>
      super.copyWith((message) => updates(message as UnpairResponse))
          as UnpairResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UnpairResponse create() => UnpairResponse._();
  @$core.override
  UnpairResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UnpairResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UnpairResponse>(create);
  static UnpairResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get ok => $_getBF(0);
  @$pb.TagNumber(1)
  set ok($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOk() => $_has(0);
  @$pb.TagNumber(1)
  void clearOk() => $_clearField(1);
}

enum Envelope_Payload {
  hello,
  chat,
  chatDeleted,
  clipboard,
  fileOffer,
  fileAnswer,
  fileCancel,
  syncAck,
  heartbeat,
  linkAuth,
  fileFetch,
  fileData,
  fileDataAck,
  notSet
}

class Envelope extends $pb.GeneratedMessage {
  factory Envelope({
    $core.String? id,
    Hello? hello,
    ChatMessage? chat,
    ChatDeleted? chatDeleted,
    ClipboardSync? clipboard,
    FileOffer? fileOffer,
    FileAnswer? fileAnswer,
    FileCancel? fileCancel,
    SyncAck? syncAck,
    Heartbeat? heartbeat,
    LinkAuth? linkAuth,
    FileFetchRequest? fileFetch,
    FileData? fileData,
    FileDataAck? fileDataAck,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (hello != null) result.hello = hello;
    if (chat != null) result.chat = chat;
    if (chatDeleted != null) result.chatDeleted = chatDeleted;
    if (clipboard != null) result.clipboard = clipboard;
    if (fileOffer != null) result.fileOffer = fileOffer;
    if (fileAnswer != null) result.fileAnswer = fileAnswer;
    if (fileCancel != null) result.fileCancel = fileCancel;
    if (syncAck != null) result.syncAck = syncAck;
    if (heartbeat != null) result.heartbeat = heartbeat;
    if (linkAuth != null) result.linkAuth = linkAuth;
    if (fileFetch != null) result.fileFetch = fileFetch;
    if (fileData != null) result.fileData = fileData;
    if (fileDataAck != null) result.fileDataAck = fileDataAck;
    return result;
  }

  Envelope._();

  factory Envelope.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Envelope.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Envelope_Payload> _Envelope_PayloadByTag = {
    2: Envelope_Payload.hello,
    3: Envelope_Payload.chat,
    4: Envelope_Payload.chatDeleted,
    5: Envelope_Payload.clipboard,
    6: Envelope_Payload.fileOffer,
    7: Envelope_Payload.fileAnswer,
    8: Envelope_Payload.fileCancel,
    9: Envelope_Payload.syncAck,
    10: Envelope_Payload.heartbeat,
    11: Envelope_Payload.linkAuth,
    12: Envelope_Payload.fileFetch,
    13: Envelope_Payload.fileData,
    14: Envelope_Payload.fileDataAck,
    0: Envelope_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Envelope',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..oo(0, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOM<Hello>(2, _omitFieldNames ? '' : 'hello', subBuilder: Hello.create)
    ..aOM<ChatMessage>(3, _omitFieldNames ? '' : 'chat',
        subBuilder: ChatMessage.create)
    ..aOM<ChatDeleted>(4, _omitFieldNames ? '' : 'chatDeleted',
        subBuilder: ChatDeleted.create)
    ..aOM<ClipboardSync>(5, _omitFieldNames ? '' : 'clipboard',
        subBuilder: ClipboardSync.create)
    ..aOM<FileOffer>(6, _omitFieldNames ? '' : 'fileOffer',
        subBuilder: FileOffer.create)
    ..aOM<FileAnswer>(7, _omitFieldNames ? '' : 'fileAnswer',
        subBuilder: FileAnswer.create)
    ..aOM<FileCancel>(8, _omitFieldNames ? '' : 'fileCancel',
        subBuilder: FileCancel.create)
    ..aOM<SyncAck>(9, _omitFieldNames ? '' : 'syncAck',
        subBuilder: SyncAck.create)
    ..aOM<Heartbeat>(10, _omitFieldNames ? '' : 'heartbeat',
        subBuilder: Heartbeat.create)
    ..aOM<LinkAuth>(11, _omitFieldNames ? '' : 'linkAuth',
        subBuilder: LinkAuth.create)
    ..aOM<FileFetchRequest>(12, _omitFieldNames ? '' : 'fileFetch',
        subBuilder: FileFetchRequest.create)
    ..aOM<FileData>(13, _omitFieldNames ? '' : 'fileData',
        subBuilder: FileData.create)
    ..aOM<FileDataAck>(14, _omitFieldNames ? '' : 'fileDataAck',
        subBuilder: FileDataAck.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Envelope clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Envelope copyWith(void Function(Envelope) updates) =>
      super.copyWith((message) => updates(message as Envelope)) as Envelope;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Envelope create() => Envelope._();
  @$core.override
  Envelope createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Envelope getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Envelope>(create);
  static Envelope? _defaultInstance;

  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  Envelope_Payload whichPayload() => _Envelope_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  Hello get hello => $_getN(1);
  @$pb.TagNumber(2)
  set hello(Hello value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasHello() => $_has(1);
  @$pb.TagNumber(2)
  void clearHello() => $_clearField(2);
  @$pb.TagNumber(2)
  Hello ensureHello() => $_ensure(1);

  @$pb.TagNumber(3)
  ChatMessage get chat => $_getN(2);
  @$pb.TagNumber(3)
  set chat(ChatMessage value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasChat() => $_has(2);
  @$pb.TagNumber(3)
  void clearChat() => $_clearField(3);
  @$pb.TagNumber(3)
  ChatMessage ensureChat() => $_ensure(2);

  @$pb.TagNumber(4)
  ChatDeleted get chatDeleted => $_getN(3);
  @$pb.TagNumber(4)
  set chatDeleted(ChatDeleted value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasChatDeleted() => $_has(3);
  @$pb.TagNumber(4)
  void clearChatDeleted() => $_clearField(4);
  @$pb.TagNumber(4)
  ChatDeleted ensureChatDeleted() => $_ensure(3);

  @$pb.TagNumber(5)
  ClipboardSync get clipboard => $_getN(4);
  @$pb.TagNumber(5)
  set clipboard(ClipboardSync value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasClipboard() => $_has(4);
  @$pb.TagNumber(5)
  void clearClipboard() => $_clearField(5);
  @$pb.TagNumber(5)
  ClipboardSync ensureClipboard() => $_ensure(4);

  @$pb.TagNumber(6)
  FileOffer get fileOffer => $_getN(5);
  @$pb.TagNumber(6)
  set fileOffer(FileOffer value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasFileOffer() => $_has(5);
  @$pb.TagNumber(6)
  void clearFileOffer() => $_clearField(6);
  @$pb.TagNumber(6)
  FileOffer ensureFileOffer() => $_ensure(5);

  @$pb.TagNumber(7)
  FileAnswer get fileAnswer => $_getN(6);
  @$pb.TagNumber(7)
  set fileAnswer(FileAnswer value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasFileAnswer() => $_has(6);
  @$pb.TagNumber(7)
  void clearFileAnswer() => $_clearField(7);
  @$pb.TagNumber(7)
  FileAnswer ensureFileAnswer() => $_ensure(6);

  @$pb.TagNumber(8)
  FileCancel get fileCancel => $_getN(7);
  @$pb.TagNumber(8)
  set fileCancel(FileCancel value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasFileCancel() => $_has(7);
  @$pb.TagNumber(8)
  void clearFileCancel() => $_clearField(8);
  @$pb.TagNumber(8)
  FileCancel ensureFileCancel() => $_ensure(7);

  @$pb.TagNumber(9)
  SyncAck get syncAck => $_getN(8);
  @$pb.TagNumber(9)
  set syncAck(SyncAck value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasSyncAck() => $_has(8);
  @$pb.TagNumber(9)
  void clearSyncAck() => $_clearField(9);
  @$pb.TagNumber(9)
  SyncAck ensureSyncAck() => $_ensure(8);

  @$pb.TagNumber(10)
  Heartbeat get heartbeat => $_getN(9);
  @$pb.TagNumber(10)
  set heartbeat(Heartbeat value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasHeartbeat() => $_has(9);
  @$pb.TagNumber(10)
  void clearHeartbeat() => $_clearField(10);
  @$pb.TagNumber(10)
  Heartbeat ensureHeartbeat() => $_ensure(9);

  @$pb.TagNumber(11)
  LinkAuth get linkAuth => $_getN(10);
  @$pb.TagNumber(11)
  set linkAuth(LinkAuth value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasLinkAuth() => $_has(10);
  @$pb.TagNumber(11)
  void clearLinkAuth() => $_clearField(11);
  @$pb.TagNumber(11)
  LinkAuth ensureLinkAuth() => $_ensure(10);

  @$pb.TagNumber(12)
  FileFetchRequest get fileFetch => $_getN(11);
  @$pb.TagNumber(12)
  set fileFetch(FileFetchRequest value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasFileFetch() => $_has(11);
  @$pb.TagNumber(12)
  void clearFileFetch() => $_clearField(12);
  @$pb.TagNumber(12)
  FileFetchRequest ensureFileFetch() => $_ensure(11);

  @$pb.TagNumber(13)
  FileData get fileData => $_getN(12);
  @$pb.TagNumber(13)
  set fileData(FileData value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasFileData() => $_has(12);
  @$pb.TagNumber(13)
  void clearFileData() => $_clearField(13);
  @$pb.TagNumber(13)
  FileData ensureFileData() => $_ensure(12);

  @$pb.TagNumber(14)
  FileDataAck get fileDataAck => $_getN(13);
  @$pb.TagNumber(14)
  set fileDataAck(FileDataAck value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasFileDataAck() => $_has(13);
  @$pb.TagNumber(14)
  void clearFileDataAck() => $_clearField(14);
  @$pb.TagNumber(14)
  FileDataAck ensureFileDataAck() => $_ensure(13);
}

/// 信封式文件数据回执:接收方每写入一帧回报已落盘偏移,
/// 发送方按窗口(8 帧)控制发送节奏,防止慢链路撑爆缓冲。
class FileDataAck extends $pb.GeneratedMessage {
  factory FileDataAck({
    $core.String? fileId,
    $fixnum.Int64? ackedOffset,
  }) {
    final result = create();
    if (fileId != null) result.fileId = fileId;
    if (ackedOffset != null) result.ackedOffset = ackedOffset;
    return result;
  }

  FileDataAck._();

  factory FileDataAck.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileDataAck.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileDataAck',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'fileId')
    ..aInt64(2, _omitFieldNames ? '' : 'ackedOffset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileDataAck clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileDataAck copyWith(void Function(FileDataAck) updates) =>
      super.copyWith((message) => updates(message as FileDataAck))
          as FileDataAck;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileDataAck create() => FileDataAck._();
  @$core.override
  FileDataAck createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileDataAck getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FileDataAck>(create);
  static FileDataAck? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get fileId => $_getSZ(0);
  @$pb.TagNumber(1)
  set fileId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFileId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFileId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get ackedOffset => $_getI64(1);
  @$pb.TagNumber(2)
  set ackedOffset($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAckedOffset() => $_has(1);
  @$pb.TagNumber(2)
  void clearAckedOffset() => $_clearField(2);
}

/// 外部传输链路(WebRTC DataChannel 等)的第一个信封:
/// 携带设备 ID + 配对令牌,等价于 gRPC 元数据鉴权。校验不过立即断链。
class LinkAuth extends $pb.GeneratedMessage {
  factory LinkAuth({
    $core.String? deviceId,
    $core.String? token,
  }) {
    final result = create();
    if (deviceId != null) result.deviceId = deviceId;
    if (token != null) result.token = token;
    return result;
  }

  LinkAuth._();

  factory LinkAuth.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LinkAuth.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LinkAuth',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..aOS(2, _omitFieldNames ? '' : 'token')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinkAuth clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinkAuth copyWith(void Function(LinkAuth) updates) =>
      super.copyWith((message) => updates(message as LinkAuth)) as LinkAuth;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LinkAuth create() => LinkAuth._();
  @$core.override
  LinkAuth createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LinkAuth getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LinkAuth>(create);
  static LinkAuth? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get token => $_getSZ(1);
  @$pb.TagNumber(2)
  set token($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearToken() => $_clearField(2);
}

/// 信封式文件拉取请求(当对端无 gRPC 可达地址时使用,如 WebRTC 链路)。
class FileFetchRequest extends $pb.GeneratedMessage {
  factory FileFetchRequest({
    $core.String? fileId,
    $fixnum.Int64? offset,
  }) {
    final result = create();
    if (fileId != null) result.fileId = fileId;
    if (offset != null) result.offset = offset;
    return result;
  }

  FileFetchRequest._();

  factory FileFetchRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileFetchRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileFetchRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'fileId')
    ..aInt64(2, _omitFieldNames ? '' : 'offset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileFetchRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileFetchRequest copyWith(void Function(FileFetchRequest) updates) =>
      super.copyWith((message) => updates(message as FileFetchRequest))
          as FileFetchRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileFetchRequest create() => FileFetchRequest._();
  @$core.override
  FileFetchRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileFetchRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FileFetchRequest>(create);
  static FileFetchRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get fileId => $_getSZ(0);
  @$pb.TagNumber(1)
  set fileId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFileId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFileId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get offset => $_getI64(1);
  @$pb.TagNumber(2)
  set offset($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOffset() => $_has(1);
  @$pb.TagNumber(2)
  void clearOffset() => $_clearField(2);
}

/// 信封式文件数据帧。单帧 ≤ 64 KiB(WebRTC DataChannel 安全消息尺寸)。
class FileData extends $pb.GeneratedMessage {
  factory FileData({
    $core.String? fileId,
    $fixnum.Int64? offset,
    $core.List<$core.int>? data,
    $core.bool? last,
  }) {
    final result = create();
    if (fileId != null) result.fileId = fileId;
    if (offset != null) result.offset = offset;
    if (data != null) result.data = data;
    if (last != null) result.last = last;
    return result;
  }

  FileData._();

  factory FileData.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileData.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileData',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'fileId')
    ..aInt64(2, _omitFieldNames ? '' : 'offset')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOB(4, _omitFieldNames ? '' : 'last')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileData clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileData copyWith(void Function(FileData) updates) =>
      super.copyWith((message) => updates(message as FileData)) as FileData;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileData create() => FileData._();
  @$core.override
  FileData createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileData getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FileData>(create);
  static FileData? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get fileId => $_getSZ(0);
  @$pb.TagNumber(1)
  set fileId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFileId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFileId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get offset => $_getI64(1);
  @$pb.TagNumber(2)
  set offset($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOffset() => $_has(1);
  @$pb.TagNumber(2)
  void clearOffset() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get data => $_getN(2);
  @$pb.TagNumber(3)
  set data($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasData() => $_has(2);
  @$pb.TagNumber(3)
  void clearData() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get last => $_getBF(3);
  @$pb.TagNumber(4)
  set last($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLast() => $_has(3);
  @$pb.TagNumber(4)
  void clearLast() => $_clearField(4);
}

/// 连接建立后的第一个信封:告知对方"我已经应用到你的第 N 条 op",
/// 对方据此从 ops 表补发 (N, +∞) 的全部操作,实现断线重连最终一致。
class Hello extends $pb.GeneratedMessage {
  factory Hello({
    $fixnum.Int64? appliedPeerSeq,
  }) {
    final result = create();
    if (appliedPeerSeq != null) result.appliedPeerSeq = appliedPeerSeq;
    return result;
  }

  Hello._();

  factory Hello.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Hello.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Hello',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'appliedPeerSeq')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Hello clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Hello copyWith(void Function(Hello) updates) =>
      super.copyWith((message) => updates(message as Hello)) as Hello;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Hello create() => Hello._();
  @$core.override
  Hello createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Hello getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Hello>(create);
  static Hello? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get appliedPeerSeq => $_getI64(0);
  @$pb.TagNumber(1)
  set appliedPeerSeq($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAppliedPeerSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearAppliedPeerSeq() => $_clearField(1);
}

/// 聊天消息。两端以 msg_id 为准各自落库,内容字节级一致。
class ChatMessage extends $pb.GeneratedMessage {
  factory ChatMessage({
    $core.String? msgId,
    $fixnum.Int64? opSeq,
    $fixnum.Int64? lamport,
    $fixnum.Int64? createdAtMs,
    $core.int? kind,
    $core.String? text,
    $core.String? fileId,
    $core.String? fileName,
    $fixnum.Int64? fileSize,
    $core.String? fileSha256,
  }) {
    final result = create();
    if (msgId != null) result.msgId = msgId;
    if (opSeq != null) result.opSeq = opSeq;
    if (lamport != null) result.lamport = lamport;
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    if (kind != null) result.kind = kind;
    if (text != null) result.text = text;
    if (fileId != null) result.fileId = fileId;
    if (fileName != null) result.fileName = fileName;
    if (fileSize != null) result.fileSize = fileSize;
    if (fileSha256 != null) result.fileSha256 = fileSha256;
    return result;
  }

  ChatMessage._();

  factory ChatMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChatMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChatMessage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'msgId')
    ..aInt64(2, _omitFieldNames ? '' : 'opSeq')
    ..aInt64(3, _omitFieldNames ? '' : 'lamport')
    ..aInt64(4, _omitFieldNames ? '' : 'createdAtMs')
    ..aI(5, _omitFieldNames ? '' : 'kind')
    ..aOS(6, _omitFieldNames ? '' : 'text')
    ..aOS(7, _omitFieldNames ? '' : 'fileId')
    ..aOS(8, _omitFieldNames ? '' : 'fileName')
    ..aInt64(9, _omitFieldNames ? '' : 'fileSize')
    ..aOS(10, _omitFieldNames ? '' : 'fileSha256')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatMessage copyWith(void Function(ChatMessage) updates) =>
      super.copyWith((message) => updates(message as ChatMessage))
          as ChatMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatMessage create() => ChatMessage._();
  @$core.override
  ChatMessage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChatMessage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChatMessage>(create);
  static ChatMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get msgId => $_getSZ(0);
  @$pb.TagNumber(1)
  set msgId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMsgId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMsgId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get opSeq => $_getI64(1);
  @$pb.TagNumber(2)
  set opSeq($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOpSeq() => $_has(1);
  @$pb.TagNumber(2)
  void clearOpSeq() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get lamport => $_getI64(2);
  @$pb.TagNumber(3)
  set lamport($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLamport() => $_has(2);
  @$pb.TagNumber(3)
  void clearLamport() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get createdAtMs => $_getI64(3);
  @$pb.TagNumber(4)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCreatedAtMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearCreatedAtMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get kind => $_getIZ(4);
  @$pb.TagNumber(5)
  set kind($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasKind() => $_has(4);
  @$pb.TagNumber(5)
  void clearKind() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get text => $_getSZ(5);
  @$pb.TagNumber(6)
  set text($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasText() => $_has(5);
  @$pb.TagNumber(6)
  void clearText() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get fileId => $_getSZ(6);
  @$pb.TagNumber(7)
  set fileId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasFileId() => $_has(6);
  @$pb.TagNumber(7)
  void clearFileId() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get fileName => $_getSZ(7);
  @$pb.TagNumber(8)
  set fileName($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasFileName() => $_has(7);
  @$pb.TagNumber(8)
  void clearFileName() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get fileSize => $_getI64(8);
  @$pb.TagNumber(9)
  set fileSize($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasFileSize() => $_has(8);
  @$pb.TagNumber(9)
  void clearFileSize() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get fileSha256 => $_getSZ(9);
  @$pb.TagNumber(10)
  set fileSha256($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasFileSha256() => $_has(9);
  @$pb.TagNumber(10)
  void clearFileSha256() => $_clearField(10);
}

/// 删除操作(墓碑)。Telegram 模式:一端删除,另一端同步硬删除。
/// 对端不在线时本操作留在 ops 表,重连后补发。
class ChatDeleted extends $pb.GeneratedMessage {
  factory ChatDeleted({
    $fixnum.Int64? opSeq,
    $core.Iterable<$core.String>? msgIds,
    $core.bool? clearAll,
  }) {
    final result = create();
    if (opSeq != null) result.opSeq = opSeq;
    if (msgIds != null) result.msgIds.addAll(msgIds);
    if (clearAll != null) result.clearAll = clearAll;
    return result;
  }

  ChatDeleted._();

  factory ChatDeleted.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChatDeleted.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChatDeleted',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'opSeq')
    ..pPS(2, _omitFieldNames ? '' : 'msgIds')
    ..aOB(3, _omitFieldNames ? '' : 'clearAll')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatDeleted clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatDeleted copyWith(void Function(ChatDeleted) updates) =>
      super.copyWith((message) => updates(message as ChatDeleted))
          as ChatDeleted;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatDeleted create() => ChatDeleted._();
  @$core.override
  ChatDeleted createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChatDeleted getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChatDeleted>(create);
  static ChatDeleted? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get opSeq => $_getI64(0);
  @$pb.TagNumber(1)
  set opSeq($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOpSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearOpSeq() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get msgIds => $_getList(1);

  @$pb.TagNumber(3)
  $core.bool get clearAll => $_getBF(2);
  @$pb.TagNumber(3)
  set clearAll($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClearAll() => $_has(2);
  @$pb.TagNumber(3)
  void clearClearAll() => $_clearField(3);
}

/// 剪贴板同步(小文本直接走消息通道;图片等大内容走文件通道)。
class ClipboardSync extends $pb.GeneratedMessage {
  factory ClipboardSync({
    $core.String? text,
    $fixnum.Int64? atMs,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (atMs != null) result.atMs = atMs;
    return result;
  }

  ClipboardSync._();

  factory ClipboardSync.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ClipboardSync.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ClipboardSync',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aInt64(2, _omitFieldNames ? '' : 'atMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClipboardSync clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClipboardSync copyWith(void Function(ClipboardSync) updates) =>
      super.copyWith((message) => updates(message as ClipboardSync))
          as ClipboardSync;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClipboardSync create() => ClipboardSync._();
  @$core.override
  ClipboardSync createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ClipboardSync getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ClipboardSync>(create);
  static ClipboardSync? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get atMs => $_getI64(1);
  @$pb.TagNumber(2)
  set atMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAtMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearAtMs() => $_clearField(2);
}

/// 文件传输协商:先发 Offer,对端回应 Answer(可带 offset 实现断点续传),
/// 同意后发送方另起 TransferService.SendFile 流传输数据。
class FileOffer extends $pb.GeneratedMessage {
  factory FileOffer({
    $core.String? fileId,
    $core.String? name,
    $fixnum.Int64? size,
    $core.String? sha256Hex,
    $core.String? mime,
  }) {
    final result = create();
    if (fileId != null) result.fileId = fileId;
    if (name != null) result.name = name;
    if (size != null) result.size = size;
    if (sha256Hex != null) result.sha256Hex = sha256Hex;
    if (mime != null) result.mime = mime;
    return result;
  }

  FileOffer._();

  factory FileOffer.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileOffer.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileOffer',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'fileId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aInt64(3, _omitFieldNames ? '' : 'size')
    ..aOS(4, _omitFieldNames ? '' : 'sha256Hex')
    ..aOS(5, _omitFieldNames ? '' : 'mime')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileOffer clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileOffer copyWith(void Function(FileOffer) updates) =>
      super.copyWith((message) => updates(message as FileOffer)) as FileOffer;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileOffer create() => FileOffer._();
  @$core.override
  FileOffer createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileOffer getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FileOffer>(create);
  static FileOffer? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get fileId => $_getSZ(0);
  @$pb.TagNumber(1)
  set fileId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFileId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFileId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get size => $_getI64(2);
  @$pb.TagNumber(3)
  set size($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearSize() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get sha256Hex => $_getSZ(3);
  @$pb.TagNumber(4)
  set sha256Hex($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSha256Hex() => $_has(3);
  @$pb.TagNumber(4)
  void clearSha256Hex() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get mime => $_getSZ(4);
  @$pb.TagNumber(5)
  set mime($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMime() => $_has(4);
  @$pb.TagNumber(5)
  void clearMime() => $_clearField(5);
}

class FileAnswer extends $pb.GeneratedMessage {
  factory FileAnswer({
    $core.String? fileId,
    $core.bool? accept,
    $fixnum.Int64? offset,
  }) {
    final result = create();
    if (fileId != null) result.fileId = fileId;
    if (accept != null) result.accept = accept;
    if (offset != null) result.offset = offset;
    return result;
  }

  FileAnswer._();

  factory FileAnswer.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileAnswer.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileAnswer',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'fileId')
    ..aOB(2, _omitFieldNames ? '' : 'accept')
    ..aInt64(3, _omitFieldNames ? '' : 'offset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileAnswer clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileAnswer copyWith(void Function(FileAnswer) updates) =>
      super.copyWith((message) => updates(message as FileAnswer)) as FileAnswer;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileAnswer create() => FileAnswer._();
  @$core.override
  FileAnswer createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileAnswer getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FileAnswer>(create);
  static FileAnswer? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get fileId => $_getSZ(0);
  @$pb.TagNumber(1)
  set fileId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFileId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFileId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get accept => $_getBF(1);
  @$pb.TagNumber(2)
  set accept($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAccept() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccept() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get offset => $_getI64(2);
  @$pb.TagNumber(3)
  set offset($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOffset() => $_has(2);
  @$pb.TagNumber(3)
  void clearOffset() => $_clearField(3);
}

class FileCancel extends $pb.GeneratedMessage {
  factory FileCancel({
    $core.String? fileId,
    $core.String? reason,
  }) {
    final result = create();
    if (fileId != null) result.fileId = fileId;
    if (reason != null) result.reason = reason;
    return result;
  }

  FileCancel._();

  factory FileCancel.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileCancel.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileCancel',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'fileId')
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileCancel clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileCancel copyWith(void Function(FileCancel) updates) =>
      super.copyWith((message) => updates(message as FileCancel)) as FileCancel;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileCancel create() => FileCancel._();
  @$core.override
  FileCancel createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileCancel getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FileCancel>(create);
  static FileCancel? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get fileId => $_getSZ(0);
  @$pb.TagNumber(1)
  set fileId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFileId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFileId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);
}

/// 应用回执:告知对方哪些信封已落库、对方 op 已应用到第几条(用于 ops 表压缩)。
class SyncAck extends $pb.GeneratedMessage {
  factory SyncAck({
    $core.Iterable<$core.String>? envelopeIds,
    $fixnum.Int64? appliedPeerSeq,
  }) {
    final result = create();
    if (envelopeIds != null) result.envelopeIds.addAll(envelopeIds);
    if (appliedPeerSeq != null) result.appliedPeerSeq = appliedPeerSeq;
    return result;
  }

  SyncAck._();

  factory SyncAck.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SyncAck.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SyncAck',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'envelopeIds')
    ..aInt64(2, _omitFieldNames ? '' : 'appliedPeerSeq')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SyncAck clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SyncAck copyWith(void Function(SyncAck) updates) =>
      super.copyWith((message) => updates(message as SyncAck)) as SyncAck;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SyncAck create() => SyncAck._();
  @$core.override
  SyncAck createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SyncAck getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SyncAck>(create);
  static SyncAck? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get envelopeIds => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get appliedPeerSeq => $_getI64(1);
  @$pb.TagNumber(2)
  set appliedPeerSeq($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAppliedPeerSeq() => $_has(1);
  @$pb.TagNumber(2)
  void clearAppliedPeerSeq() => $_clearField(2);
}

class Heartbeat extends $pb.GeneratedMessage {
  factory Heartbeat({
    $fixnum.Int64? atMs,
  }) {
    final result = create();
    if (atMs != null) result.atMs = atMs;
    return result;
  }

  Heartbeat._();

  factory Heartbeat.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Heartbeat.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Heartbeat',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'atMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Heartbeat clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Heartbeat copyWith(void Function(Heartbeat) updates) =>
      super.copyWith((message) => updates(message as Heartbeat)) as Heartbeat;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Heartbeat create() => Heartbeat._();
  @$core.override
  Heartbeat createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Heartbeat getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Heartbeat>(create);
  static Heartbeat? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get atMs => $_getI64(0);
  @$pb.TagNumber(1)
  set atMs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtMs() => $_clearField(1);
}

enum FileChunk_Part { head, data, notSet }

class FileChunk extends $pb.GeneratedMessage {
  factory FileChunk({
    FileHead? head,
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (head != null) result.head = head;
    if (data != null) result.data = data;
    return result;
  }

  FileChunk._();

  factory FileChunk.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileChunk.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, FileChunk_Part> _FileChunk_PartByTag = {
    1: FileChunk_Part.head,
    2: FileChunk_Part.data,
    0: FileChunk_Part.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileChunk',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 2])
    ..aOM<FileHead>(1, _omitFieldNames ? '' : 'head',
        subBuilder: FileHead.create)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileChunk clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileChunk copyWith(void Function(FileChunk) updates) =>
      super.copyWith((message) => updates(message as FileChunk)) as FileChunk;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileChunk create() => FileChunk._();
  @$core.override
  FileChunk createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileChunk getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FileChunk>(create);
  static FileChunk? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  FileChunk_Part whichPart() => _FileChunk_PartByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  void clearPart() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  FileHead get head => $_getN(0);
  @$pb.TagNumber(1)
  set head(FileHead value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasHead() => $_has(0);
  @$pb.TagNumber(1)
  void clearHead() => $_clearField(1);
  @$pb.TagNumber(1)
  FileHead ensureHead() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.List<$core.int> get data => $_getN(1);
  @$pb.TagNumber(2)
  set data($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasData() => $_has(1);
  @$pb.TagNumber(2)
  void clearData() => $_clearField(2);
}

class FileHead extends $pb.GeneratedMessage {
  factory FileHead({
    $core.String? fileId,
    $core.String? name,
    $fixnum.Int64? offset,
    $fixnum.Int64? totalSize,
    $core.String? sha256Hex,
  }) {
    final result = create();
    if (fileId != null) result.fileId = fileId;
    if (name != null) result.name = name;
    if (offset != null) result.offset = offset;
    if (totalSize != null) result.totalSize = totalSize;
    if (sha256Hex != null) result.sha256Hex = sha256Hex;
    return result;
  }

  FileHead._();

  factory FileHead.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileHead.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileHead',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'fileId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aInt64(3, _omitFieldNames ? '' : 'offset')
    ..aInt64(4, _omitFieldNames ? '' : 'totalSize')
    ..aOS(5, _omitFieldNames ? '' : 'sha256Hex')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileHead clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileHead copyWith(void Function(FileHead) updates) =>
      super.copyWith((message) => updates(message as FileHead)) as FileHead;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileHead create() => FileHead._();
  @$core.override
  FileHead createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileHead getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FileHead>(create);
  static FileHead? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get fileId => $_getSZ(0);
  @$pb.TagNumber(1)
  set fileId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFileId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFileId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get offset => $_getI64(2);
  @$pb.TagNumber(3)
  set offset($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOffset() => $_has(2);
  @$pb.TagNumber(3)
  void clearOffset() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalSize => $_getI64(3);
  @$pb.TagNumber(4)
  set totalSize($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTotalSize() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalSize() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get sha256Hex => $_getSZ(4);
  @$pb.TagNumber(5)
  set sha256Hex($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSha256Hex() => $_has(4);
  @$pb.TagNumber(5)
  void clearSha256Hex() => $_clearField(5);
}

class FetchRequest extends $pb.GeneratedMessage {
  factory FetchRequest({
    $core.String? fileId,
    $fixnum.Int64? offset,
  }) {
    final result = create();
    if (fileId != null) result.fileId = fileId;
    if (offset != null) result.offset = offset;
    return result;
  }

  FetchRequest._();

  factory FetchRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FetchRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FetchRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'fileId')
    ..aInt64(2, _omitFieldNames ? '' : 'offset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FetchRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FetchRequest copyWith(void Function(FetchRequest) updates) =>
      super.copyWith((message) => updates(message as FetchRequest))
          as FetchRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FetchRequest create() => FetchRequest._();
  @$core.override
  FetchRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FetchRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FetchRequest>(create);
  static FetchRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get fileId => $_getSZ(0);
  @$pb.TagNumber(1)
  set fileId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFileId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFileId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get offset => $_getI64(1);
  @$pb.TagNumber(2)
  set offset($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOffset() => $_has(1);
  @$pb.TagNumber(2)
  void clearOffset() => $_clearField(2);
}

class FileResult extends $pb.GeneratedMessage {
  factory FileResult({
    $core.bool? ok,
    $fixnum.Int64? receivedBytes,
    $core.bool? sha256Ok,
    $core.String? message,
  }) {
    final result = create();
    if (ok != null) result.ok = ok;
    if (receivedBytes != null) result.receivedBytes = receivedBytes;
    if (sha256Ok != null) result.sha256Ok = sha256Ok;
    if (message != null) result.message = message;
    return result;
  }

  FileResult._();

  factory FileResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FileResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'littlelaw.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'ok')
    ..aInt64(2, _omitFieldNames ? '' : 'receivedBytes')
    ..aOB(3, _omitFieldNames ? '' : 'sha256Ok')
    ..aOS(4, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileResult copyWith(void Function(FileResult) updates) =>
      super.copyWith((message) => updates(message as FileResult)) as FileResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileResult create() => FileResult._();
  @$core.override
  FileResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FileResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FileResult>(create);
  static FileResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get ok => $_getBF(0);
  @$pb.TagNumber(1)
  set ok($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOk() => $_has(0);
  @$pb.TagNumber(1)
  void clearOk() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get receivedBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set receivedBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReceivedBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearReceivedBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get sha256Ok => $_getBF(2);
  @$pb.TagNumber(3)
  set sha256Ok($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSha256Ok() => $_has(2);
  @$pb.TagNumber(3)
  void clearSha256Ok() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get message => $_getSZ(3);
  @$pb.TagNumber(4)
  set message($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearMessage() => $_clearField(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
