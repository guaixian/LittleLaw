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

import 'package:protobuf/protobuf.dart' as $pb;

import 'littlelaw.pb.dart' as $0;
import 'littlelaw.pbjson.dart';

export 'littlelaw.pb.dart';

abstract class PairingServiceBase extends $pb.GeneratedService {
  $async.Future<$0.PairResponse> requestPair(
      $pb.ServerContext ctx, $0.PairRequest request);
  $async.Future<$0.TapPairResponse> pairWithTap(
      $pb.ServerContext ctx, $0.TapPairRequest request);
  $async.Future<$0.DeliverAnswerResponse> deliverAnswer(
      $pb.ServerContext ctx, $0.DeliverAnswerRequest request);
  $async.Future<$0.UnpairResponse> unpair(
      $pb.ServerContext ctx, $0.UnpairRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'RequestPair':
        return $0.PairRequest();
      case 'PairWithTap':
        return $0.TapPairRequest();
      case 'DeliverAnswer':
        return $0.DeliverAnswerRequest();
      case 'Unpair':
        return $0.UnpairRequest();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'RequestPair':
        return requestPair(ctx, request as $0.PairRequest);
      case 'PairWithTap':
        return pairWithTap(ctx, request as $0.TapPairRequest);
      case 'DeliverAnswer':
        return deliverAnswer(ctx, request as $0.DeliverAnswerRequest);
      case 'Unpair':
        return unpair(ctx, request as $0.UnpairRequest);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => PairingServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => PairingServiceBase$messageJson;
}

abstract class SyncServiceBase extends $pb.GeneratedService {
  $async.Future<$0.Envelope> channel(
      $pb.ServerContext ctx, $0.Envelope request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Channel':
        return $0.Envelope();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Channel':
        return channel(ctx, request as $0.Envelope);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => SyncServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => SyncServiceBase$messageJson;
}

abstract class TransferServiceBase extends $pb.GeneratedService {
  $async.Future<$0.FileResult> sendFile(
      $pb.ServerContext ctx, $0.FileChunk request);
  $async.Future<$0.FileChunk> fetchFile(
      $pb.ServerContext ctx, $0.FetchRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'SendFile':
        return $0.FileChunk();
      case 'FetchFile':
        return $0.FetchRequest();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'SendFile':
        return sendFile(ctx, request as $0.FileChunk);
      case 'FetchFile':
        return fetchFile(ctx, request as $0.FetchRequest);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => TransferServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => TransferServiceBase$messageJson;
}
