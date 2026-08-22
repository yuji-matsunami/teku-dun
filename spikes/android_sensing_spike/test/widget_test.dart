// アプリ起動時の最小限のスモークテスト。
//
// 実機のプラットフォームチャンネル (位置情報プラグイン・Health Connect・
// バッテリー・端末情報など) はテスト環境には存在しないため、
// SessionController.init() 内の各呼び出しは MissingPluginException を
// 握りつぶしつつも最後まで完了するはずである。
//
// 注意: 初期化中は CircularProgressIndicator (不確定アニメーション) が
// 表示され続けるため、`pumpAndSettle()` はアニメーションが収束せず
// 永遠にタイムアウトしてしまう。また、プラットフォームチャンネル越しの
// 応答は通常の `pump()` (フェイクタイムゾーン) だけでは処理されないため、
// `runAsync()` で実イベントループを一度回してから `pump()` する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:android_sensing_spike/main.dart';

void main() {
  testWidgets('アプリが起動し計測開始ボタンが表示される', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // 初期化中はローディングインジケータが出る。
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // SessionController.init() (プラットフォームチャンネル呼び出しを含む) の
    // 完了を実イベントループ上で待つ。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    // メイン画面のタイトルが表示されていること。
    expect(find.text('バックグラウンド計測スパイク'), findsOneWidget);

    // 開始ボタンは画面下方にあるため、テスト用の小さいビューポートでは
    // 初期状態で画面外に位置する。スクロールして表示されることを確認する。
    await tester.scrollUntilVisible(
      find.text('計測開始'),
      300.0,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('計測開始'), findsOneWidget);
  });
}
