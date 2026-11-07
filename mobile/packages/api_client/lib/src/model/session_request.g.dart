// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SessionRequest extends SessionRequest {
  @override
  final DateTime startDatetime;

  factory _$SessionRequest([void Function(SessionRequestBuilder)? updates]) =>
      (SessionRequestBuilder()..update(updates))._build();

  _$SessionRequest._({required this.startDatetime}) : super._();
  @override
  SessionRequest rebuild(void Function(SessionRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SessionRequestBuilder toBuilder() => SessionRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SessionRequest && startDatetime == other.startDatetime;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, startDatetime.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SessionRequest')
          ..add('startDatetime', startDatetime))
        .toString();
  }
}

class SessionRequestBuilder
    implements Builder<SessionRequest, SessionRequestBuilder> {
  _$SessionRequest? _$v;

  DateTime? _startDatetime;
  DateTime? get startDatetime => _$this._startDatetime;
  set startDatetime(DateTime? startDatetime) =>
      _$this._startDatetime = startDatetime;

  SessionRequestBuilder() {
    SessionRequest._defaults(this);
  }

  SessionRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _startDatetime = $v.startDatetime;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SessionRequest other) {
    _$v = other as _$SessionRequest;
  }

  @override
  void update(void Function(SessionRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SessionRequest build() => _build();

  _$SessionRequest _build() {
    final _$result = _$v ??
        _$SessionRequest._(
          startDatetime: BuiltValueNullFieldError.checkNotNull(
              startDatetime, r'SessionRequest', 'startDatetime'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
