//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ready_response.g.dart';

/// Successful readiness check response.
///
/// Properties:
/// * [status]
@BuiltValue()
abstract class ReadyResponse implements Built<ReadyResponse, ReadyResponseBuilder> {
  @BuiltValueField(wireName: r'status')
  ReadyResponseStatusEnum get status;
  // enum statusEnum {  ready,  };

  ReadyResponse._();

  factory ReadyResponse([void updates(ReadyResponseBuilder b)]) = _$ReadyResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReadyResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReadyResponse> get serializer => _$ReadyResponseSerializer();
}

class _$ReadyResponseSerializer implements PrimitiveSerializer<ReadyResponse> {
  @override
  final Iterable<Type> types = const [ReadyResponse, _$ReadyResponse];

  @override
  final String wireName = r'ReadyResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReadyResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(ReadyResponseStatusEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ReadyResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReadyResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadyResponseStatusEnum),
          ) as ReadyResponseStatusEnum;
          result.status = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReadyResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReadyResponseBuilder();
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

class ReadyResponseStatusEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'ready')
  static const ReadyResponseStatusEnum ready = _$readyResponseStatusEnum_ready;

  static Serializer<ReadyResponseStatusEnum> get serializer => _$readyResponseStatusEnumSerializer;

  const ReadyResponseStatusEnum._(String name): super(name);

  static BuiltSet<ReadyResponseStatusEnum> get values => _$readyResponseStatusEnumValues;
  static ReadyResponseStatusEnum valueOf(String name) => _$readyResponseStatusEnumValueOf(name);
}
