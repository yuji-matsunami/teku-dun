// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'steps_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$StepsRequest extends StepsRequest {
  @override
  final DateTime startDatetime;
  @override
  final DateTime endDatetime;
  @override
  final int steps;
  @override
  final int revision;

  factory _$StepsRequest([void Function(StepsRequestBuilder)? updates]) =>
      (StepsRequestBuilder()..update(updates))._build();

  _$StepsRequest._(
      {required this.startDatetime,
      required this.endDatetime,
      required this.steps,
      required this.revision})
      : super._();
  @override
  StepsRequest rebuild(void Function(StepsRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  StepsRequestBuilder toBuilder() => StepsRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is StepsRequest &&
        startDatetime == other.startDatetime &&
        endDatetime == other.endDatetime &&
        steps == other.steps &&
        revision == other.revision;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, startDatetime.hashCode);
    _$hash = $jc(_$hash, endDatetime.hashCode);
    _$hash = $jc(_$hash, steps.hashCode);
    _$hash = $jc(_$hash, revision.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'StepsRequest')
          ..add('startDatetime', startDatetime)
          ..add('endDatetime', endDatetime)
          ..add('steps', steps)
          ..add('revision', revision))
        .toString();
  }
}

class StepsRequestBuilder
    implements Builder<StepsRequest, StepsRequestBuilder> {
  _$StepsRequest? _$v;

  DateTime? _startDatetime;
  DateTime? get startDatetime => _$this._startDatetime;
  set startDatetime(DateTime? startDatetime) =>
      _$this._startDatetime = startDatetime;

  DateTime? _endDatetime;
  DateTime? get endDatetime => _$this._endDatetime;
  set endDatetime(DateTime? endDatetime) => _$this._endDatetime = endDatetime;

  int? _steps;
  int? get steps => _$this._steps;
  set steps(int? steps) => _$this._steps = steps;

  int? _revision;
  int? get revision => _$this._revision;
  set revision(int? revision) => _$this._revision = revision;

  StepsRequestBuilder() {
    StepsRequest._defaults(this);
  }

  StepsRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _startDatetime = $v.startDatetime;
      _endDatetime = $v.endDatetime;
      _steps = $v.steps;
      _revision = $v.revision;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(StepsRequest other) {
    _$v = other as _$StepsRequest;
  }

  @override
  void update(void Function(StepsRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  StepsRequest build() => _build();

  _$StepsRequest _build() {
    final _$result = _$v ??
        _$StepsRequest._(
          startDatetime: BuiltValueNullFieldError.checkNotNull(
              startDatetime, r'StepsRequest', 'startDatetime'),
          endDatetime: BuiltValueNullFieldError.checkNotNull(
              endDatetime, r'StepsRequest', 'endDatetime'),
          steps: BuiltValueNullFieldError.checkNotNull(
              steps, r'StepsRequest', 'steps'),
          revision: BuiltValueNullFieldError.checkNotNull(
              revision, r'StepsRequest', 'revision'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
