import 'package:flutter/material.dart';

import '../health/health_steps_reader.dart';
import '../providers/provider_registry.dart';
import 'session_controller.dart';
import 'sessions_page.dart';

/// アプリのメイン画面。
///
/// 散歩に出る直前・帰ってきた直後に片手で操作することを想定した 1 画面。
/// 上から順に「プロバイダ選択 → 権限確認 → Health Connect 状態 →
/// 計測開始/停止 → ライブ表示 → 注意事項 → 記録一覧への導線」の並びにし、
/// スクロールするだけで一通りの状態が確認できるようにしている。
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('バックグラウンド計測スパイク')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (controller.providerStopFailureMessage != null) ...<Widget>[
                  _ProviderStopFailureBanner(controller: controller),
                  const SizedBox(height: 16),
                ],
                _ProviderSelector(controller: controller),
                const SizedBox(height: 16),
                _PermissionSection(controller: controller),
                const SizedBox(height: 16),
                _HealthConnectSection(controller: controller),
                const SizedBox(height: 24),
                _StartStopButton(controller: controller),
                const SizedBox(height: 16),
                _LiveReadout(controller: controller),
                if (controller.isRunning) ...<Widget>[
                  const SizedBox(height: 16),
                  const _RunningWarning(),
                ],
                const SizedBox(height: 24),
                if (controller.latestPluginRecordStats != null) ...<Widget>[
                  const SizedBox(height: 16),
                  _PluginRecordCrossCheck(controller: controller),
                ],
                const SizedBox(height: 24),
                _SessionsLink(controller: controller),
                if (controller.messages.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 24),
                  _MessagesSection(controller: controller),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// セクション 1: プロバイダ選択。計測中は変更できない。
