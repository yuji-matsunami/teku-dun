//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'steps_request.g.dart';

/// StepsRequest
///
/// Properties:
/// * [startDatetime] - Immutable interval start in RFC 3339 format, aligned to a one-minute interval from the session origin.
/// * [endDatetime] - Immutable interval end in RFC 3339 format.
/// * [steps] - Non-negative step count.
/// * [revision] - Client revision used for idempotent correction.
@BuiltValue()
abstract class StepsRequest implements Built<StepsRequest, StepsRequestBuilder> {
  /// Immutable interval start in RFC 3339 format, aligned to a one-minute interval from the session origin.
  @BuiltValueField(wireName: r'start_datetime')
  DateTime get startDatetime;

  /// Immutable interval end in RFC 3339 format.
  @BuiltValueField(wireName: r'end_datetime')
  DateTime get endDatetime;

  /// Non-negative step count.
  @BuiltValueField(wireName: r'steps')
  int get steps;

  /// Client revision used for idempotent correction.
  @BuiltValueField(wireName: r'revision')
  int get revision;

  StepsRequest._();

  factory StepsRequest([void updates(StepsRequestBuilder b)]) = _$StepsRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(StepsRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<StepsRequest> get serializer => _$StepsRequestSerializer();
}

class _$StepsRequestSerializer implements PrimitiveSerializer<StepsRequest> {
  @override
  final Iterable<Type> types = const [StepsRequest, _$StepsRequest];

  @override
  final String wireName = r'StepsRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    StepsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'start_datetime';
    yield serializers.serialize(
      object.startDatetime,
      specifiedType: const FullType(DateTime),
    );
    yield r'end_datetime';
    yield serializers.serialize(
      object.endDatetime,
      specifiedType: const FullType(DateTime),
    );
    yield r'steps';
    yield serializers.serialize(
      object.steps,
      specifiedType: const FullType(int),
    );
    yield r'revision';
    yield serializers.serialize(
      object.revision,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    StepsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required StepsRequestBuilder result,
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
        case r'end_datetime':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.endDatetime = valueDes;
          break;
        case r'steps':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.steps = valueDes;
          break;
        case r'revision':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.revision = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  StepsRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = StepsRequestBuilder();
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

