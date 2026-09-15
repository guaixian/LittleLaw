// This is a generated file - do not edit.
//
// Generated from littlelaw.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'littlelaw.pb.dart' as $0;

export 'littlelaw.pb.dart';

@$pb.GrpcServiceName('littlelaw.v1.PairingService')
class PairingServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  PairingServiceClient(super.channel, {super.options, super.interceptors});

  /// 请求配对。双方各自用对方证书指纹计算相同 PIN 并肉眼核对,
  /// 被请求方用户点击同意后返回一次性会话令牌(此时**未入账**)。
  /// 发起方核验 TLS 观测指纹与响应宣称一致后,调 ConfirmPair 提交——
  /// 两阶段提交:响应方只在收到发起方身份密钥签名确认后才落库,
  /// 防止"发起方已发现中间人放弃,响应方却已入账"的单边提交劫持。
  $grpc.ResponseFuture<$0.PairResponse> requestPair(
    $0.PairRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$requestPair, request, options: options);
  }

  $grpc.ResponseFuture<$0.PairConfirmResponse> confirmPair(
    $0.PairConfirmRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$confirmPair, request, options: options);
  }

  /// 一碰/一扫配对(免 PIN):请求方携带通过物理通道(NFC 触碰 /
  /// 当面扫码)获得的一次性令牌,证明物理在场;服务端比对有效窗口内的
  /// tap_token 后签发会话令牌并双端入账。
  $grpc.ResponseFuture<$0.TapPairResponse> pairWithTap(
    $0.TapPairRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$pairWithTap, request, options: options);
  }

  /// 应答自动回传(WebRTC 远程配对):受邀方扫描邀请后,若邀请方地址
  /// 可达,直接把 answer 引导包推回给邀请方,免人工复制粘贴。
  /// 安全性:offer_token 即"持有了邀请二维码"的物理证明。
  $grpc.ResponseFuture<$0.DeliverAnswerResponse> deliverAnswer(
    $0.DeliverAnswerRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$deliverAnswer, request, options: options);
  }

  /// 解除配对:双端同时删除对方信任记录(需要有效会话令牌)。
  $grpc.ResponseFuture<$0.UnpairResponse> unpair(
    $0.UnpairRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$unpair, request, options: options);
  }

  /// 取消配对请求(发起方主动取消,无需认证):被请求方收到后
  /// 立即完成挂起的 requestPair 为"拒绝",不再入账。
  $grpc.ResponseFuture<$0.PairCancelResponse> cancelPair(
    $0.PairCancelRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$cancelPair, request, options: options);
  }

  // method descriptors

  static final _$requestPair =
      $grpc.ClientMethod<$0.PairRequest, $0.PairResponse>(
          '/littlelaw.v1.PairingService/RequestPair',
          ($0.PairRequest value) => value.writeToBuffer(),
          $0.PairResponse.fromBuffer);
  static final _$confirmPair =
      $grpc.ClientMethod<$0.PairConfirmRequest, $0.PairConfirmResponse>(
          '/littlelaw.v1.PairingService/ConfirmPair',
          ($0.PairConfirmRequest value) => value.writeToBuffer(),
          $0.PairConfirmResponse.fromBuffer);
  static final _$pairWithTap =
      $grpc.ClientMethod<$0.TapPairRequest, $0.TapPairResponse>(
          '/littlelaw.v1.PairingService/PairWithTap',
          ($0.TapPairRequest value) => value.writeToBuffer(),
          $0.TapPairResponse.fromBuffer);
  static final _$deliverAnswer =
      $grpc.ClientMethod<$0.DeliverAnswerRequest, $0.DeliverAnswerResponse>(
          '/littlelaw.v1.PairingService/DeliverAnswer',
          ($0.DeliverAnswerRequest value) => value.writeToBuffer(),
          $0.DeliverAnswerResponse.fromBuffer);
  static final _$unpair =
      $grpc.ClientMethod<$0.UnpairRequest, $0.UnpairResponse>(
          '/littlelaw.v1.PairingService/Unpair',
          ($0.UnpairRequest value) => value.writeToBuffer(),
          $0.UnpairResponse.fromBuffer);
  static final _$cancelPair =
      $grpc.ClientMethod<$0.PairCancelRequest, $0.PairCancelResponse>(
          '/littlelaw.v1.PairingService/CancelPair',
          ($0.PairCancelRequest value) => value.writeToBuffer(),
          $0.PairCancelResponse.fromBuffer);
}

@$pb.GrpcServiceName('littlelaw.v1.PairingService')
abstract class PairingServiceBase extends $grpc.Service {
  $core.String get $name => 'littlelaw.v1.PairingService';

  PairingServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.PairRequest, $0.PairResponse>(
        'RequestPair',
        requestPair_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.PairRequest.fromBuffer(value),
        ($0.PairResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.PairConfirmRequest, $0.PairConfirmResponse>(
            'ConfirmPair',
            confirmPair_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.PairConfirmRequest.fromBuffer(value),
            ($0.PairConfirmResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.TapPairRequest, $0.TapPairResponse>(
        'PairWithTap',
        pairWithTap_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.TapPairRequest.fromBuffer(value),
        ($0.TapPairResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.DeliverAnswerRequest, $0.DeliverAnswerResponse>(
            'DeliverAnswer',
            deliverAnswer_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.DeliverAnswerRequest.fromBuffer(value),
            ($0.DeliverAnswerResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UnpairRequest, $0.UnpairResponse>(
        'Unpair',
        unpair_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.UnpairRequest.fromBuffer(value),
        ($0.UnpairResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.PairCancelRequest, $0.PairCancelResponse>(
        'CancelPair',
        cancelPair_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.PairCancelRequest.fromBuffer(value),
        ($0.PairCancelResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.PairResponse> requestPair_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.PairRequest> $request) async {
    return requestPair($call, await $request);
  }

  $async.Future<$0.PairResponse> requestPair(
      $grpc.ServiceCall call, $0.PairRequest request);

  $async.Future<$0.PairConfirmResponse> confirmPair_Pre($grpc.ServiceCall $call,
      $async.Future<$0.PairConfirmRequest> $request) async {
    return confirmPair($call, await $request);
  }

  $async.Future<$0.PairConfirmResponse> confirmPair(
      $grpc.ServiceCall call, $0.PairConfirmRequest request);

  $async.Future<$0.TapPairResponse> pairWithTap_Pre($grpc.ServiceCall $call,
      $async.Future<$0.TapPairRequest> $request) async {
    return pairWithTap($call, await $request);
  }

  $async.Future<$0.TapPairResponse> pairWithTap(
      $grpc.ServiceCall call, $0.TapPairRequest request);

  $async.Future<$0.DeliverAnswerResponse> deliverAnswer_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DeliverAnswerRequest> $request) async {
    return deliverAnswer($call, await $request);
  }

  $async.Future<$0.DeliverAnswerResponse> deliverAnswer(
      $grpc.ServiceCall call, $0.DeliverAnswerRequest request);

  $async.Future<$0.UnpairResponse> unpair_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.UnpairRequest> $request) async {
    return unpair($call, await $request);
  }

  $async.Future<$0.UnpairResponse> unpair(
      $grpc.ServiceCall call, $0.UnpairRequest request);

  $async.Future<$0.PairCancelResponse> cancelPair_Pre($grpc.ServiceCall $call,
      $async.Future<$0.PairCancelRequest> $request) async {
    return cancelPair($call, await $request);
  }

  $async.Future<$0.PairCancelResponse> cancelPair(
      $grpc.ServiceCall call, $0.PairCancelRequest request);
}

@$pb.GrpcServiceName('littlelaw.v1.SyncService')
class SyncServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  SyncServiceClient(super.channel, {super.options, super.interceptors});

  /// 双向流。连接建立后双方互发 Hello 交换同步游标,
  /// 随后按需推送各类事件。对端不在线的事件本地落 ops 表,重连补发。
  $grpc.ResponseStream<$0.Envelope> channel(
    $async.Stream<$0.Envelope> request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$channel, request, options: options);
  }

  // method descriptors

  static final _$channel = $grpc.ClientMethod<$0.Envelope, $0.Envelope>(
      '/littlelaw.v1.SyncService/Channel',
      ($0.Envelope value) => value.writeToBuffer(),
      $0.Envelope.fromBuffer);
}

@$pb.GrpcServiceName('littlelaw.v1.SyncService')
abstract class SyncServiceBase extends $grpc.Service {
  $core.String get $name => 'littlelaw.v1.SyncService';

  SyncServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.Envelope, $0.Envelope>(
        'Channel',
        channel,
        true,
        true,
        ($core.List<$core.int> value) => $0.Envelope.fromBuffer(value),
        ($0.Envelope value) => value.writeToBuffer()));
  }

  $async.Stream<$0.Envelope> channel(
      $grpc.ServiceCall call, $async.Stream<$0.Envelope> request);
}

@$pb.GrpcServiceName('littlelaw.v1.TransferService')
class TransferServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  TransferServiceClient(super.channel, {super.options, super.interceptors});

  /// 客户端流上传。首帧必须是 FileHead,后续为数据帧。
  /// 接收方落盘到 <inbox>/<file_id>.part,完成后校验 SHA-256 并重命名。
  $grpc.ResponseFuture<$0.FileResult> sendFile(
    $async.Stream<$0.FileChunk> request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$sendFile, request, options: options).single;
  }

  /// 主动拉取(用于接收方在中断后重新拉取剩余部分)。
  $grpc.ResponseStream<$0.FileChunk> fetchFile(
    $0.FetchRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$fetchFile, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$sendFile = $grpc.ClientMethod<$0.FileChunk, $0.FileResult>(
      '/littlelaw.v1.TransferService/SendFile',
      ($0.FileChunk value) => value.writeToBuffer(),
      $0.FileResult.fromBuffer);
  static final _$fetchFile = $grpc.ClientMethod<$0.FetchRequest, $0.FileChunk>(
      '/littlelaw.v1.TransferService/FetchFile',
      ($0.FetchRequest value) => value.writeToBuffer(),
      $0.FileChunk.fromBuffer);
}

@$pb.GrpcServiceName('littlelaw.v1.TransferService')
abstract class TransferServiceBase extends $grpc.Service {
  $core.String get $name => 'littlelaw.v1.TransferService';

  TransferServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.FileChunk, $0.FileResult>(
        'SendFile',
        sendFile,
        true,
        false,
        ($core.List<$core.int> value) => $0.FileChunk.fromBuffer(value),
        ($0.FileResult value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.FetchRequest, $0.FileChunk>(
        'FetchFile',
        fetchFile_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.FetchRequest.fromBuffer(value),
        ($0.FileChunk value) => value.writeToBuffer()));
  }

  $async.Future<$0.FileResult> sendFile(
      $grpc.ServiceCall call, $async.Stream<$0.FileChunk> request);

  $async.Stream<$0.FileChunk> fetchFile_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.FetchRequest> $request) async* {
    yield* fetchFile($call, await $request);
  }

  $async.Stream<$0.FileChunk> fetchFile(
      $grpc.ServiceCall call, $0.FetchRequest request);
}
