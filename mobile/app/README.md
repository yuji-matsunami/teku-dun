# Teku Dun Flutter app

Flutter 3.47.0 の Android アプリです。API の接続先は必須で、
`API_BASE_URL` の `dart-define` で指定します。`task flutter:run` では、
Android エミュレータからホストの API に接続する
`http://10.0.2.2:8080` がローカル開発用の既定値として渡されます。

```sh
fvm flutter pub get
fvm flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
fvm flutter analyze
fvm flutter test
```

リポジトリルートから起動する場合は、次のタスクも利用できます。

```sh
task flutter:run
```

実機から接続する場合は、開発マシンの LAN アドレスなど、端末から到達可能な
URL を指定してください。平文 HTTP はデバッグビルドの Android 設定でのみ
許可し、リリースビルドでは HTTPS を使用します。

## Drift のスキーマ変更

`lib/src/data/local/app_database.dart` のテーブル定義を変更したら、リポジトリ
ルートで `task flutter:build` を実行して生成コード（`app_database.g.dart`）を
再生成し、差分をコミットしてください。生成コードは手で編集しません。

```sh
task flutter:build
```

`task` を使わずに `mobile/app` で直接実行する場合は、`fvm flutter pub get` の後に
次を実行します。

```sh
fvm flutter pub run build_runner build
```

生成コードが最新であることは `task flutter:verify` で確認できます。詳しくは
[開発手順](../../docs/development.md)を参照してください。

アプリの配布前は、マイグレーションを書かずに `schemaVersion` を 1 のまま
テーブル定義を直します。古い定義で作成済みの DB が端末に残っていると
`no such column` などのエラーになるため、スキーマが変わる変更を取り込んだら、
端末（エミュレータ）のアプリデータを消去するか、アプリを入れ直してください。

```sh
adb shell pm clear dev.tekudun.app
```

配布後にスキーマを変える場合は、`schemaVersion` を上げてマイグレーションを書きます。
