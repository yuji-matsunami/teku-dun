// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LocationRequest extends LocationRequest {
  @override
  final DateTime recordedAt;
  @override
  final double latitude;
  @override
  final double longitude;
  @override
  final double accuracyM;

  factory _$LocationRequest([void Function(LocationRequestBuilder)? updates]) =>
      (LocationRequestBuilder()..update(updates))._build();

  _$LocationRequest._(
      {required this.recordedAt,
      required this.latitude,
      required this.longitude,
      required this.accuracyM})
      : super._();
  @override
  LocationRequest rebuild(void Function(LocationRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LocationRequestBuilder toBuilder() => LocationRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LocationRequest &&
        recordedAt == other.recordedAt &&
        latitude == other.latitude &&
        longitude == other.longitude &&
        accuracyM == other.accuracyM;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, recordedAt.hashCode);
    _$hash = $jc(_$hash, latitude.hashCode);
    _$hash = $jc(_$hash, longitude.hashCode);
    _$hash = $jc(_$hash, accuracyM.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LocationRequest')
          ..add('recordedAt', recordedAt)
          ..add('latitude', latitude)
          ..add('longitude', longitude)
          ..add('accuracyM', accuracyM))
        .toString();
  }
}

class LocationRequestBuilder
    implements Builder<LocationRequest, LocationRequestBuilder> {
  _$LocationRequest? _$v;

  DateTime? _recordedAt;
  DateTime? get recordedAt => _$this._recordedAt;
  set recordedAt(DateTime? recordedAt) => _$this._recordedAt = recordedAt;

  double? _latitude;
  double? get latitude => _$this._latitude;
  set latitude(double? latitude) => _$this._latitude = latitude;

  double? _longitude;
  double? get longitude => _$this._longitude;
  set longitude(double? longitude) => _$this._longitude = longitude;

  double? _accuracyM;
  double? get accuracyM => _$this._accuracyM;
  set accuracyM(double? accuracyM) => _$this._accuracyM = accuracyM;

  LocationRequestBuilder() {
    LocationRequest._defaults(this);
  }

  LocationRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _recordedAt = $v.recordedAt;
      _latitude = $v.latitude;
      _longitude = $v.longitude;
      _accuracyM = $v.accuracyM;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LocationRequest other) {
    _$v = other as _$LocationRequest;
  }

  @override
  void update(void Function(LocationRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LocationRequest build() => _build();

  _$LocationRequest _build() {
    final _$result = _$v ??
        _$LocationRequest._(
          recordedAt: BuiltValueNullFieldError.checkNotNull(
              recordedAt, r'LocationRequest', 'recordedAt'),
          latitude: BuiltValueNullFieldError.checkNotNull(
              latitude, r'LocationRequest', 'latitude'),
          longitude: BuiltValueNullFieldError.checkNotNull(
              longitude, r'LocationRequest', 'longitude'),
          accuracyM: BuiltValueNullFieldError.checkNotNull(
              accuracyM, r'LocationRequest', 'accuracyM'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
