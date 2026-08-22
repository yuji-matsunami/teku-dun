import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart' show immutable;

import '../core/models/tracking_event.dart';

/// バッテリー残量・充電状態を計測するためのラッパー。
///
/// 2 つの位置情報ライブラリ (flutter_background_geolocation / tracelet) の
/// バッテリー消費を比較するには、セッション開始/終了の 2 点だけでなく、
/// 散歩の途中経過 (10〜15 分間隔) でも残量を記録し、消費の推移を
/// グラフ化できるようにする必要がある。そのための定期サンプラーを提供する。
class BatterySampler {
  BatterySampler({Battery? battery}) : _battery = battery ?? Battery();

  final Battery _battery;

  /// 現在のバッテリー残量・充電状態を 1 回だけ読み取る。
  /// 例外は決して外に投げず、失敗時は各フィールドを null にして返す。
  Future<BatteryReading> read() async {
    final now = DateTime.now().toUtc();
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      return BatteryReading(
        levelPercent: level,
        isCharging: _isChargingFromState(state),
        at: now,
      );
    } catch (_) {
      return BatteryReading(levelPercent: null, isCharging: null, at: now);
    }
  }

  /// `BatteryState` を「充電中とみなせるか」の真偽値に単純化する。
  ///
  /// full (満充電) と connectedNotCharging (給電中だが充電はしていない、
  /// 上限設定などで発生) は「外部電源に接続されている」という意味で
  /// isCharging = true にまとめ、discharging のみ false とする。
  /// unknown は判定不能として null を返す。
  bool? _isChargingFromState(BatteryState state) {
    switch (state) {
      case BatteryState.charging:
      case BatteryState.full:
      case BatteryState.connectedNotCharging:
        return true;
      case BatteryState.discharging:
        return false;
      case BatteryState.unknown:
        return null;
    }
  }

  /// [interval] ごとにバッテリー状態を読み取り、
  /// [TrackingEventKind.batterySnapshot] イベントとして流し続ける Stream を返す。
  ///
  /// 返された Stream の購読 (`StreamSubscription`) を `cancel()` すると
  /// 内部の `Timer` も確実に破棄されるため、Timer のリークは発生しない。
  Stream<TrackingEvent> periodic({Duration interval = const Duration(minutes: 1)}) {
    late final StreamController<TrackingEvent> controller;
    Timer? timer;

    Future<void> emitOnce() async {
      final reading = await read();
      if (!controller.isClosed) {
        controller.add(
          TrackingEvent(
            at: reading.at,
            kind: TrackingEventKind.batterySnapshot,
            data: reading.toJson(),
          ),
        );
      }
    }

    controller = StreamController<TrackingEvent>(
      onListen: () {
        // 購読開始直後にも 1 回計測しておく (最初のサンプルまで interval 待たされないように)。
        unawaited(emitOnce());
        timer = Timer.periodic(interval, (_) {
          unawaited(emitOnce());
        });
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );

    return controller.stream;
  }
}

/// バッテリー残量のスナップショット。
@immutable
class BatteryReading {
  const BatteryReading({
    required this.levelPercent,
    required this.isCharging,
    required this.at,
  });

  /// バッテリー残量 (0-100)。取得できなかった場合は null。
  final int? levelPercent;

  /// 充電中とみなせるかどうか。取得できなかった場合は null。
  final bool? isCharging;

  /// この計測を行った時刻 (UTC)。
  final DateTime at;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'at': at.toIso8601String()};
    if (levelPercent != null) {
      map['levelPercent'] = levelPercent;
    }
    if (isCharging != null) {
      map['isCharging'] = isCharging;
    }
    return map;
  }
}
