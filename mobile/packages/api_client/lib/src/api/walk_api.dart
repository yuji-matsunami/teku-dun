//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:teku_dun_api_client/src/api_util.dart';
import 'package:teku_dun_api_client/src/model/error_response.dart';
import 'package:teku_dun_api_client/src/model/session_request.dart';

class WalkApi {

  final Dio _dio;

  final Serializers _serializers;

  const WalkApi(this._dio, this._serializers);

  /// Create or update a walking session start time
  /// Stores the start time for a walking session. The session identifier is supplied by the client and authentication is out of scope for this API contract. A session is the origin for one-minute step intervals; only the final partial interval is allowed by the client contract. The start time is immutable after the first accepted value. The server records the time at which the request is received. 
  ///
  /// Parameters:
  /// * [sessionId] - Non-zero canonical UUID identifying the walking session.
  /// * [sessionRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future]
  /// Throws [DioException] if API call or serialization fails
  Future<Response<void>> putSession({ 
    required String sessionId,
    required SessionRequest sessionRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/sessions/{session_id}'.replaceAll('{' r'session_id' '}', encodeQueryParameter(_serializers, sessionId, const FullType(String)).toString());
    final _options = Options(
      method: r'PUT',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[],
        ...?extra,
      },
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(SessionRequest);
      _bodyData = _serializers.serialize(sessionRequest, specifiedType: _type);

    } catch(error, stackTrace) {
      throw DioException(
         requestOptions: _options.compose(
          _dio.options,
          _path,
        ),
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final _response = await _dio.request<Object>(
      _path,
      data: _bodyData,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return _response;
  }

}
