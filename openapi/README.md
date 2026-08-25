# OpenAPI仕様書

## OpenAPI 3.0.3を採用する理由

仕様書ではOpenAPI **3.0.3**を使用します。現時点では、次の理由から
OpenAPI 3.1ではなく3.0.3を選択しています。

- Goサーバーの`oapi-codegen` v2.4.1と、DartクライアントのOpenAPI Generator
  v7.10.0を組み合わせたコード生成を、このバージョンで検証している。
- validator、Redoclyによるlint・プレビューを含む現在のツールチェーンで、
  サーバーとクライアントの共通契約として安定して扱える。
- 現在のAPIは、OpenAPI 3.1で強化されたJSON Schemaとの整合性など、
  3.1固有の機能を必要としていない。

OpenAPI 3.1への移行は、3.1固有の表現が必要になった場合、または利用する
validator、Redocly、`oapi-codegen`、OpenAPI Generatorが3.1を一貫して扱えることを
確認できた段階で検討します。移行時には、GoとDartの生成差分、既存APIとの互換性、
validate・lint・プレビューの結果を確認します。

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
