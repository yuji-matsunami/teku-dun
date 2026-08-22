import 'package:flutter_test/flutter_test.dart';

import 'package:android_sensing_spike/core/metrics/session_metrics.dart';
import 'package:android_sensing_spike/core/models/location_sample.dart';

LocationSample _sample({
  required int seq,
  required DateTime recordedAt,
  required double latitude,
  required double longitude,
  double? accuracy,
  bool? isMoving,
  String? activity,
}) {
  return LocationSample(
    seq: seq,
    providerId: 'test',
    recordedAt: recordedAt,
    receivedAt: recordedAt,
    latitude: latitude,
    longitude: longitude,
    accuracy: accuracy,
    isMoving: isMoving,
    activity: activity,
  );
}

void main() {
  final base = DateTime.utc(2026, 8, 22, 9);

  group('SessionMetrics.compute のエッジケース', () {
    test('空リストでも例外を投げず、すべて 0 / null で返す', () {
      final metrics = SessionMetrics.compute(
        const [],
        sessionStart: base,
        sessionEnd: base,
      );

      expect(metrics.sampleCount, 0);
      expect(metrics.wallClockDuration, Duration.zero);
      expect(metrics.medianInterval, Duration.zero);
      expect(metrics.p95Interval, Duration.zero);
      expect(metrics.maxInterval, Duration.zero);
      expect(metrics.gaps, isEmpty);
      expect(metrics.totalGapDuration, Duration.zero);
      expect(metrics.gapRatio, 0.0);
      expect(metrics.totalDistanceMeters, 0.0);
      expect(metrics.rejectedSegments, 0);
      expect(metrics.medianAccuracy, isNull);
      expect(metrics.p95Accuracy, isNull);
      expect(metrics.activityHistogram, isEmpty);
      expect(metrics.movingSampleCount, 0);
      // toReportString も例外を投げないこと。
      expect(metrics.toReportString(), isNotEmpty);
    });

    test('単一サンプルでも例外を投げない', () {
      final metrics = SessionMetrics.compute(
        [_sample(seq: 0, recordedAt: base, latitude: 35.0, longitude: 135.0)],
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 1)),
      );

      expect(metrics.sampleCount, 1);
      expect(metrics.medianInterval, Duration.zero);
      expect(metrics.maxInterval, Duration.zero);
      expect(metrics.totalDistanceMeters, 0.0);
      expect(metrics.gaps, isEmpty);
    });

    test('ゼロ秒セッションでも gapRatio が 0 割りにならない', () {
      final metrics = SessionMetrics.compute(
        [
          _sample(seq: 0, recordedAt: base, latitude: 0, longitude: 0),
          _sample(
            seq: 1,
            recordedAt: base.add(const Duration(minutes: 5)),
            latitude: 0,
            longitude: 0.001,
          ),
        ],
        sessionStart: base,
        sessionEnd: base, // wallClockDuration は 0 になる
      );

      expect(metrics.wallClockDuration, Duration.zero);
      expect(metrics.gapRatio, 0.0);
    });

    test('入力が recordedAt 順にソートされていなくても正しく処理する', () {
      final s0 = _sample(seq: 0, recordedAt: base, latitude: 0, longitude: 0);
      final s1 = _sample(
        seq: 1,
        recordedAt: base.add(const Duration(seconds: 10)),
        latitude: 0,
        longitude: 0,
      );
      final s2 = _sample(
        seq: 2,
        recordedAt: base.add(const Duration(seconds: 20)),
        latitude: 0,
        longitude: 0,
      );

      // わざと逆順・シャッフルした状態で渡す。
      final metrics = SessionMetrics.compute(
        [s2, s0, s1],
        sessionStart: base,
        sessionEnd: base.add(const Duration(seconds: 20)),
      );

      expect(metrics.sampleCount, 3);
      // 2 区間とも 10 秒間隔になるはず。
      expect(metrics.medianInterval, const Duration(seconds: 10));
      expect(metrics.maxInterval, const Duration(seconds: 10));
    });

    test('タイムスタンプが重複していても例外を投げず間隔 0 として扱う', () {
      final metrics = SessionMetrics.compute(
        [
          _sample(seq: 0, recordedAt: base, latitude: 0, longitude: 0),
          _sample(seq: 1, recordedAt: base, latitude: 0, longitude: 0.01),
        ],
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 1)),
      );

      expect(metrics.sampleCount, 2);
      expect(metrics.medianInterval, Duration.zero);
      expect(metrics.gaps, isEmpty);
    });
  });

  group('欠損 (gap) の検出', () {
    test('gapThreshold を超える間隔だけを欠損として記録する', () {
      final samples = [
        _sample(seq: 0, recordedAt: base, latitude: 0, longitude: 0),
        _sample(
          seq: 1,
          recordedAt: base.add(const Duration(seconds: 30)),
          latitude: 0,
          longitude: 0,
        ),
        // 30 秒 -> 200 秒経過 (170 秒のギャップ、閾値 60 秒を超える)
        _sample(
          seq: 2,
          recordedAt: base.add(const Duration(seconds: 200)),
          latitude: 0,
          longitude: 0,
        ),
      ];

      final metrics = SessionMetrics.compute(
        samples,
        sessionStart: base,
        sessionEnd: base.add(const Duration(seconds: 200)),
        gapThreshold: const Duration(seconds: 60),
      );

      expect(metrics.gaps, hasLength(1));
      expect(metrics.gaps.single.duration, const Duration(seconds: 170));
      expect(metrics.totalGapDuration, const Duration(seconds: 170));
      expect(metrics.gapRatio, closeTo(170 / 200, 1e-9));
    });
  });

  group('パーセンタイル (最近接順位法)', () {
    test('取得間隔の中央値・p95 が最近接順位法で計算される', () {
      // 間隔: 10, 20, 30, 40, 50 (秒) の 5 つ -> 6 サンプル
      final intervalsSec = [10, 20, 30, 40, 50];
      var t = base;
      final samples = <LocationSample>[
        _sample(seq: 0, recordedAt: t, latitude: 0, longitude: 0),
      ];
      for (var i = 0; i < intervalsSec.length; i++) {
        t = t.add(Duration(seconds: intervalsSec[i]));
        samples.add(_sample(seq: i + 1, recordedAt: t, latitude: 0, longitude: 0));
      }

      final metrics = SessionMetrics.compute(
        samples,
        sessionStart: base,
        sessionEnd: t,
      );

      // ソート済み: [10, 20, 30, 40, 50], N=5
      // median (p50): rank = ceil(0.5*5)=3 -> index 2 -> 30
      expect(metrics.medianInterval, const Duration(seconds: 30));
      // p95: rank = ceil(0.95*5)=5 -> index 4 -> 50
      expect(metrics.p95Interval, const Duration(seconds: 50));
      expect(metrics.maxInterval, const Duration(seconds: 50));
    });
  });

  group('距離計算 (Haversine)', () {
    test('赤道上で緯度 1 度分の距離が約 111.19km になる (誤差 1% 以内)', () {
      final samples = [
        _sample(seq: 0, recordedAt: base, latitude: 0.0, longitude: 0.0),
        _sample(
          seq: 1,
          recordedAt: base.add(const Duration(seconds: 1)),
          latitude: 1.0,
          longitude: 0.0,
        ),
      ];

      final metrics = SessionMetrics.compute(
        samples,
        sessionStart: base,
        sessionEnd: base.add(const Duration(seconds: 1)),
      );

      const expectedMeters = 111190.0;
      final diffRatio =
          (metrics.totalDistanceMeters - expectedMeters).abs() / expectedMeters;
      expect(diffRatio, lessThan(0.01));
    });

    test('accuracy が閾値を超えるサンプルが絡む区間は距離計算から除外する', () {
      final samples = [
        _sample(seq: 0, recordedAt: base, latitude: 0.0, longitude: 0.0, accuracy: 10),
        // このサンプルは精度が悪い (accuracy=100 > 50) ので、
        // 前後の区間は距離計算から除外されるはず。
        _sample(
          seq: 1,
          recordedAt: base.add(const Duration(seconds: 1)),
          latitude: 1.0,
          longitude: 0.0,
          accuracy: 100,
        ),
        _sample(
          seq: 2,
          recordedAt: base.add(const Duration(seconds: 2)),
          latitude: 2.0,
          longitude: 0.0,
          accuracy: 5,
        ),
      ];

      final metrics = SessionMetrics.compute(
        samples,
        sessionStart: base,
        sessionEnd: base.add(const Duration(seconds: 2)),
        accuracyRejectMeters: 50,
      );

      // 2 区間とも accuracy=100 のサンプルに接しているため両方除外される。
      expect(metrics.rejectedSegments, 2);
      expect(metrics.totalDistanceMeters, 0.0);
    });
  });

  group('バッテリー・アクティビティ集計', () {
    test('バッテリー消費量と時間当たり消費率を計算する', () {
      final metrics = SessionMetrics.compute(
        const [],
        sessionStart: base,
        sessionEnd: base.add(const Duration(hours: 2)),
        batteryAtStart: 100,
        batteryAtEnd: 80,
      );

      expect(metrics.batteryDropPercent, 20);
      expect(metrics.batteryDropPerHour, closeTo(10.0, 1e-9));
    });

    test('バッテリー情報が片方だけの場合は null になる', () {
      final metrics = SessionMetrics.compute(
        const [],
        sessionStart: base,
        sessionEnd: base.add(const Duration(hours: 1)),
        batteryAtStart: 100,
      );

      expect(metrics.batteryDropPercent, isNull);
      expect(metrics.batteryDropPerHour, isNull);
    });

    test('activity のヒストグラムと移動中サンプル数を集計する', () {
      final samples = [
        _sample(
          seq: 0,
          recordedAt: base,
          latitude: 0,
          longitude: 0,
          activity: 'still',
          isMoving: false,
        ),
        _sample(
          seq: 1,
          recordedAt: base.add(const Duration(seconds: 1)),
          latitude: 0,
          longitude: 0,
          activity: 'on_foot',
          isMoving: true,
        ),
        _sample(
          seq: 2,
          recordedAt: base.add(const Duration(seconds: 2)),
          latitude: 0,
          longitude: 0,
          activity: 'on_foot',
          isMoving: true,
        ),
        _sample(
          seq: 3,
          recordedAt: base.add(const Duration(seconds: 3)),
          latitude: 0,
          longitude: 0,
        ),
      ];

      final metrics = SessionMetrics.compute(
        samples,
        sessionStart: base,
        sessionEnd: base.add(const Duration(seconds: 3)),
      );

      expect(metrics.activityHistogram, {'still': 1, 'on_foot': 2});
      expect(metrics.movingSampleCount, 2);
    });
  });
}
