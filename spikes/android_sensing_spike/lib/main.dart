import 'package:flutter/material.dart';

import 'ui/home_page.dart';
import 'ui/session_controller.dart';

void main() {
  runApp(const MyApp());
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