class _ProviderSelector extends StatelessWidget {
  const _ProviderSelector({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'プロバイダ選択',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            RadioGroup<ProviderKind>(
              groupValue: controller.selectedProviderKind,
              onChanged: controller.isRunning
                  ? (ProviderKind? _) {}
                  : (ProviderKind? value) {
                      if (value != null) {
                        controller.switchProvider(value);
                      }
                    },
              child: Column(
                children: [
                  for (final kind in ProviderKind.values)
                    RadioListTile<ProviderKind>(
                      value: kind,
                      enabled: !controller.isRunning,
                      title: Text(labelOf(kind)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// セクション 2: 権限の状態。
///
/// issue #5 では「拒否された場合の挙動」も確認対象そのものであるため、
/// 拒否状態を隠さず、許可/拒否/未確認をはっきり色分けして見せる。
class _PermissionSection extends StatelessWidget {
  const _PermissionSection({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final outcome = controller.latestPermissionOutcome;
    final health = controller.latestHealthPermissionResult;

    final rows = <_PermissionRow>[
      _PermissionRow('位置情報 (使用中)', outcome?.fineLocationGranted),
      _PermissionRow('位置情報 (常に許可)', outcome?.backgroundLocationGranted),
      _PermissionRow('身体活動', outcome?.activityRecognitionGranted),
      _PermissionRow('通知', outcome?.notificationsGranted),
      _PermissionRow(
        'Health Connect 歩数',
        health == null
            ? null
            : health.status == HealthPermissionStatus.granted,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '権限の状態',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final row in rows) row,
            Padding(
              padding: const EdgeInsets.all(8),
              child: FilledButton.icon(
                onPressed: controller.requestAllPermissions,
                icon: const Icon(Icons.lock_open),
                label: const Text('権限をリクエスト'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow(this.label, this.granted);

  final String label;
  final bool? granted;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String statusText;
    if (granted == null) {
      color = Colors.grey;
      icon = Icons.help_outline;
      statusText = '未確認';
    } else if (granted!) {
      color = Colors.green;
      icon = Icons.check_circle;
      statusText = '許可';
    } else {
      color = Colors.red;
      icon = Icons.cancel;
      statusText = '拒否';
    }
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(label),
      trailing: Text(
        statusText,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// 歩数スナップショットの対象区間に応じた見出しを返す。
///
/// 「直近の歩数」のような曖昧なラベルにすると、計測開始時点の
/// 当日累計歩数を、この散歩で歩いた歩数として比較表へ転記されてしまう。
String _stepsLabel(StepsSnapshotScope? scope) {
  switch (scope) {
    case StepsSnapshotScope.beforeSession:
      return '計測開始時点の当日累計歩数';
    case StepsSnapshotScope.session:
      return 'この計測区間の歩数';
    case null:
      return '歩数';
  }
}

/// セクション 3: Health Connect の状態と直近の歩数スナップショット。
class _HealthConnectSection extends StatelessWidget {
  const _HealthConnectSection({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final availability = controller.healthAvailability;
    final snapshot = controller.latestStepsSnapshot;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Health Connect',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(availability?.message ?? '未確認です。'),
            if (availability != null && !availability.canRead) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: controller.openHealthConnectInstall,
                icon: const Icon(Icons.open_in_new),
                label: const Text('インストール'),
              ),
            ],
            if (snapshot != null) ...[
              const Divider(),
              // 開始時と終了時ではスナップショットの対象区間が違う。
              // 同じ「歩数」というラベルで出すと、当日の累計を
              // 「この散歩の歩数」として比較表へ転記される。
              Text(
                snapshot.error != null
                    ? '歩数の取得に失敗しました: ${snapshot.error}'
                    : '${_stepsLabel(controller.latestStepsSnapshotScope)}: '
                          '${snapshot.totalSteps ?? "不明"} 歩',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '対象区間: ${formatDateTime(snapshot.start)} 〜 '
                '${formatDateTime(snapshot.end)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (controller.latestStepsSnapshotScope ==
                  StepsSnapshotScope.beforeSession)
                Text(
                  'これは計測開始時点の当日累計です。この散歩の歩数ではありません。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              if (snapshot.sourceApps.isNotEmpty)
                Text('記録元アプリ: ${snapshot.sourceApps.join(", ")}'),
            ],
          ],
        ),
      ),
    );
  }
}

/// セクション 4: 大きな開始/停止ボタン。散歩に出る直前に片手で押す想定。
class _StartStopButton extends StatelessWidget {
  const _StartStopButton({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final running = controller.isRunning;
    final elapsed = controller.elapsed;
    final elapsedText = elapsed != null ? formatDuration(elapsed) : '0:00:00';

    return SizedBox(
      width: double.infinity,
      height: 96,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: running ? Colors.red : Colors.green,
          textStyle: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        onPressed: running ? controller.stopSession : controller.startSession,
        child: Text(running ? '計測停止 ($elapsedText)' : '計測開始'),
      ),
    );
  }
}

/// セクション 5: ライブ表示。
///
/// 「最終取得からの経過秒数」が最重要指標: これが伸び続けている場合、
/// 画面ロック中にバックグラウンド計測が止まっている疑いが強い。
class _LiveReadout extends StatelessWidget {
  const _LiveReadout({required this.controller});

  final SessionController controller;

  /// 30 秒未満は正常 (緑)、120 秒未満は要注意 (黄)、それ以上は異常の疑い (赤)。
  /// 計測間隔は約 5 秒に設定されているため、30 秒あれば数回分の取りこぼしを
  /// 許容しつつ、120 秒を超えたら「明らかに止まっている」と判断できる。
  Color _ageColor(Duration? age) {
    if (age == null) return Colors.grey;
    if (age < const Duration(seconds: 30)) return Colors.green;
    if (age < const Duration(seconds: 120)) return Colors.amber;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final sample = controller.latestSample;
    final age = controller.lastFixAge;
    final battery = controller.latestBattery;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ライブ表示', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('サンプル数: ${controller.sampleCount} 件'),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('最終取得からの経過: '),
                Text(
                  age != null ? '${age.inSeconds} 秒' : 'データなし',
                  style: TextStyle(
                    color: _ageColor(age),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const Divider(),
            if (sample == null)
              const Text('まだサンプルがありません。')
            else ...[
              Text(
                '緯度/経度: ${sample.latitude.toStringAsFixed(6)}, '
                '${sample.longitude.toStringAsFixed(6)}',
              ),
              Text('精度: ${sample.accuracy?.toStringAsFixed(1) ?? "不明"} m'),
              Text('速度: ${sample.speed?.toStringAsFixed(1) ?? "不明"} m/s'),
              Text(
                '移動中: ${sample.isMoving == null ? "不明" : (sample.isMoving! ? "はい" : "いいえ")}',
              ),
              Text('活動: ${sample.activity ?? "不明"}'),
            ],
            const Divider(),
            Text(
              'バッテリー: '
              '${battery?.levelPercent != null ? "${battery!.levelPercent}%" : "不明"}'
              '${battery?.isCharging == true ? " (充電中)" : ""}',
            ),
          ],
        ),
      ),
    );
  }
}

/// セクション 6: 計測中のみ表示する注意書き。
class _RunningWarning extends StatelessWidget {
  const _RunningWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.black87),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '計測中は充電ケーブルを挿さないでください (電池比較が無効になります)。'
              'このアプリのバッテリー最適化も無効にしてください。',
              style: TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

/// セクション 7: 記録一覧への導線。
/// プロバイダの停止に失敗したままであることを知らせる警告バナー。
///
/// 停止できていない = Android の常駐フォアグラウンドサービスが動き続けている
/// ということで、そのまま次の計測に進むと電池消費が二重に乗る。
/// 流れて消えるメッセージ一覧では見落とすため、独立したバナーとして出す。
class _ProviderStopFailureBanner extends StatelessWidget {
  const _ProviderStopFailureBanner({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                controller.providerStopFailureMessage ?? '',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// プラグイン内部DBと自前ログの突き合わせ結果。
///
/// 自前ログが途切れていたときに、その原因が
/// 「ライブラリが計測を止めた」のか
/// 「アプリの Dart 側だけが落ちてネイティブは記録し続けていた」のかを
/// 切り分ける。両者を取り違えると、実際には正常に動いていたライブラリを
/// 不採用にしかねない。
class _PluginRecordCrossCheck extends StatelessWidget {
  const _PluginRecordCrossCheck({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final stats = controller.latestPluginRecordStats!;
    final jsonlCount = controller.sampleCount;
    final theme = Theme.of(context);

    final String verdict;
    if (!stats.supported) {
      verdict = 'このプラグインは記録件数の取得に対応していないため、突き合わせできません。';
    } else if (stats.error != null) {
      verdict = '読み出しに失敗しました: ${stats.error}';
    } else {
      final inWindow = stats.countInWindow ?? 0;
      if (inWindow > jsonlCount * 2 && inWindow - jsonlCount > 10) {
        verdict =
            'プラグイン側の記録が自前ログより大幅に多いです。'
            '計測中にアプリ (Dart 側) だけが停止し、ライブラリ自体は'
            '記録を続けていた可能性が高いです。ライブラリの不具合ではありません。';
      } else {
        verdict =
            '自前ログとプラグイン側の記録に大きな差はありません。'
            'Dart 側での取りこぼしは無いと考えられます。';
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'プラグイン内部記録との突き合わせ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('自前ログのサンプル数: $jsonlCount 件'),
            if (stats.countInWindow != null)
              Text('プラグイン記録 (計測区間内): ${stats.countInWindow} 件'),
            if (stats.totalCount != null)
              Text('プラグイン記録 (DB全体): ${stats.totalCount} 件'),
            if (stats.lastAt != null)
              Text('プラグイン側の最終記録: ${formatDateTime(stats.lastAt!)}'),
            const SizedBox(height: 8),
            Text(verdict, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              '注: flutter_background_geolocation は使い捨てサンプルを'
              '自前DBへ保存しないため、両者の件数は元々完全には一致しません。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionsLink extends StatelessWidget {
  const _SessionsLink({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SessionsPage(controller: controller),
          ),
        );
      },
      icon: const Icon(Icons.list_alt),
      label: const Text('記録一覧を見る'),
    );
  }
}

/// 直近の状態・エラーメッセージ表示。
class _MessagesSection extends StatelessWidget {
  const _MessagesSection({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('メッセージ', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            for (final message in controller.messages.reversed.take(5))
              Text('・$message', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
