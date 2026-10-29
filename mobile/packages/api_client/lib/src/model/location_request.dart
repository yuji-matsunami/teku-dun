//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'location_request.g.dart';

/// LocationRequest
///
/// Properties:
/// * [recordedAt] - Device-recorded time in RFC 3339 format; requests more than five minutes in the future are invalid.
/// * [latitude] - Latitude in decimal degrees.
/// * [longitude] - Longitude in decimal degrees.
/// * [accuracyM] - Horizontal accuracy in metres.
@BuiltValue()
abstract class LocationRequest implements Built<LocationRequest, LocationRequestBuilder> {
  /// Device-recorded time in RFC 3339 format; requests more than five minutes in the future are invalid.
  @BuiltValueField(wireName: r'recorded_at')
  DateTime get recordedAt;

  /// Latitude in decimal degrees.
  @BuiltValueField(wireName: r'latitude')
  double get latitude;

  /// Longitude in decimal degrees.
  @BuiltValueField(wireName: r'longitude')
  double get longitude;

  /// Horizontal accuracy in metres.
  @BuiltValueField(wireName: r'accuracy_m')
  double get accuracyM;

  LocationRequest._();

  factory LocationRequest([void updates(LocationRequestBuilder b)]) = _$LocationRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LocationRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LocationRequest> get serializer => _$LocationRequestSerializer();
}

class _$LocationRequestSerializer implements PrimitiveSerializer<LocationRequest> {
  @override
  final Iterable<Type> types = const [LocationRequest, _$LocationRequest];

  @override
  final String wireName = r'LocationRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LocationRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'recorded_at';
    yield serializers.serialize(
      object.recordedAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'latitude';
    yield serializers.serialize(
      object.latitude,
      specifiedType: const FullType(double),
    );
    yield r'longitude';
    yield serializers.serialize(
      object.longitude,
      specifiedType: const FullType(double),
    );
    yield r'accuracy_m';
    yield serializers.serialize(
      object.accuracyM,
      specifiedType: const FullType(double),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LocationRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LocationRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'recorded_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.recordedAt = valueDes;
          break;
        case r'latitude':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.latitude = valueDes;
          break;
        case r'longitude':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.longitude = valueDes;
          break;
        case r'accuracy_m':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.accuracyM = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LocationRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LocationRequestBuilder();
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

