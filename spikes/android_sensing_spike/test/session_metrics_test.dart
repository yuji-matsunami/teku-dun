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

  // 頭尾の欠損検出。本スパイクが検出すべき失敗そのものを扱う。
  group('頭尾の欠損検出', () {
    // 15分のセッション中、最初の3分しかサンプルが無い =
    // 途中で計測が死んで戻らなかったケース。
    List<LocationSample> firstThreeMinutesOnly() {
      return List<LocationSample>.generate(19, (i) {
        return _sample(
          seq: i + 1,
          recordedAt: base.add(Duration(seconds: 10 * i)),
          latitude: 35.0 + i * 0.0001,
          longitude: 139.0,
          accuracy: 8,
        );
      });
    }

    test('途中で計測が止まると末尾欠損として検出される', () {
      final metrics = SessionMetrics.compute(
        firstThreeMinutesOnly(),
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 15)),
      );

      final tail = metrics.gaps.where((g) => g.position == GapPosition.tail);
      expect(tail, hasLength(1));
      // 3分ちょうどまでサンプルがあるので、残り12分が欠損。
      expect(tail.first.duration, const Duration(minutes: 12));
      expect(metrics.gapRatio, greaterThan(0.7));
    });

    test('末尾欠損は取得間隔の統計を汚染しない', () {
      final metrics = SessionMetrics.compute(
        firstThreeMinutesOnly(),
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 15)),
      );

      // サンプル間はすべて10秒間隔。末尾の12分が混ざってはならない。
      expect(metrics.medianInterval, const Duration(seconds: 10));
      expect(metrics.p95Interval, const Duration(seconds: 10));
      expect(metrics.maxInterval, const Duration(seconds: 10));
    });

    test('開始直後に取得できない区間は先頭欠損として検出される', () {
      final samples = List<LocationSample>.generate(6, (i) {
        return _sample(
          seq: i + 1,
          recordedAt: base.add(Duration(minutes: 4, seconds: 10 * i)),
          latitude: 35.0 + i * 0.0001,
          longitude: 139.0,
          accuracy: 8,
        );
      });

      final metrics = SessionMetrics.compute(
        samples,
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 5)),
      );

      final head = metrics.gaps.where((g) => g.position == GapPosition.head);
      expect(head, hasLength(1));
      expect(head.first.duration, const Duration(minutes: 4));
      expect(head.first.positionLabel, '開始直後');
    });

    test('サンプルが1件も無い場合はセッション全体が欠損になる', () {
      final metrics = SessionMetrics.compute(
        const [],
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 15)),
      );

      expect(metrics.gaps, hasLength(1));
      expect(metrics.gaps.first.position, GapPosition.whole);
      expect(metrics.gaps.first.duration, const Duration(minutes: 15));
      expect(metrics.gapRatio, closeTo(1.0, 0.001));
      expect(metrics.toReportString(), contains('セッション全体'));
    });

    test('末尾欠損があるとレポートに警告が出る', () {
      final metrics = SessionMetrics.compute(
        firstThreeMinutesOnly(),
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 15)),
      );

      expect(metrics.toReportString(), contains('計測が途中で止まった可能性'));
    });

    test('サンプルがセッション区間外にあっても負の欠損を出さない', () {
      final samples = [
        _sample(
          seq: 1,
          recordedAt: base.subtract(const Duration(minutes: 1)),
          latitude: 35.0,
          longitude: 139.0,
        ),
        _sample(
          seq: 2,
          recordedAt: base.add(const Duration(minutes: 16)),
          latitude: 35.001,
          longitude: 139.0,
        ),
      ];

      final metrics = SessionMetrics.compute(
        samples,
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 15)),
      );

      for (final gap in metrics.gaps) {
        expect(gap.duration.isNegative, isFalse);
      }
      expect(metrics.totalGapDuration.isNegative, isFalse);
    });
  });

  // 静止中の欠損と、動いているのに取れていない欠損の区別。
  // ここを誤ると、正しく省電力しているライブラリほど悪く見え、
  // ライブラリ採否の結論が逆転する。
  group('欠損の原因分類', () {
    // 20分のセッション。5分〜13分の8分間、サンプルが来ない。
    //
    // [movedMetersDuringGap] は欠損中に進んだ距離。
    // 変位ベースの判定を効かせるため、静止時と歩行時を作り分ける。
    List<LocationSample> withMiddleGap({double movedMetersDuringGap = 10}) {
      final times = <int>[
        for (var i = 0; i < 30; i++) i * 10, // 0〜290秒
        for (var i = 0; i < 42; i++) 780 + i * 10, // 780〜1190秒
      ];
      // 緯度 1 度 ≒ 111.19km。
      final jump = movedMetersDuringGap / 111190.0;
      return [
        for (var i = 0; i < times.length; i++)
          _sample(
            seq: i + 1,
            recordedAt: base.add(Duration(seconds: times[i])),
            latitude: 35.0 + i * 0.0000001 + (i >= 30 ? jump : 0),
            longitude: 139.0,
            accuracy: 8,
          ),
      ];
    }

    test('静止イベントに覆われた欠損は stationary に分類される', () {
      final metrics = SessionMetrics.compute(
        withMiddleGap(),
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 20)),
        motionChanges: [
          MotionChangeRecord(
            at: base.add(const Duration(seconds: 285)),
            isMoving: false,
          ),
          MotionChangeRecord(
            at: base.add(const Duration(seconds: 785)),
            isMoving: true,
          ),
        ],
      );

      final interior = metrics.gaps
          .where((g) => g.position == GapPosition.interior)
          .toList();
      expect(interior, hasLength(1));
      expect(interior.first.cause, GapCause.stationary);
      expect(metrics.unexplainedGapDuration, Duration.zero);
      expect(metrics.stationaryGapDuration, greaterThan(Duration.zero));
    });

    test('欠損中に歩いていれば unexplained になる', () {
      final metrics = SessionMetrics.compute(
        // 490秒で 600m ≒ 4.4km/h。歩いている。
        withMiddleGap(movedMetersDuringGap: 600),
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 20)),
      );

      final interior = metrics.gaps
          .where((g) => g.position == GapPosition.interior)
          .toList();
      expect(interior, hasLength(1));
      expect(interior.first.cause, GapCause.unexplained);
      expect(metrics.unexplainedGapDuration, greaterThan(Duration.zero));
      expect(metrics.stationaryGapDuration, Duration.zero);
    });

    test('動いているのに取れていない欠損は静止イベントがあっても unexplained', () {
      final metrics = SessionMetrics.compute(
        withMiddleGap(movedMetersDuringGap: 600),
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 20)),
        motionChanges: [
          MotionChangeRecord(
            at: base.add(const Duration(seconds: 100)),
            isMoving: false,
          ),
          MotionChangeRecord(
            at: base.add(const Duration(seconds: 110)),
            isMoving: true,
          ),
        ],
      );

      final interior = metrics.gaps
          .where((g) => g.position == GapPosition.interior)
          .toList();
      expect(interior.first.cause, GapCause.unexplained);
    });

    test('原因不明の欠損率は分母から静止時間を除く', () {
      // 20分のうち8分静止。原因不明の欠損は無い。
      final metrics = SessionMetrics.compute(
        withMiddleGap(),
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 20)),
        motionChanges: [
          MotionChangeRecord(
            at: base.add(const Duration(seconds: 285)),
            isMoving: false,
          ),
          MotionChangeRecord(
            at: base.add(const Duration(seconds: 785)),
            isMoving: true,
          ),
        ],
      );

      expect(metrics.unexplainedGapRatio, 0.0);
      // 従来の欠損率は静止分を含むので 0 より大きいままである。
      expect(metrics.gapRatio, greaterThan(0.0));
      expect(metrics.stationaryDuration, const Duration(seconds: 500));
    });

    test('静止したまま終わった場合はセッション終了までを静止とみなす', () {
      final intervals = SessionMetrics.buildStationaryIntervals(
        [
          MotionChangeRecord(
            at: base.add(const Duration(minutes: 5)),
            isMoving: false,
          ),
        ],
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 20)),
      );

      expect(intervals, hasLength(1));
      expect(intervals.first.to, base.add(const Duration(minutes: 20)));
    });

    test('同じ状態が連続する重複イベントを無視する', () {
      final intervals = SessionMetrics.buildStationaryIntervals(
        [
          MotionChangeRecord(at: base, isMoving: false),
          MotionChangeRecord(at: base, isMoving: false),
          MotionChangeRecord(
            at: base.add(const Duration(minutes: 3)),
            isMoving: true,
          ),
          MotionChangeRecord(
            at: base.add(const Duration(minutes: 4)),
            isMoving: true,
          ),
        ],
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 20)),
      );

      expect(intervals, hasLength(1));
      expect(intervals.first.from, base);
      expect(intervals.first.to, base.add(const Duration(minutes: 3)));
    });

    test('motionChange が空でも例外を投げず従来どおり動く', () {
      final metrics = SessionMetrics.compute(
        withMiddleGap(),
        sessionStart: base,
        sessionEnd: base.add(const Duration(minutes: 20)),
        motionChanges: const [],
      );
      expect(metrics.stationaryDuration, Duration.zero);
      expect(metrics.toReportString(), contains('原因不明の欠損'));
    });
  });

  test('静止分と原因不明分の合計は必ず総欠損時間に一致する', () {
    // 変位が測れる欠損では、変位だけで判定する。
    // 1.1km を 10 分 = 6.7km/h なので歩行とみなし、全体が原因不明になる。
    final samples = [
      _sample(seq: 1, recordedAt: base, latitude: 35.0, longitude: 139.0),
      _sample(
        seq: 2,
        recordedAt: base.add(const Duration(minutes: 10)),
        latitude: 35.01,
        longitude: 139.0,
      ),
    ];

    final metrics = SessionMetrics.compute(
      samples,
      sessionStart: base,
      sessionEnd: base.add(const Duration(minutes: 10)),
      motionChanges: [
        MotionChangeRecord(
          at: base.add(const Duration(minutes: 2)),
          isMoving: false,
        ),
        MotionChangeRecord(
          at: base.add(const Duration(minutes: 5)),
          isMoving: true,
        ),
      ],
    );

    expect(
      metrics.stationaryGapDuration + metrics.unexplainedGapDuration,
      metrics.totalGapDuration,
    );
    expect(metrics.unexplainedGapRatio, lessThanOrEqualTo(1.0));
    // 静止イベントが重なっていても、実際に歩いていたので免罪しない。
    expect(metrics.stationaryGapDuration, Duration.zero);
    expect(metrics.unexplainedGapDuration, const Duration(minutes: 10));
  });

  test('変位を測れない末尾欠損では motionChange を根拠に使う', () {
    // 末尾欠損には終端のサンプルが無いため変位を測れない。
    // この場合に限り、静止イベントの重なりで按分する。
    final samples = [
      _sample(seq: 1, recordedAt: base, latitude: 35.0, longitude: 139.0),
      _sample(
        seq: 2,
        recordedAt: base.add(const Duration(seconds: 30)),
        latitude: 35.0001,
        longitude: 139.0,
      ),
    ];

    final metrics = SessionMetrics.compute(
      samples,
      sessionStart: base,
      sessionEnd: base.add(const Duration(minutes: 10)),
      motionChanges: [
        MotionChangeRecord(
          at: base.add(const Duration(minutes: 4)),
          isMoving: false,
        ),
        MotionChangeRecord(
          at: base.add(const Duration(minutes: 7)),
          isMoving: true,
        ),
      ],
    );

    final tail = metrics.gaps
        .where((g) => g.position == GapPosition.tail)
        .toList();
    expect(tail, hasLength(1));
    expect(tail.first.impliedSpeedKmh, isNull);
    expect(metrics.stationaryGapDuration, const Duration(minutes: 3));
    expect(
      metrics.stationaryGapDuration + metrics.unexplainedGapDuration,
      metrics.totalGapDuration,
    );
  });
}
