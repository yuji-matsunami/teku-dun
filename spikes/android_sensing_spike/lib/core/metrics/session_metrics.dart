import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

import '../models/location_sample.dart';

/// 欠損区間がセッションのどこで起きたか。
///
/// この区別を失うと、意味の全く違う 2 つの現象が同じ数字に見えてしまう。
/// 「最初の 4 分間 fix が来ない」(GPS のコールドスタート、想定内) と
/// 「最後の 11 分間 fix が来ない」(計測が死んだ) は、
/// 本スパイクにとって正反対の結論を導く。
enum GapPosition {
  /// セッション開始から最初のサンプルまで。
  /// GPS の初期補足や権限ダイアログの待ち時間で、ある程度は必ず生じる。
  head,

  /// サンプルとサンプルの間。
  interior,

  /// 最後のサンプルからセッション終了まで。
  /// ここが長い場合、計測が途中で死んだことを強く示唆する。
  tail,

  /// サンプルが 1 件も無く、セッション全体が欠損しているケース。
  whole,
}

/// 欠損の原因の分類。
///
/// __この区別が比較の成否を分ける。__
/// 両ライブラリとも、静止を検知すると GPS を止めて電池を節約する。
/// そのため「静止中に位置が来ない」のは正常な動作であって、失敗ではない。
///
/// 一方、動いているのに位置が来ない区間は、ライブラリまたは OS の
/// 省電力制御によって計測が実際に止まっていたことを意味する。
/// 両者を一緒に数えると、正しく省電力していたライブラリほど
/// 欠損率が高く見えてしまい、評価が逆転する。
enum GapCause {
  /// 静止区間に収まっている欠損。省電力が働いた結果であり、失敗ではない。
  stationary,

  /// 静止していないのに位置が取れていない欠損。
  /// __これが本当に問題視すべき欠損。__
  unexplained,
}

/// `motionChange` イベント 1 件分。
///
/// 静止区間を組み立てるために使う。ログ (JSONL) の
/// `kind == "motionChange"` イベントから作る。
@immutable
class MotionChangeRecord {
  const MotionChangeRecord({required this.at, required this.isMoving});

  /// イベント発生時刻 (UTC)。
  final DateTime at;

  /// このイベント以降、移動中か静止中か。
  final bool isMoving;
}

