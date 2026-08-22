import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/metrics/session_metrics.dart';
import '../core/models/location_sample.dart';
import '../core/models/session_meta.dart';
import '../core/models/tracking_event.dart';
import '../providers/provider_registry.dart';
import 'session_controller.dart';

/// providerId ("fbg" / "tracelet") から人間可読なラベルへ変換する。
///
/// [ProviderKind] の enum ケース名 (`.name`) が各プロバイダ実装の `id`
/// (`FbgLocationProvider.id` / `TraceletLocationProvider.id`) と一致するよう
/// 設計されているため、この対応関係を利用してラベルを引く。
/// 万一未知の ID だった場合は、そのまま ID を表示する。
String _labelForProviderId(String providerId) {
  for (final kind in ProviderKind.values) {
    if (kind.name == providerId) {
      return labelOf(kind);
    }
  }
  return providerId;
}

/// 保存済み計測セッションの一覧画面。
///
/// 散歩から帰ってきたテスターが、その場で比較表を埋められるように
/// する画面。新しい順に並べ、タップすると比較用メトリクスを表示する。
class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key, required this.controller});

  final SessionController controller;

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  late Future<List<SessionMeta>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SessionMeta>> _load() {
    final store = widget.controller.store;
    if (store == null) return Future<List<SessionMeta>>.value(const []);
    return store.listSessions();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _share(SessionMeta meta) async {
    final store = widget.controller.store;
    if (store == null) return;
    final file = await store.exportSessionAsJsonl(meta.id);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  Future<void> _confirmDelete(SessionMeta meta) async {
    final store = widget.controller.store;
    if (store == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('セッションを削除しますか?'),
        content: Text('ID: ${meta.id}\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.deleteSession(meta.id);
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('記録一覧')),
      body: FutureBuilder<List<SessionMeta>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data ?? const <SessionMeta>[];
          if (sessions.isEmpty) {
            return const Center(child: Text('保存されたセッションはありません。'));
          }
          return ListView.separated(
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final meta = sessions[index];
              final duration = meta.endedAt?.difference(meta.startedAt);
              return ListTile(
                title: Text(_labelForProviderId(meta.providerId)),
                subtitle: Text(
                  '開始: ${formatDateTime(meta.startedAt)}\n'
                  '計測時間: ${duration != null ? formatDuration(duration) : "計測中"}',
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.share),
                      tooltip: '共有',
                      onPressed: () => _share(meta),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '削除',
                      onPressed: () => _confirmDelete(meta),
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _SessionDetailPage(
                        controller: widget.controller,
                        meta: meta,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// セッション詳細画面。比較用メトリクス・端末情報・プロバイダ設定を表示する。
class _SessionDetailPage extends StatefulWidget {
  const _SessionDetailPage({required this.controller, required this.meta});

  final SessionController controller;
  final SessionMeta meta;

  @override
  State<_SessionDetailPage> createState() => _SessionDetailPageState();
}

/// セッション詳細画面が表示するために読み出した内容一式。
class _SessionDetail {
  const _SessionDetail({
    required this.metrics,
    required this.stepsEvents,
    required this.pluginRecordEvents,
    required this.locationSampleCount,
  });

  final SessionMetrics? metrics;

  /// healthSnapshot イベント (phase: start / end)。
  final List<Map<String, dynamic>> stepsEvents;

  /// pluginRecordStats イベント。
  final List<Map<String, dynamic>> pluginRecordEvents;

  /// ログに残っていた位置サンプル件数。
  final int locationSampleCount;
}

class _SessionDetailPageState extends State<_SessionDetailPage> {
  late Future<_SessionDetail?> _future;

  static const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

  @override
  void initState() {
    super.initState();
    _future = _computeMetrics();
  }

  Future<_SessionDetail?> _computeMetrics() async {
    final store = widget.controller.store;
    if (store == null) return null;
    final rawEvents = await store.readEvents(widget.meta.id);
    final samples = <LocationSample>[];
    for (final json in rawEvents) {
      if (json['type'] == 'location') {
        samples.add(LocationSample.fromJson(json));
      }
    }
    // 未終了セッション (endedAt が無い) で DateTime.now() を代入してはならない。
    //
    // 15分の散歩を3時間後に開いただけで「計測時間 3:47:12」という
    // それらしい数字が出てしまい、欠損率も同じ分母で薄まる。
    // アプリが計測中に OS に落とされると未終了セッションは普通に発生するため、
    // 現実に起こる。
    //
    // 代わりに「実際に記録が残っている最後の時刻」を終端とする。
    // これは観測された事実だけから決まる値であり、画面を開いた時刻に
    // 依存しない。あわせて未終了である旨を画面に明示する。
    final endedAt = widget.meta.endedAt ?? _lastRecordedAt(rawEvents, samples);

    final metrics = SessionMetrics.compute(
      samples,
      sessionStart: widget.meta.startedAt,
      sessionEnd: endedAt ?? widget.meta.startedAt,
      batteryAtStart: widget.meta.batteryAtStart,
      batteryAtEnd: widget.meta.batteryAtEnd,
    );

    // 歩数と突き合わせ結果は JSONL のイベントにしか無い。
    // ここで読み出さないと、issue #5 の成果物である「この散歩の歩数」を
    // ホーム画面を閉じたあと確認する手段が無くなる。
    final stepsEvents = <Map<String, dynamic>>[];
    final pluginRecordEvents = <Map<String, dynamic>>[];
    for (final json in rawEvents) {
      if (json['type'] != 'event') continue;
      switch (json['kind']) {
        case TrackingEventKind.healthSnapshot:
          stepsEvents.add(json);
        case TrackingEventKind.pluginRecordStats:
          pluginRecordEvents.add(json);
      }
    }

    return _SessionDetail(
      metrics: metrics,
      stepsEvents: stepsEvents,
      pluginRecordEvents: pluginRecordEvents,
      locationSampleCount: samples.length,
    );
  }

  /// ログに残っている最後の時刻を返す。
  /// 位置サンプルとイベントの両方を見て、最も新しいものを採用する。
  static DateTime? _lastRecordedAt(
    List<Map<String, dynamic>> rawEvents,
    List<LocationSample> samples,
  ) {
    DateTime? latest;
    void consider(DateTime? candidate) {
      if (candidate == null) return;
      if (latest == null || candidate.isAfter(latest!)) {
        latest = candidate;
      }
    }

    for (final sample in samples) {
      consider(sample.recordedAt);
    }
    for (final json in rawEvents) {
      if (json['type'] != 'event') continue;
      final at = json['at'];
      if (at is String) {
        consider(DateTime.tryParse(at)?.toUtc());
      }
    }
    return latest;
  }

  Future<void> _share() async {
    final store = widget.controller.store;
    if (store == null) return;
    final file = await store.exportSessionAsJsonl(widget.meta.id);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_labelForProviderId(widget.meta.providerId)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '共有',
            onPressed: _share,
          ),
        ],
      ),
      body: FutureBuilder<_SessionDetail?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final detail = snapshot.data;
          final metrics = detail?.metrics;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ID: ${widget.meta.id}'),
                Text('開始: ${formatDateTime(widget.meta.startedAt)}'),
                Text(
                  '終了: ${widget.meta.endedAt != null ? formatDateTime(widget.meta.endedAt!) : "未終了"}',
                ),
                if (widget.meta.endedAt == null) ...<Widget>[
                  const SizedBox(height: 8),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'このセッションは正常に終了していません。'
                        'アプリが計測中に停止した可能性があります。\n'
                        '以下の数値は「ログに残っている最後の記録」までを'
                        '計測時間として算出したものです。'
                        '電池消費は終了時の残量が無いため算出できません。'
                        '比較表へはそのまま転記せず、計測をやり直してください。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  '比較レポート',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  metrics?.toReportString() ?? 'メトリクスを計算できませんでした。',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'この計測区間の歩数 (Health Connect)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _StepsSummary(events: detail?.stepsEvents ?? const []),
                if ((detail?.pluginRecordEvents ?? const []).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'プラグイン内部記録との突き合わせ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _PluginRecordSummary(
                    events: detail!.pluginRecordEvents,
                    locationSampleCount: detail.locationSampleCount,
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  '端末情報',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _prettyJson.convert(widget.meta.deviceInfo),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'プロバイダ設定',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _prettyJson.convert(widget.meta.providerConfig),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// セッション区間の歩数を表示する。
///
/// phase: "end" のスナップショットが、issue #5 の比較表に載せるべき
/// 「この散歩で歩いた歩数」。phase: "start" は開始時点の当日累計であり、
/// 混同しないよう区別して見せる。
class _StepsSummary extends StatelessWidget {
  const _StepsSummary({required this.events});

  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? endEvent;
    Map<String, dynamic>? startEvent;
    for (final e in events) {
      if (e['phase'] == 'end') endEvent = e;
      if (e['phase'] == 'start') startEvent = e;
    }

    if (endEvent == null) {
      return Text(
        startEvent == null
            ? '歩数の記録がありません。Health Connect の権限が拒否されていた可能性があります。'
            : '計測区間の歩数が記録されていません (セッションが正常終了していない可能性)。',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final steps = endEvent['totalSteps'];
    final sources = endEvent['sourceApps'];
    final error = endEvent['error'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null)
          Text('取得に失敗しました: $error')
        else
          Text(
            '${steps ?? "不明"} 歩',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        if (sources is List && sources.isNotEmpty)
          Text('記録元アプリ: ${sources.join(", ")}'),
        if (startEvent != null)
          Text(
            '(参考) 計測開始時点の当日累計: ${startEvent['totalSteps'] ?? "不明"} 歩',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// プラグイン内部DBと自前ログの件数を突き合わせて表示する。
class _PluginRecordSummary extends StatelessWidget {
  const _PluginRecordSummary({
    required this.events,
    required this.locationSampleCount,
  });

  final List<Map<String, dynamic>> events;
  final int locationSampleCount;

  @override
  Widget build(BuildContext context) {
    final e = events.last;
    final supported = e['supported'] == true;
    final error = e['error'];
    final inWindow = e['countInWindow'];
    final total = e['totalCount'];
    final lastAt = e['lastAt'];

    final String verdict;
    if (!supported) {
      verdict = 'このプラグインは記録件数の取得に対応していないため、突き合わせできません。';
    } else if (error != null) {
      verdict = '読み出しに失敗しました: $error';
    } else if (inWindow is int &&
        inWindow > locationSampleCount * 2 &&
        inWindow - locationSampleCount > 10) {
      verdict =
          'プラグイン側の記録が自前ログより大幅に多いです。'
          '計測中にアプリ (Dart 側) だけが停止し、ライブラリ自体は記録を'
          '続けていた可能性が高いです。ライブラリの不具合ではありません。';
    } else {
      verdict = '自前ログとプラグイン側の記録に大きな差はありません。';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('自前ログのサンプル数: $locationSampleCount 件'),
        if (inWindow != null) Text('プラグイン記録 (計測区間内): $inWindow 件'),
        if (total != null) Text('プラグイン記録 (DB全体): $total 件'),
        if (lastAt is String)
          Text(
            'プラグイン側の最終記録: '
            '${formatDateTime(DateTime.parse(lastAt).toUtc())}',
          ),
        const SizedBox(height: 8),
        Text(verdict),
        const SizedBox(height: 4),
        Text(
          '注: flutter_background_geolocation は使い捨てサンプルを'
          '自前DBへ保存しないため、両者の件数は元々完全には一致しません。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
