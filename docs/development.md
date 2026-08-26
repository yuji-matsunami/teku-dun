# 開発手順

このリポジトリのIssue #4で定義した、再現可能な最小開発環境の手順です。
対象環境は **macOS + Android（AndroidエミュレータまたはAndroid実機）** とします。
iOS、Windows、Linuxでの動作はこの手順の保証対象ではありません。

## 構成

ローカルでは、PostGISだけをDocker Composeで起動し、Go APIとFlutterアプリは
ホスト上で起動します。

| コンポーネント | 場所 | 役割 |
| --- | --- | --- |
| PostGIS | `compose.yaml` の `db` | DBとPostGIS拡張 |
| マイグレーション | `db/migrations/` | DBスキーマの適用 |
| OpenAPI | `openapi/openapi.yaml` | Go/Dartクライアントの契約 |
| Go API | `api/` | `/healthz` と `/readyz` |
| Dart APIクライアント | `mobile/packages/api_client/` | OpenAPIから生成した型付きクライアント |
| Flutterアプリ | `mobile/app/` | Androidの疎通確認画面 |

## 前提ツール

次のツールをmacOSにインストールしてください。

- Go **1.24.6**。`api/go.mod` の `toolchain go1.24.6` に合わせます。
- Flutter **3.47.0** と [FVM](https://fvm.app/)。`mobile/app/.fvmrc` に固定しています。
- Docker Desktop（Docker Engine と Compose v2）。OpenAPI検証、Dart生成、PostGISに使用します。
- Android Studio、Android SDK、Android Emulator。Android SDKのライセンスを承諾し、エミュレータを作成できる状態にします。
- go-task **3.53.1** 以上。Taskfileで開発コマンドを実行します。Homebrewでは
  `brew install go-task` でインストールできます。
- `curl`。macOSに含まれるものを使用できます。

バージョンを確認します。

```sh
go version                 # go1.24.6 を確認
fvm --version
docker --version
docker compose version
task --version
curl --version
```

この手順では、Task CLI **3.53.1**で確認しています。Taskのメジャーバージョンを
更新する場合は、Taskfileのincludeや変数の仕様が変わっていないことを確認してから
更新してください。

Android StudioのSDK Managerでは、Flutter 3.47.0で利用するAndroid SDKと、
SDK Platform-Tools、Android Emulatorをインストールしてください。`flutter doctor`
がAndroid toolchainの不足を示す場合は、Android Studioで不足項目を解消してから
再実行します。

> **このIssueでの未検証事項**: この作業環境ではAndroid SDKがないため、
> `flutter build apk`（APKビルド）は実行していません。APKビルドをIssue #4の
> 検証済み項目とは扱わず、Android SDKを用意した環境で別途確認してください。

## クリーンなcloneからのセットアップ

1. リポジトリをcloneし、ルートに移動します。

   ```sh
   git clone https://github.com/yuji-matsunami/teku-dun.git
   cd teku-dun
   ```

2. ローカル設定を作成します。`.env` はGit管理対象外です。

   ```sh
   cp .env.example .env
   ```

   `.env.example` にはローカルDBのデフォルト値だけを置いています。パスワードや
   トークンなどの秘密を`.env`、ソース、ログ、コミットに書かないでください。
   DBの値を変更する場合は、Composeの`POSTGRES_*`と、マイグレーションコンテナ用の
   `MIGRATE_DATABASE_URL`（URL中の資格情報はpercent-encode）を一致させます。

3. FVMで固定バージョンのFlutterを取得し、Flutterの依存関係を取得します。

   ```sh
   cd mobile/app
   fvm install 3.47.0
   fvm flutter --version
   fvm flutter pub get
   cd ../..
   ```

   Dart APIクライアントの依存関係も取得します。生成チェックと同じ固定Dart
   コンテナを使うため、Dockerが起動している必要があります。

   ```sh
   task dart:pub-get
   ```

   Dart APIクライアントの検証は、デフォルトでは固定Dartコンテナ（`DART_MODE=docker`）
   で実行します。Dart SDKをホストにインストール済みで、ホストのDartを使いたい場合だけ
   `DART_MODE=host`を指定します（例: `task dart:verify DART_MODE=host`）。

4. PostGISを起動し、マイグレーションを適用します。

   ```sh
   task db:up
   task db:migrate
   task db:verify
   ```

   `task db:up`はhealthcheckが成功するまで待ち、`task db:migrate`は未適用のマイグレーションを
   適用します。`task db:verify`は`PostGIS_Version()`の結果を表示します。

5. OpenAPI契約を検証します。

   ```sh
   task openapi:validate
   task openapi:lint
   ```

   ブラウザで仕様書を確認する場合は、ローカルプレビューを起動します。

   ```sh
   task openapi:preview
   ```

   [http://127.0.0.1:8081](http://127.0.0.1:8081)を開き、確認後は
   ターミナルで`Ctrl-C`を押して終了します。Go APIの既定ポート`8080`とは分けています。
   詳細と公開先の変更方法は[OpenAPI仕様書](../openapi/README.md)を参照してください。

## APIとFlutterの起動

### Androidエミュレータ

APIを起動するターミナルを1つ用意します。

```sh
task api:run
```

APIはデフォルトで`API_ADDR=:8080`、DBは`127.0.0.1:5432`に接続します。
別のアドレスやポートを使う場合は、APIプロセスに環境変数を渡します。

```sh
API_ADDR=0.0.0.0:8080 DATABASE_URL='postgres://teku_dun:teku_dun@127.0.0.1:5432/teku_dun?sslmode=disable' task api:run
```

別のターミナルで、Androidエミュレータを起動してからFlutterアプリを起動します。

```sh
task flutter:run API_BASE_URL=http://10.0.2.2:8080
```

Androidエミュレータの`10.0.2.2`は、開発Macのloopback（`127.0.0.1`）を指す特別な
アドレスです。Androidアプリの`localhost`または`127.0.0.1`はMacではなく、
エミュレータ自身を指すため使用しません。`API_BASE_URL`を省略した場合も、
Flutterアプリのデフォルトは`http://10.0.2.2:8080`です。

アプリに次の表示が出れば、Flutterから`/healthz`への疎通に成功しています。

```text
API is healthy
The health check returned OK.
```

### Android実機

実機とMacを同じLAN（通常は同じWi-Fi）に接続し、MacのLAN IPを確認します。

```sh
ipconfig getifaddr en0
```

Wi-Fiインターフェースが`en1`などの場合は、実際に使用しているインターフェースの
アドレスを指定します。APIをLANから到達可能なアドレスにbindし、`API_BASE_URL`に
MacのLAN IPを指定します。

```sh
API_ADDR=0.0.0.0:8080 task api:run
task flutter:run API_BASE_URL=http://192.168.1.23:8080
```

`192.168.1.23`は例なので、実際のMacのアドレスに置き換えてください。実機からは
`localhost`、`127.0.0.1`、エミュレータ専用の`10.0.2.2`を使いません。Macの
ファイアウォールが有効な場合は、Go APIのTCP `8080`（変更した場合はそのポート）への
受信を許可してください。公衆ネットワークで全インターフェースにbindしない、
確認後はAPIを停止する、という点にも注意してください。

## 端末不要の通常検証

`verify`はDB、Androidエミュレータ、実機を必要としない静的検証です。OpenAPI、Go API、
Dart APIクライアント、Flutterアプリの各検証をまとめて実行します。

```sh
task verify
```

FlutterをFVM以外の固定パスで実行する場合は、次のように上書きできます。

```sh
task verify FLUTTER=/private/tmp/flutter-3.47.0/bin/flutter
```

通常検証が行う内容は次のとおりです。各コンポーネントは前の検証が成功した後に
順番に実行されます。

- OpenAPIのvalidator検証とRedocly lint
- Go生成物のドリフト確認、Goテスト、`go vet`
- DartクライアントのOpenAPI生成物ドリフト確認、`build_runner`生成物確認、analyze、test
- Flutterアプリのanalyze、test

生成物にドリフトがある場合、検証を通すために生成ファイルを直接編集してはいけません。
後述の生成手順で再生成し、差分の原因となった契約または生成設定をレビューしてください。

## DB込みの統合スモークテスト

次のコマンドは、DB起動、マイグレーション、Go APIの一時ビルド・起動、`healthz`/
`readyz`のcurl検証、API停止、開始前の状態に応じたDBの復元までを一度に行います。

```sh
task smoke
```

`smoke`はデフォルトで`127.0.0.1:18080`を一時APIポートに使い、既存のリスナーが
ある場合は開始前に失敗します。必要なら未使用ポートに変更します。

```sh
task smoke SMOKE_API_PORT=18081
```

`SMOKE_API_TIMEOUT`はAPI起動待ち時間を秒で指定する正の整数です（デフォルト30秒）。
`0`や負数、数字以外は入力エラーとして拒否します。

APIディレクトリと接続先アドレスはTask変数で上書きできます。

```sh
task smoke API_DIR=api SMOKE_API_ADDR=127.0.0.1 SMOKE_API_PORT=18081
```

成功時の期待値は以下です（レスポンスボディはJSONです）。

```sh
curl -fsS http://127.0.0.1:18080/healthz
# {"status":"ok"}
curl -fsS http://127.0.0.1:18080/readyz
# {"status":"ready"}
```

スモークテストは開始時にComposeの`db`がrunningかを確認します。開始前からrunningだった
既存DBは、成功・失敗・入力検証エラーのいずれでも停止せず保持します。開始時に停止していた
DBは停止状態へ戻し、存在しなかったDBコンテナは終了時に停止・削除します。いずれの場合も
`docker compose down -v`は実行せず、DBボリュームは保持されます。DBを完全に初期化する操作は
意図的に別ターゲットです。同じComposeプロジェクトに対する`task smoke`の並行実行は
サポートしません。

```sh
task db:reset CONFIRM_DB_RESET=1
```

`CONFIRM_DB_RESET=1`なしの`task db:reset`は拒否されます。ボリューム削除前に、ローカルに
必要なデータが残っていないことを確認してください。

## OpenAPI・Go・Dart生成コードの更新

OpenAPI定義（`openapi/openapi.yaml`）を変更した場合は、生成物を手作業で編集せず、
次の順番で更新します。生成コマンドは固定されたコンテナまたはGoモジュールの
バージョンを使用します。

### Goサーバコード

```sh
task api:generate
task api:test
task api:vet
task api:generate-check
```

主な生成先は`api/internal/openapi/openapi.gen.go`です。`task api:generate-check`は一時出力と
コミット済み生成物を比較します。生成物のコメントにあるとおり、生成されたGoコードは
直接編集しません。

### Dart APIクライアント

```sh
task dart:generate
task dart:pub-get
task dart:build
task dart:generate-check
task dart:build-check
```

OpenAPI Generatorの出力は`mobile/packages/api_client/`、`build_runner`の出力は
同ディレクトリの`*.g.dart`です。`generator_post_process.sh`は生成後の正規化に使われる
ため、出力の手修正で差分を隠さず、必要な正規化がある場合はスクリプトや生成設定を
変更して再生成します。生成物、生成Markdown、`*.g.dart`を手で編集してはいけません。

更新後は必ず次を実行してください。

```sh
task dart:verify
task api:verify
task flutter:verify
```

## 停止と再開

- Flutterは実行中のターミナルで`q`、または`Ctrl-C`で停止します。
- Go APIは`Ctrl-C`で停止します。別ターミナルで起動したAPIを残したままにしないでください。
- DBコンテナは`task db:down`で停止します。この操作はボリュームを保持します。
- 再開時は`task db:up`を実行し、必要なら`task db:migrate`を実行します。
- `task smoke`は成功・失敗のどちらでも一時APIを後片付けします。開始前からrunningだったDBは保持し、停止していたDBは停止状態へ戻し、存在しなかったDBコンテナは停止・削除します。

## トラブルシューティング

### `readyz`が503になる

`readyz`はPostGISへの問い合わせまで確認します。まずDBを起動してマイグレーションを
適用します。

```sh
task db:up
task db:migrate
task db:verify
curl -i http://127.0.0.1:8080/readyz
```

DBポートを変更した場合は、APIの`DATABASE_URL`も同じポートに変更してください。
DBコンテナのログは`docker compose logs db`で確認できます。

### AndroidからAPIに接続できない

- エミュレータは`http://10.0.2.2:8080`、実機は`http://<MacのLAN IP>:8080`を指定します。
- Android側の`localhost`はMacを指しません。
- 実機ではMacと端末が同じLANにいるか、MacのファイアウォールがAPIポートを許可しているかを確認します。
- APIが`127.0.0.1:8080`だけにbindしている場合、実機から届きません。実機確認時は`API_ADDR=0.0.0.0:8080`など、到達可能なアドレスにbindします。
- `curl http://127.0.0.1:8080/healthz`をMac上で実行し、API自体が起動していることを先に確認します。

### Android SDKまたはエミュレータが見つからない

Android StudioのSDK ManagerでSDK Platform-ToolsとAndroid Emulatorをインストールし、
AVDを作成して起動します。`fvm flutter doctor -v`で不足しているSDKパスやライセンスを
確認してください。SDKがない環境ではFlutterのanalyze/testは実行できても、APKビルドや
端末起動は検証できません。

### Docker、ポート、またはApple Siliconの問題

- Docker Desktopを起動し、`docker info`と`docker compose version`が成功することを確認します。
- DBの`5432`、通常APIの`8080`、スモークテストの`18080`が他のプロセスに占有されていないか確認します。DBポートは`DB_PORT=15432 task db:up`のように変更できますが、APIの`DATABASE_URL`も合わせて変更します。
- ComposeのPostGISイメージは`linux/amd64`に固定されています。Apple SiliconではDockerのamd64エミュレーションが動作するため、初回起動やマイグレーションが遅くなることがあります。Docker Desktopのリソース不足やエミュレーションの警告は失敗とは限りません。
- `task smoke`が既存APIポートを検出した場合は、残っているAPIを停止するか`SMOKE_API_PORT`を未使用ポートに変更します。既存プロセスのレスポンスをスモーク成功とは扱いません。

### 生成ドリフトが検出される

OpenAPIの変更後にGo/Dart生成を更新していない、または generator/Dart SDKのバージョンが
異なる可能性があります。`task api:generate`と`task dart:generate`、
`task dart:build`を実行し、差分をレビューしてから再度`task verify`を実行します。
生成ファイルを手で変更してチェックを回避しないでください。

### `.env`や秘密が差分に出た

秘密を削除してからコミット履歴と作業ツリーを確認し、漏えいした資格情報はローテーション
します。`.env.example`にはローカル開発に必要なプレースホルダーだけを置き、実際の秘密を
追記してコミットしないでください。

## Issue #4 の再実行チェックリスト

別メンバーがクリーンなcloneで、次の順に実行結果を記録してください。通常検証と端末確認を
混ぜず、端末不要の失敗か環境依存の失敗かを区別します。

### 端末不要のチェック

- [ ] Go `1.24.6`、FVM管理Flutter `3.47.0`、Docker、Task `3.53.1`、curlを確認した。
- [ ] `cp .env.example .env`を実行し、秘密をcommitしていない。
- [ ] `task db:up`がhealthyになった。
- [ ] `task db:migrate`が成功した。
- [ ] `task db:verify`がPostGISのバージョンを表示した。
- [ ] `task openapi:validate`と`task openapi:lint`が成功した。
- [ ] `task api:verify`が成功し、Go生成物にドリフトがない。
- [ ] `task dart:verify`が成功し、Dart生成物にドリフトがない（必要なら`DART_MODE=host`を使用）。
- [ ] `task flutter:verify`が成功した。
- [ ] `task verify`が成功した（Android端末不要）。
- [ ] `task smoke`が`{"status":"ok"}`と`{"status":"ready"}`を確認し、APIを停止した。開始時にDBが停止していた場合はDBも停止し、開始前からrunningだったDBは保持された。
- [ ] `task db:down`後もボリュームが保持されることを確認した。削除が必要な場合だけ`CONFIRM_DB_RESET=1`を指定した。

### Android手動チェック

- [ ] Android Emulatorを起動し、`task api:run`と`task flutter:run API_BASE_URL=http://10.0.2.2:8080`を実行した。
- [ ] アプリに`API is healthy`と`The health check returned OK.`が表示された。
- [ ] Mac上の`curl`で`/healthz`が200、`{"status":"ok"}`になることを確認した。
- [ ] Mac上の`curl`でDB起動中の`/readyz`が200、`{"status":"ready"}`になることを確認した。
- [ ] （任意）実機でMacのLAN IPを`API_BASE_URL`に指定し、同じLANとファイアウォール設定で疎通した。
- [ ] 確認後にFlutter、Go API、DBを停止した。
- [ ] `flutter build apk`はAndroid SDKがないため未検証であることを記録した（この環境の既知の制約）。