/// 静止していた区間。
@immutable
class StationaryInterval {
  const StationaryInterval({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  /// [from]〜[to] と、指定区間との重なりの長さ。
  Duration overlapWith(DateTime start, DateTime end) {
    final s = start.isAfter(from) ? start : from;
    final e = end.isBefore(to) ? end : to;
    final d = e.difference(s);
    return d.isNegative ? Duration.zero : d;
  }
}

/// 検出された「欠損 (位置情報が取れていない区間)」。
@immutable
class Gap {
  const Gap({
    required this.from,
    required this.to,
    required this.duration,
    required this.position,
    this.cause = GapCause.unexplained,
    this.displacementMeters,
    this.impliedSpeedKmh,
  });

  /// 欠損の両端のサンプル間の直線距離 (メートル)。
  /// 端点が無い欠損 (開始直後・終了直前・セッション全体) では `null`。
  final double? displacementMeters;

  /// [displacementMeters] を欠損時間で割った平均速度 (km/h)。
  ///
  /// __静止判定の主たる根拠。__ 「その間に実際どれだけ動いたか」を
  /// 直接測っているため、ライブラリ自身の静止検知より信頼できる。
  /// 実機では fbg が、実際に止まってから 15 分後にようやく
  /// motionChange を発火した例が観測されている。
  final double? impliedSpeedKmh;

  /// 欠損の原因の分類。
  /// 静止区間の情報が渡されなかった場合は、すべて [GapCause.unexplained] になる。
  final GapCause cause;

  /// 表示用の原因ラベル。
  String get causeLabel {
    switch (cause) {
      case GapCause.stationary:
        return '静止中';
      case GapCause.unexplained:
        return '原因不明';
    }
  }

  /// 欠損区間の開始。
  final DateTime from;

  /// 欠損区間の終了。
  final DateTime to;

  /// 欠損区間の長さ。
  final Duration duration;

  /// 欠損がセッションのどこで起きたか。
  final GapPosition position;

  /// 表示用のラベル。
  String get positionLabel {
    switch (position) {
      case GapPosition.head:
        return '開始直後';
      case GapPosition.interior:
        return '計測中';
      case GapPosition.tail:
        return '終了直前';
      case GapPosition.whole:
        return 'セッション全体';
    }
  }
}

/// 1 セッション分の [LocationSample] 群から算出した比較用メトリクス。
///
/// flutter_background_geolocation と tracelet のような、異なるプロバイダの
/// 挙動を同じ土台で比較するために使う。パーセンタイルは全て
/// **最近接順位法 (nearest-rank method)** で計算する
/// (要素数 N, 百分位 p に対して rank = ceil(p / 100 * N) を [1, N] にクランプし、
/// ソート済み配列の (rank - 1) 番目の要素を採用する)。
@immutable
class SessionMetrics {
  const SessionMetrics({
    required this.sampleCount,
    required this.wallClockDuration,
    required this.medianInterval,
    required this.p95Interval,
    required this.maxInterval,
    required this.gaps,
    required this.totalGapDuration,
    required this.gapRatio,
    required this.totalDistanceMeters,
    required this.rejectedSegments,
    required this.medianAccuracy,
    required this.p95Accuracy,
    required this.batteryDropPercent,
    required this.batteryDropPerHour,
    required this.activityHistogram,
    required this.movingSampleCount,
    required this.unexplainedGapDuration,
    required this.unexplainedGapRatio,
    required this.stationaryGapDuration,
    required this.stationaryDuration,
  });

  /// サンプル件数。
  final int sampleCount;

  /// セッション開始から終了までの経過時間 (終了 < 開始の場合は Duration.zero)。
  final Duration wallClockDuration;

  /// 連続サンプル間の取得間隔 (recordedAt の差分) の中央値。
  final Duration medianInterval;

  /// 取得間隔の 95 パーセンタイル値。
  final Duration p95Interval;

  /// 取得間隔の最大値。
  final Duration maxInterval;

  /// [gapThreshold] を超えた取得間隔の一覧。
  final List<Gap> gaps;

  /// [gaps] の合計時間。
  final Duration totalGapDuration;

  /// [totalGapDuration] / [wallClockDuration]。
  /// [wallClockDuration] が 0 の場合は 0.0 とする。
  ///
  /// __この値だけで良し悪しを判断してはいけない。__ 静止中の省電力による
  /// 正常な欠損も含まれるため、正しく省電力しているライブラリほど
  /// 悪く見える。比較には [unexplainedGapRatio] を使うこと。
  final double gapRatio;

  /// 静止していないのに位置が取れていなかった時間の合計。
  /// __ライブラリの比較で見るべきはこちら。__
  final Duration unexplainedGapDuration;

  /// [unexplainedGapDuration] を「移動していた時間」で割った比率。
  ///
  /// 分母から静止時間を除いてあるため、
  /// 「動いている間にどれだけ取り逃したか」を表す。
  /// 移動時間が 0 の場合は 0.0 とする。
  final double unexplainedGapRatio;

  /// 静止区間に収まっていた欠損の合計時間 (省電力が働いた結果)。
  final Duration stationaryGapDuration;

  /// motionChange から算出した、静止していた時間の合計。
  /// motionChange が渡されなかった場合は [Duration.zero]。
  final Duration stationaryDuration;

  /// Haversine 公式で積算した総移動距離 (メートル)。
  /// 精度が悪いサンプル (accuracy > accuracyRejectMeters) を含む区間は除外する。
  final double totalDistanceMeters;

  /// 精度不良により距離計算から除外された区間数。
  final int rejectedSegments;

  /// 精度 (accuracy) の中央値。値を持つサンプルが 1 件もなければ `null`。
  final double? medianAccuracy;

  /// 精度 (accuracy) の 95 パーセンタイル値。
  final double? p95Accuracy;

  /// 開始時と終了時のバッテリー残量の差分 (%)。どちらかが `null` なら `null`。
  final int? batteryDropPercent;

  /// 1 時間あたりのバッテリー消費率 (%/時)。
  /// [batteryDropPercent] が `null`、またはセッション時間が 0 の場合は `null`。
  final double? batteryDropPerHour;

  /// activity 値ごとのサンプル数 (activity が `null` のサンプルは集計しない)。
  final Map<String, int> activityHistogram;

  /// isMoving == true のサンプル数。
  final int movingSampleCount;

  /// 地球の平均半径 (メートル)。Haversine 公式で使用。
  static const double _earthRadiusMeters = 6371008.8;

  /// [samples] からメトリクスを計算する。
  ///
  /// - 空リスト・要素 1 件・タイムスタンプ重複・入力の順序が recordedAt 順で
  ///   ない場合でも例外を投げない。
  /// - [gapThreshold] を超える取得間隔を欠損として扱う (既定 60 秒)。
  /// - [accuracyRejectMeters] を超える精度 (accuracy) を持つサンプルが
  ///   関わる区間は距離計算から除外する (既定 50 メートル)。
  factory SessionMetrics.compute(
    List<LocationSample> samples, {
    required DateTime sessionStart,
    required DateTime sessionEnd,
    int? batteryAtStart,
    int? batteryAtEnd,
    Duration gapThreshold = const Duration(seconds: 60),
    double accuracyRejectMeters = 50,
    List<MotionChangeRecord> motionChanges = const <MotionChangeRecord>[],
    double stationaryOverlapThreshold = 0.8,
    double stationarySpeedThresholdKmh = 1.0,
  }) {
    // 静止区間を組み立てる。渡されなければ空になり、
    // すべての欠損が「原因不明」として扱われる (従来どおりの挙動)。
    final stationary = buildStationaryIntervals(
      motionChanges,
      sessionStart: sessionStart,
      sessionEnd: sessionEnd,
    );
    final sorted = List<LocationSample>.of(samples)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    final wallClockDuration = sessionEnd.isAfter(sessionStart)
        ? sessionEnd.difference(sessionStart)
        : Duration.zero;

    final intervals = <Duration>[];
    final gaps = <Gap>[];
    var rejectedSegments = 0;
    var totalDistanceMeters = 0.0;

    // セッション開始から最初のサンプルまでの欠損。
    //
    // ここを見ないと「計測が一度も始まらなかった」ケースを検出できない。
    // またこの区間は正常時でも必ず 0 より大きい。呼び出し側はセッション開始
    // 時刻を記録してから Health Connect の読み出しを待ち、そのあとで
    // provider.start() を呼ぶうえ、GPS のコールドスタートも加わるためである。
    if (sorted.isNotEmpty) {
      final headGap = _clampNonNegative(
        sorted.first.recordedAt.difference(sessionStart),
      );
      if (headGap > gapThreshold) {
        gaps.add(
          Gap(
            from: sessionStart,
            to: sorted.first.recordedAt,
            duration: headGap,
            position: GapPosition.head,
          ),
        );
      }
    }

    for (var i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final cur = sorted[i];
      final rawDiff = cur.recordedAt.difference(prev.recordedAt);
      // 入力が recordedAt でソートされていない・逆転している異常値も
      // 例外にせず 0 として扱う。
      final diff = rawDiff.isNegative ? Duration.zero : rawDiff;
      intervals.add(diff);
      if (diff > gapThreshold) {
        // 欠損の両端がどれだけ離れているかを測る。
        // ほとんど動いていなければ、その間は歩いていなかったということ。
        final displacement = _haversineMeters(
          prev.latitude,
          prev.longitude,
          cur.latitude,
          cur.longitude,
        );
        final seconds = diff.inMicroseconds / Duration.microsecondsPerSecond;
        gaps.add(
          Gap(
            from: prev.recordedAt,
            to: cur.recordedAt,
            duration: diff,
            position: GapPosition.interior,
            displacementMeters: displacement,
            impliedSpeedKmh: seconds > 0 ? displacement / seconds * 3.6 : null,
          ),
        );
      }

      final prevAcc = prev.accuracy;
      final curAcc = cur.accuracy;
      final isRejected =
          (prevAcc != null && prevAcc > accuracyRejectMeters) ||
          (curAcc != null && curAcc > accuracyRejectMeters);
      if (isRejected) {
        rejectedSegments++;
      } else {
        totalDistanceMeters += _haversineMeters(
          prev.latitude,
          prev.longitude,
          cur.latitude,
          cur.longitude,
        );
      }
    }

    // 最後のサンプルからセッション終了までの欠損。
    //
    // __本スパイクが検出すべき失敗そのもの。__ 15 分の歩行のうち 3 分で
    // 計測が死んで戻らなかった場合、サンプル間だけを見ていると
    // 「欠損 0 回・欠損率 0%・取得間隔も健全」という、正常な計測と
    // 見分けのつかない結果になる。
    if (sorted.isNotEmpty) {
      final tailGap = _clampNonNegative(
        sessionEnd.difference(sorted.last.recordedAt),
      );
      if (tailGap > gapThreshold) {
        gaps.add(
          Gap(
            from: sorted.last.recordedAt,
            to: sessionEnd,
            duration: tailGap,
            position: GapPosition.tail,
          ),
        );
      }
    } else if (wallClockDuration > gapThreshold) {
      // サンプルが 1 件も無い = 完全な失敗。最も目立たせるべきケース。
      gaps.add(
        Gap(
          from: sessionStart,
          to: sessionEnd,
          duration: wallClockDuration,
          position: GapPosition.whole,
        ),
      );
    }

    // 各欠損を「静止中」か「原因不明」かに分類する。
    //
    // 欠損の大半 (既定 80% 以上) が静止区間に収まっていれば、
    // 省電力が働いた正常な動作とみなす。
    // そうでなければ、動いているのに取得できていなかったということ。
    // 欠損ごとに、静止区間と重なっている分と、そうでない分に分ける。
    //
    // __欠損を丸ごとどちらかに振り分けてはならない。__ 一部だけ静止と
    // 重なる欠損では合計が実態と合わなくなり、実データでは
    // 「移動中の欠損率 291%」のような破綻した値が出た。
    // 重なった分だけを静止として差し引き、残りを原因不明として数える。
    // こうすれば両者の合計が必ず総欠損時間に一致する。
    final classified = <Gap>[];
    var unexplainedGapDuration = Duration.zero;
    var stationaryGapDuration = Duration.zero;
    for (final g in gaps) {
      var covered = Duration.zero;
      for (final iv in stationary) {
        covered += iv.overlapWith(g.from, g.to);
      }
      if (covered > g.duration) covered = g.duration;

      // __判定の優先順位__
      //
      // 1. 欠損中の実測変位が分かるなら、それだけで決める。
      //    その間に実際どれだけ動いたかを直接測っているため最も確実で、
      //    ライブラリ自身の静止検知より信頼できる。
      //    実機では fbg が、実際に止まってから 15 分後にようやく
      //    motionChange を発火した例を観測している。
      //    ここで motionChange の重なり分を差し引くと、
      //    「歩いていたのに静止として免罪される」ことになる。
      //
      // 2. 変位が測れない欠損 (開始直後・終了直前・セッション全体) だけ、
      //    motionChange の重なりを根拠に使う。
      final speed = g.impliedSpeedKmh;
      if (speed != null) {
        if (speed < stationarySpeedThresholdKmh) {
          stationaryGapDuration += g.duration;
        } else {
          unexplainedGapDuration += g.duration;
        }
      } else {
        final uncovered = g.duration - covered;
        stationaryGapDuration += covered;
        unexplainedGapDuration += uncovered;
      }

      final ratio = g.duration.inMicroseconds == 0
          ? 0.0
          : covered.inMicroseconds / g.duration.inMicroseconds;
      final speedForLabel = g.impliedSpeedKmh;
      classified.add(
        Gap(
          from: g.from,
          to: g.to,
          duration: g.duration,
          position: g.position,
          displacementMeters: g.displacementMeters,
          impliedSpeedKmh: g.impliedSpeedKmh,
          cause:
              (speedForLabel != null &&
                  speedForLabel < stationarySpeedThresholdKmh)
              ? GapCause.stationary
              : (speedForLabel == null && ratio >= stationaryOverlapThreshold)
              ? GapCause.stationary
              : GapCause.unexplained,
        ),
      );
    }
    gaps
      ..clear()
      ..addAll(classified);

    final stationaryDuration = stationary.fold<Duration>(
      Duration.zero,
      (sum, iv) => sum + iv.to.difference(iv.from),
    );
    // 分母は「移動していた時間」。静止時間を除くことで、
    // 正しく省電力しているライブラリが不利にならないようにする。
    final movingDuration = _clampNonNegative(
      wallClockDuration - stationaryDuration,
    );
    final unexplainedGapRatio = movingDuration.inMicroseconds == 0
        ? 0.0
        : math.min(
            1.0,
            unexplainedGapDuration.inMicroseconds /
                movingDuration.inMicroseconds,
          );

    final totalGapDuration = gaps.fold<Duration>(
      Duration.zero,
      (sum, g) => sum + g.duration,
    );
    final gapRatio = wallClockDuration == Duration.zero
        ? 0.0
        : totalGapDuration.inMicroseconds / wallClockDuration.inMicroseconds;

    final accuracies = sorted
        .map((s) => s.accuracy)
        .whereType<double>()
        .toList(growable: false)
      ..sort();

    final batteryDropPercent = (batteryAtStart != null && batteryAtEnd != null)
        ? batteryAtStart - batteryAtEnd
        : null;
    final batteryDropPerHour =
        (batteryDropPercent != null && wallClockDuration.inSeconds > 0)
        ? batteryDropPercent / (wallClockDuration.inSeconds / 3600.0)
        : null;

    final activityHistogram = <String, int>{};
    var movingSampleCount = 0;
    for (final s in sorted) {
      final activity = s.activity;
      if (activity != null) {
        activityHistogram.update(activity, (v) => v + 1, ifAbsent: () => 1);
      }
      if (s.isMoving == true) {
        movingSampleCount++;
      }
    }

    return SessionMetrics(
      sampleCount: sorted.length,
      wallClockDuration: wallClockDuration,
      medianInterval: _percentileDuration(intervals, 50),
      p95Interval: _percentileDuration(intervals, 95),
      maxInterval: intervals.isEmpty
          ? Duration.zero
          : intervals.reduce((a, b) => a > b ? a : b),
      gaps: gaps,
      totalGapDuration: totalGapDuration,
      gapRatio: gapRatio,
      totalDistanceMeters: totalDistanceMeters,
      rejectedSegments: rejectedSegments,
      medianAccuracy: _percentileDouble(accuracies, 50),
      p95Accuracy: _percentileDouble(accuracies, 95),
      batteryDropPercent: batteryDropPercent,
      batteryDropPerHour: batteryDropPerHour,
      activityHistogram: activityHistogram,
      movingSampleCount: movingSampleCount,
      unexplainedGapDuration: unexplainedGapDuration,
      unexplainedGapRatio: unexplainedGapRatio,
      stationaryGapDuration: stationaryGapDuration,
      stationaryDuration: stationaryDuration,
    );
  }

  static double _degToRad(double deg) => deg * math.pi / 180.0;

  /// Haversine 公式による 2 点間の距離 (メートル)。
  static double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  /// 最近接順位法によるパーセンタイル。要素数が 0 の場合は Duration.zero。
  static Duration _percentileDuration(List<Duration> values, double percentile) {
    if (values.isEmpty) return Duration.zero;
    final sorted = List<Duration>.of(values)..sort();
    return sorted[_nearestRankIndex(sorted.length, percentile)];
  }

  /// 最近接順位法によるパーセンタイル。[values] は昇順ソート済みであること。
  /// 要素数が 0 の場合は `null`。
  static double? _percentileDouble(List<double> values, double percentile) {
    if (values.isEmpty) return null;
    return values[_nearestRankIndex(values.length, percentile)];
  }

  /// `motionChange` イベント列から静止区間を組み立てる。
  ///
  /// `isMoving == false` のイベントから、次の `isMoving == true` の
  /// イベント (無ければセッション終了) までを静止区間とみなす。
  ///
  /// 同じ状態が連続する重複イベントは無視する。実機のログでは
  /// 同一時刻に複数の motionChange が並ぶことがあるため。
  static List<StationaryInterval> buildStationaryIntervals(
    List<MotionChangeRecord> motionChanges, {
    required DateTime sessionStart,
    required DateTime sessionEnd,
  }) {
    if (motionChanges.isEmpty) return const <StationaryInterval>[];

    final sorted = List<MotionChangeRecord>.of(motionChanges)
      ..sort((a, b) => a.at.compareTo(b.at));

    final intervals = <StationaryInterval>[];
    DateTime? stoppedAt;
    for (final m in sorted) {
      if (!m.isMoving) {
        // 既に静止中なら、最初の静止時刻を維持する。
        stoppedAt ??= m.at;
      } else if (stoppedAt != null) {
        if (m.at.isAfter(stoppedAt)) {
          intervals.add(StationaryInterval(from: stoppedAt, to: m.at));
        }
        stoppedAt = null;
      }
    }
    // 静止したまま終わった場合は、セッション終了までを静止とみなす。
    if (stoppedAt != null && sessionEnd.isAfter(stoppedAt)) {
      intervals.add(StationaryInterval(from: stoppedAt, to: sessionEnd));
    }
    return intervals;
  }

  /// 負の [Duration] を 0 に丸める。
  /// サンプルの時刻がセッション区間の外にある異常入力でも、
  /// 負の欠損時間を出さないようにするため。
  static Duration _clampNonNegative(Duration d) =>
      d.isNegative ? Duration.zero : d;

  static int _nearestRankIndex(int length, double percentile) {
    final rank = (percentile / 100 * length).ceil().clamp(1, length);
    return rank - 1;
  }

  static String _formatDuration(Duration d) {
    final negative = d.isNegative;
    final abs = d.abs();
    final h = abs.inHours;
    final m = abs.inMinutes.remainder(60);
    final s = abs.inSeconds.remainder(60);
    final sign = negative ? '-' : '';
    return '$sign$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// プロバイダ比較表に貼り付けやすい、日本語の簡潔なレポート文字列を返す。
  String toReportString() {
    final buf = StringBuffer();
    buf.writeln('件数: $sampleCount 件');
    buf.writeln('計測時間: ${_formatDuration(wallClockDuration)}');
    buf.writeln('取得間隔中央値: ${_formatDuration(medianInterval)}');
    buf.writeln('取得間隔p95: ${_formatDuration(p95Interval)}');
    // 「最大取得間隔」はサンプルとサンプルの最大の空き。
    // 頭尾の欠損は含まないので、下の「最大欠損」と混同しないこと。
    buf.writeln('最大取得間隔(サンプル間): ${_formatDuration(maxInterval)}');
    buf.writeln('欠損回数: ${gaps.length} 回 (閾値超過区間)');
    buf.writeln('総欠損時間: ${_formatDuration(totalGapDuration)}');
    buf.writeln('欠損率(静止含む・参考値): ${(gapRatio * 100).toStringAsFixed(1)}%');
    buf.writeln(
      '  うち静止中(省電力・正常): ${_formatDuration(stationaryGapDuration)}',
    );
    buf.writeln(
      '★原因不明の欠損: ${_formatDuration(unexplainedGapDuration)} '
      '(移動中の ${(unexplainedGapRatio * 100).toStringAsFixed(1)}%)',
    );
    buf.writeln('  ※ ライブラリの比較にはこの「原因不明」を使うこと');
    buf.writeln('  ※ 静止判定は欠損中の実測変位から行う (1.0km/h 未満を静止)');
    if (stationaryDuration > Duration.zero) {
      buf.writeln('静止していた時間: ${_formatDuration(stationaryDuration)}');
    } else {
      buf.writeln('静止していた時間: 判定なし (motionChange が記録されていない)');
    }
    final maxGap = gaps.isEmpty
        ? Duration.zero
        : gaps.map((g) => g.duration).reduce((a, b) => a > b ? a : b);
    buf.writeln('最大欠損: ${_formatDuration(maxGap)}');
    if (gaps.isEmpty) {
      buf.writeln('欠損の内訳: なし');
    } else {
      final breakdown = <String, Duration>{};
      for (final g in gaps) {
        breakdown[g.positionLabel] =
            (breakdown[g.positionLabel] ?? Duration.zero) + g.duration;
      }
      buf.writeln(
        '欠損の内訳: '
        '${breakdown.entries.map((e) => '${e.key} ${_formatDuration(e.value)}').join(', ')}',
      );
      for (final g in gaps) {
        final speed = g.impliedSpeedKmh;
        final moved = speed != null
            ? ' 変位${g.displacementMeters!.toStringAsFixed(0)}m '
                  '(${speed.toStringAsFixed(1)}km/h)'
            : '';
        buf.writeln(
          '  - ${g.positionLabel} ${_formatDuration(g.duration)}'
          '$moved [${g.causeLabel}]',
        );
      }
      final tail = gaps.where(
        (g) => g.position == GapPosition.tail || g.position == GapPosition.whole,
      );
      if (tail.isNotEmpty) {
        buf.writeln(
          '警告: セッション終了まで位置情報が来ていない区間がある。'
          '計測が途中で止まった可能性が高い。',
        );
      }
    }
    buf.writeln(
      '移動距離: ${(totalDistanceMeters / 1000).toStringAsFixed(2)} km '
      '(精度不良で除外した区間: $rejectedSegments)',
    );
    buf.writeln(
      '精度中央値: ${medianAccuracy != null ? '${medianAccuracy!.toStringAsFixed(1)} m' : 'データなし'}',
    );
    buf.writeln(
      '精度p95: ${p95Accuracy != null ? '${p95Accuracy!.toStringAsFixed(1)} m' : 'データなし'}',
    );
    final batteryLine = StringBuffer('電池消費: ');
    if (batteryDropPercent != null) {
      batteryLine.write('$batteryDropPercent%');
      if (batteryDropPerHour != null) {
        batteryLine.write(' (${batteryDropPerHour!.toStringAsFixed(1)}%/時)');
      }
    } else {
      batteryLine.write('データなし');
    }
    buf.writeln(batteryLine.toString());
    buf.writeln('移動判定サンプル数: $movingSampleCount 件');
    final activityText = activityHistogram.isEmpty
        ? 'なし'
        : activityHistogram.entries.map((e) => '${e.key}=${e.value}').join(', ');
    buf.write('アクティビティ内訳: $activityText');
    return buf.toString();
  }
}
