# OpenAPI仕様書

## ブラウザでプレビューする

リポジトリのルートから次のコマンドを実行します。

```sh
task openapi:preview
```

起動後、ブラウザで [http://127.0.0.1:8081](http://127.0.0.1:8081) を開くと、RedoclyによるAPI仕様書を確認できます。プレビューはフォアグラウンドで動作するため、終了するときはターミナルで `Ctrl+C` を押してください。

IPv4のbind addressやポートを変更する場合は、Task変数を上書きします。

```sh
task openapi:preview OPENAPI_PREVIEW_HOST=127.0.0.1 OPENAPI_PREVIEW_PORT=18081
```

`OPENAPI_PREVIEW_HOST=0.0.0.0` を指定すると、ローカルマシン以外からも接続できるようになります。ファイアウォールやネットワーク設定を確認し、信頼できるネットワークでのみ使用してください。

プレビューで使用する仕様ファイルとRedocly設定は、情報の公開範囲を限定するため
`openapi/`ディレクトリ内に置きます。

## 仕様書を検証する

プレビュー前後には、仕様書の内容を次のTaskで検証できます。

```sh
task openapi:validate
task openapi:lint
```

`validate`はOpenAPI Generatorのvalidatorで仕様としての妥当性を検証します。
`lint`とプレビューは、固定したRedocly CLIコンテナを使用します。
