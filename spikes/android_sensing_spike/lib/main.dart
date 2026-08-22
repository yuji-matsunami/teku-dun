import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:tracelet/tracelet.dart' as tl;

import 'providers/headless_task.dart';
import 'ui/home_page.dart';
import 'ui/session_controller.dart';

void main() {
  runApp(const MyApp());

  // ヘッドレスタスクの登録は runApp のあと、必ず main() の中で行う。
  //
  // アプリ (Dart isolate) が OS に停止させられても、両ライブラリの
  // ネイティブサービスは `stopOnTerminate: false` により記録を続ける。
  // ここで登録しておかないと、その間の記録が JSONL に一切残らず、
  // 「ライブラリが計測を止めた」のか「アプリだけが落ちた」のかを
  // 区別できなくなる。
  //
  // 実機ログで確認済み: 設定に enableHeadless を入れても、この登録が
  // 無ければ `☯️ HeadlessMode? true` と出るだけで何も実行されない。
  bg.BackgroundGeolocation.registerHeadlessTask(fbgHeadlessTask);
  tl.Tracelet.registerHeadlessTask(traceletHeadlessTask);
}

/// アプリのルートウィジェット。
///
/// [SessionController] をここで 1 つだけ生成し、アプリ起動時に
/// [SessionController.init] を実行する。初期化が終わるまでは
/// ローディング表示にし、完了後に [HomePage] を表示する。
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final SessionController _controller = SessionController();
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'バックグラウンド計測スパイク',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return HomePage(controller: _controller);
        },
      ),
    );
  }
}
