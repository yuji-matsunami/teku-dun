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
