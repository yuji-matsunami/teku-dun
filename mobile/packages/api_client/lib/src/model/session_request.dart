//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'session_request.g.dart';

/// SessionRequest
///
/// Properties:
/// * [startDatetime] - Immutable session start time in RFC 3339 format.
@BuiltValue()
abstract class SessionRequest implements Built<SessionRequest, SessionRequestBuilder> {
  /// Immutable session start time in RFC 3339 format.
  @BuiltValueField(wireName: r'start_datetime')
  DateTime get startDatetime;

  SessionRequest._();

  factory SessionRequest([void updates(SessionRequestBuilder b)]) = _$SessionRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SessionRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SessionRequest> get serializer => _$SessionRequestSerializer();
}

class _$SessionRequestSerializer implements PrimitiveSerializer<SessionRequest> {
  @override
  final Iterable<Type> types = const [SessionRequest, _$SessionRequest];

  @override
  final String wireName = r'SessionRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SessionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'start_datetime';
    yield serializers.serialize(
      object.startDatetime,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SessionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SessionRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'start_datetime':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startDatetime = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SessionRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SessionRequestBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

