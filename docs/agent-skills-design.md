# PR #24: リポジトリローカル skill 詳細設計

## 目的と設計境界

`docs/development.md` に集まっている開発操作を、エージェントが自然言語から再現性のある
コマンドへ変換できる形にする。実行手順は Taskfile と小さな専用スクリプトへ置き、skill は
意図の判定、入力の選択、結果の解釈を担当する。

追加する repo-local skill は次の3つとする。

| skill | 担当する意図 | 担当しないこと |
| --- | --- | --- |
| `setup-teku-dun-development` | 環境診断、依存取得、ローカルDBの準備、通常起動 | 契約更新、変更のコミット |
| `update-teku-dun-openapi-contract` | OpenAPI検証、Go/Dart生成物の更新、更新結果の検証 | 契約内容の設計、生成物の手編集 |
| `verify-teku-dun-changes` | 変更内容に応じた検証profileの選択と実行 | 失敗した実装の修正、生成物更新 |

ブランチ、コミット、push、PRは既存の `manage-git-workflow` skill に残す。3 skill から自動で
コミットやpushを行わない。`docs/development.md` は人間向けの前提、代表コマンド、各skillへの
導線だけを持つ薄い入口にし、重複した長いチェックリストは持たせない。

総合runner、独自manifest、JSON Schema、状態管理ファイルは追加しない。標準の Task 実行ログ、
各step名、終了コード、差分を観測可能な契約とする。skill 自身にも汎用シェル実装を埋め込まず、
既存Taskを優先して呼び出す。

## 現状の実行面

以下はすでに存在するコマンドである。

| 領域 | 既存入口 | 現在の挙動 |
| --- | --- | --- |
| DB | `task db:up`, `db:migrate`, `db:verify`, `db:down` | `db:down` は `docker compose down` でCompose全体を停止する。volumeは保持する |
| DB破棄 | `task db:reset CONFIRM_DB_RESET=1` | 明示変数がない場合はTaskが拒否し、指定時はvolumeを削除する |
| OpenAPI | `task openapi:validate`, `openapi:lint` | digest固定コンテナで検証する |
| Go生成 | `task api:generate`, `api:generate-check` | 更新は作業ツリーへ出力し、checkは一時生成との差分を見る |
| Dart生成 | `task dart:generate`, `dart:build` | OpenAPI Generator出力と`*.g.dart`を作業ツリーへ書く |
| Dart検証 | `task dart:generate-check`, `dart:build-check` | 前者は隔離生成、後者は作業ツリーでbuild後にGit差分を見る |
| Flutter | `task flutter:verify`, `flutter:run` | 既定は`fvm flutter`。`run`だけ既定の`API_BASE_URL`を注入する |
| 全体 | `task verify`, `task smoke` | 順次fail-fast。`smoke`はDB/APIの起動を伴う |

`task dart:build-check` は `build_runner` 実行後の `git diff -- '*.g.dart'` と未追跡ファイルを
検査する。そのため、契約更新で正当に再生成した未ステージの `*.g.dart` も失敗になる。
自動 `git add` で基準を変えるとユーザーのステージ状態を改変するため、この回避は禁止する。

`AppConfig.fromEnvironment()` は `API_BASE_URL` が空または不正なら
`AppConfigurationException` を投げる。APKを生成できても、接続先を含む実行時動作が成功した
ことにはならない。Androidのbuild検証と端末上のruntime検証は別profileにする。

`scripts/smoke.sh` は自分が起動したAPI PIDだけを停止し、DBコンテナを開始前のrunning/stopped/
nonexistent状態へ戻す。既存running DBは残す。ただし適用済みmigrationとmigrationが変更した
DBデータは巻き戻さない。cleanupはプロセス・コンテナ状態の復元であり、DB内容のtransactionalな
復元ではない。

## 配置とskillの共通形

次の最小構成で実装する。

```text
.agents/skills/
├── setup-teku-dun-development/SKILL.md
├── update-teku-dun-openapi-contract/SKILL.md
└── verify-teku-dun-changes/SKILL.md
```

各 `SKILL.md` のfrontmatterは名前と識別力のあるdescriptionだけを必須とする。独自scriptや
referenceは、後述のTaskfile側だけでは表せない具体的な反復処理が判明した場合に限り追加する。
skillはリポジトリルートを `git rev-parse --show-toplevel` で確定し、期待する
`Taskfile.yml`、`api/go.mod`、`mobile/app/.fvmrc` の存在を確認してから実行する。別repoで同名の
一般的な依頼に反応しないdescriptionにする。

共通の終了契約は次のとおり。

- 最上位Taskは全step成功時0、入力不正・前提不足・検証失敗・cleanup失敗時は非0を返す。
- Taskが子Taskやスクリプトを順番にラップし、最初の非0で後続stepを実行しない。Taskによる
  wrapper後も子プロセスの終了コード値そのものが保持される、という保証には依存しない。
- skillは最上位の0/nonzeroと失敗したstepを解釈し、再実行コマンド、残った副作用を報告する。
- 複数stepを成功扱いにするための `|| true` はcleanupの既知の不存在などに限定する。
- 生成・setup後に失敗しても、skillは作業ツリー、DBデータ、cacheを自動で巻き戻さない。

ログは `==> <step>` 程度の固定prefixをTaskまたは専用スクリプトから出す。machine-readableな
reportファイルは作らず、診断に必要な実コマンドのstderr/stdoutを保持する。

## `setup-teku-dun-development`

### 呼び出しと入力

「開発環境を確認して」は `check`、「初期設定して」「依存を揃えて」は `setup`、「アプリを
起動して」「端末へ接続して」は `run` と解釈する。環境profileは `core`（既定）または
`android` とする。skill内部の正規入口候補は次のとおり。

```sh
# 実装済みの固定入口
task dev:check PROFILE=core
task dev:check PROFILE=android
task dev:accept-android-licenses CONFIRM_ANDROID_LICENSES=1
task dev:setup PROFILE=core
task dev:setup PROFILE=android
task dev:run TARGET=emulator DEVICE_ID=<DEVICE_ID> API_BASE_URL=http://10.0.2.2:8080
```

`PROFILE` はTask側でenum検証し、未指定は `core`、未知値はサービス起動や依存取得より前に
非0で終了する。Agent経由ではFlutterコマンドを `fvm flutter` に固定する。既存Taskの
`FLUTTER=<command string>` overrideは人間向け互換性として当面残すが、skill入力として任意の
command stringを受け取らない。

### `check` の前提・終了条件・副作用

`core` は Task、Docker Engine、Compose CLI v2以降（`up --wait`対応）、curl、FVM、Flutter、Go toolchainを確認する。
期待versionの一次仕様は `api/go.mod`、`mobile/app/.fvmrc`、Taskfile内の固定値から読む。
本設計時の実測値はTask 3.53.1以上、Flutter 3.47.0、`api/` で有効なGo 1.24.6だが、skillへ
重複して固定せず、一次仕様が更新されたらそちらに従う。バージョン文字列だけでなく
`docker info` と固定イメージを使う後続処理の前提も確認する。`android` はcoreに加え、
`fvm flutter doctor -v` のAndroid toolchainと、接続済み端末または起動可能なemulatorを診断する。

Android CLIのversion差を吸収するため、license判定は `flutter doctor` の表示だけに依存しない。
未承諾licenseを検出した場合は固定markerを返し、skillがユーザーへ同意を確認する。ユーザーが
明示的に同意した後だけ `task dev:accept-android-licenses CONFIRM_ANDROID_LICENSES=1` を実行し、
表示されたlicenseを承諾してから `dev:check` を再実行する。確認前の実行や無条件の自動承諾はしない。
新しいAndroid CLIが `--licenses` は不要と正常終了した場合は、未承諾として扱わない。

Goのeffective toolchain確認は `api/` で `go version` を実行する。Goのtoolchain自動取得や
FVM/FlutterのSDK解決は、read-onlyに見える診断でも不足SDKをdownloadし得る。実行前に
その可能性をstepログへ出し、完全な無副作用チェックとは表現しない。診断はDBやemulatorを
起動せず、パッケージ依存も更新しない。`check` は必要SDKが未導入なら項目名と期待値を示して
非0にする。一方、`setup` では未導入のFVM管理Flutter SDKは取得対象なので、取得可能である限り
事前の失敗条件にしない。Docker daemon停止やFVM自体の不存在など、setupが解消しない前提だけを
副作用発生前に拒否する。

### `setup` の処理と副作用

`setup core` は `check` の構造確認後、FVMの固定SDK取得、既存 `task flutter:pub-get`、
`task dart:pub-get`、`task db:up`、`task db:migrate`、`task db:verify` を順次実行する。
`setup android` はcoreに加えAndroid toolchain診断まで行うが、AVDの新規作成やGUI操作は行わない。
license承諾が必要なら上記の明示確認を先に完了する。setup成功は依存取得とPostGIS検証までであり、
アプリ疎通成功を意味しない。

副作用はSDK・module/package cacheのdownload、`.dart_tool`等のローカル生成、DBコンテナ起動、
migration適用である。失敗時も取得済みcacheとmigration済みデータは残る。開始前にDBが停止して
いた場合もsetup成功後はrunningのままにし、明示的な `task db:down` によって停止する。

### `run` の入力、起動、cleanup

`run` はセットアップ済み環境で通常の開発セッションを開始する。runtimeを検証対象として
合否判定する依頼は `verify-teku-dun-changes` が `android-runtime` を選ぶ。入力は
`TARGET=emulator|device`、Flutterが列挙する具体的な `DEVICE_ID`、`API_BASE_URL` とする。
`DEVICE_ID` は常に必須で、曖昧な「最初の端末」を選ばない。`dev:run` の入力はこの3つに限定する。
emulatorが未起動の場合、Agentはその前段の候補選択で `EMULATOR_ID` を取得する。

正規コマンドは次のとおり。端末候補の取得とAVD選択はAgentが行い、開発セッションの
lifecycleは `scripts/dev-session.sh` を呼ぶ `task dev:run` に固定する。

```sh
# 端末・emulator候補を取得（既存ツールの直接利用）
cd mobile/app && fvm flutter devices --machine
cd mobile/app && fvm flutter emulators

# emulatorを選んだ場合のみ、必要なら起動（既存ツールの直接利用）
cd mobile/app && fvm flutter emulators --launch <EMULATOR_ID>

# 起動した端末がdevicesへ現れた後にセッション開始
task dev:run TARGET=emulator DEVICE_ID=<DEVICE_ID> API_BASE_URL=http://10.0.2.2:8080
task dev:run TARGET=device DEVICE_ID=<DEVICE_ID> API_BASE_URL=http://<MacのLAN IP>:8080
```

emulatorが未起動なら、Agentは `flutter emulators` で既存AVDを選び、launchし、
`flutter devices --machine` に現れるまで待つ。その後に具体的な `DEVICE_ID` を渡す。物理端末も
接続済みで同じ一覧に現れていることを前提とする。`dev-session.sh` は起動直前に一覧を再取得し、
指定IDが一意に存在することをコードで検証してからDBやAPIを起動する。

`dev-session.sh` は `TARGET` のenum、改行等を含まない `DEVICE_ID`、AppConfigと同じ制約の
`API_BASE_URL`を副作用発生前に検証する。emulatorではhostを `10.0.2.2`、実機では開発Macの
local interface addressに限定する。schemeはローカルAPIが提供する `http`、portは初期版では
`8080` に固定し、起動するAPIと一致させる。初期対象はこのスクリプトが起動する
ローカルAPIへの接続だけとし、remote API URLは拒否する。任意command stringは受け取らず、Flutterは
`fvm flutter run -d "$DEVICE_ID" --dart-define=API_BASE_URL="$API_BASE_URL"` に固定する。既存の
`task flutter:run` と `FLUTTER` overrideは人間向け互換入口として残すが、Agentのrun経路には使わない。

スクリプトは起動前のDB状態をrunning/stopped/nonexistentで記録し、起動予定のローカルAPI portに
既存listenerがあれば開始前に拒否する。`task db:up`、`task db:migrate`、Go APIのbuild/start、healthz/readyzの
timeout付き起動待ち、指定端末へのFlutter起動を順次fail-fastで行う。API起動待ちは30秒、
HTTP要求は接続1秒・全体2秒とし、DB起動待ちは既存Compose healthcheck設定を使う。
Flutterの対話実行時間には制限を設けず、起動待ちと対話セッションを区別する。
初期実装ではAgentによる候補取得とAVD launch以外のlifecycleをこの
スクリプトへコード化し、永続状態ファイルや汎用runner frameworkは作らない。

スクリプトは自分が起動したAPI/FlutterのPIDだけを所有する。正常停止、失敗、INT、TERMでtrapを
実行し、所有プロセスを停止してからDBを開始前のcontainer状態へ戻す。開始前runningなら維持、
stoppedならstop、nonexistentならdb containerだけをstop/removeし、volumeを削除しない。
migrationデータは戻らない。既存プロセスや他serviceを巻き込む `task db:down` をcleanupに使わない。
cleanup失敗は、元処理が成功していた場合も最上位Taskを非0にする。画面上のhealth表示を機械的に
取得できない場合、Agentがスクリプトログとユーザーが確認した表示からruntimeの成否を判断する。

## `update-teku-dun-openapi-contract`

### 呼び出し、前提、処理順

入力は契約ファイルの変更内容であり、生成先やgenerator imageを自由入力にしない。対象は固定の
`openapi/openapi.yaml`、Go出力、Dart client出力とする。ユーザーが契約内容をまだ決めていない
場合は先に設計判断を確認し、決まっている場合は余分な確認なしで更新する。

正規入口候補は、複数の既存コマンド表記をskillが毎回組み立てないための薄いTaskである。

```sh
# 実装済みの固定入口（内部では既存Taskを順番に呼ぶ）
task contract:update
task contract:verify
```

`contract:update` は次の順でfail-fastに実行する。

1. `task openapi:validate` と `task openapi:lint`
2. `task api:generate`
3. `task dart:generate`
4. `task dart:build`（lockfileは更新せず、enforce済み依存から`*.g.dart`を生成）

ここでupdateは成功とし、変更された型やinterfaceに合わせてAgentが手書きのGo
`ServerInterface`実装、Flutter呼び出し側、テストを修正する。生成直後にfull verifyを強制すると、
この追従修正より前に必然的にcompile/testが失敗するためである。手書き修正後に
`task contract:verify` を実行する。これは既存 `task verify` への薄いaliasとし、OpenAPI
validate/lintを含むfull検証を1回行う。updateの末尾で同じ検証を重複実行しない。

### Dartドリフト検査

`dart:build-check` はclientの生成入力だけを安全な一時ディレクトリへ複製し、固定Dart
imageで `pub get --enforce-lockfile` と `build_runner build` を実行して、生成された `*.g.dart`
集合を作業ツリーと比較する。複製時は既存の全 `*.g.dart`、`.dart_tool/`、`build/`
およびbuild cacheを除外し、必ずfreshな空の生成物集合から開始する。既存の余分な `*.g.dart` を
一時側へ自己コピーして差分を隠してはならない。一時ディレクトリはrepo外で `mktemp -d` し、
実体pathとprefixを検証した場合だけtrapで削除する。既存 `dart:generate-check` と同じ安全条件を
適用する。

比較対象は相対path、ファイル内容、片側だけに存在する `*.g.dart` とする。作業ツリーで直接
buildしてからGit差分を見る方式は使わない。これにより、未ステージの正当な再生成を許容し、
古い・欠落・余分な生成物だけを失敗にできる。Git indexを変更せず、自動stageもしない。

`dart:verify` は `generate-check`、freshな `build-check`、ロック済み依存取得、
`analyze-only`、`test-only` の順に実行する。生成を内包する既存 `analyze` / `test` は呼ばない。
verifyは観測だけを行い、更新が必要なら `contract:update` へ戻す。

### 終了条件と副作用

`update` の成功条件は、契約がvalidate/lintを通り、Go/Dart生成コマンドが全て0で終了することと
する。この時点では手書きコードのcompile/test成功を要求しない。追従修正後の `contract:verify`
では、生成物が現在の契約から再現され、対象テストと解析が全て0で終わることを成功条件とする。
skillは各段階の最後に `git diff --stat` と対象pathの `git status --short` を読み取り、レビュー対象を
列挙する。差分があること自体はupdateの失敗ではない。

生成器は既存ファイルを上書き・削除し得て、途中失敗では部分的な差分が残る。cacheや一時的な
`.dart_tool`も作られる。skillは生成物を手編集せず、失敗時にGit操作で復元しない。依存定義を
意図的に変更した場合だけ、別判断で既存 `task dart:lock-update` を実行する。

## `verify-teku-dun-changes`

### profileインターフェース

自然言語を次の固定profileへ写像する。小さな変更では変更componentの既存Taskを使う。複数profile
が必要なら安全な順に個別実行し、巨大な新規runnerへ統合しない。

| profile | 選択条件 | 正規入口 | 前提・成功条件 |
| --- | --- | --- | --- |
| `component` | 変更中の対象別確認 | 既存 `task api:verify`, `dart:verify`, `flutter:verify` | 変更したcomponentのTaskが0。OpenAPI単体は既存validate/lint |
| `full` | PR前、生成・契約を含む変更、指定なしの「全部検証」 | 既存 `task verify` | 既存全検証に修正後の隔離Dartドリフト検査を含み、全stepが0 |
| `smoke` | DB/API結合確認 | 既存 `task smoke` | healthz/readyzの厳密なJSON応答が得られ、cleanupも成功 |
| `android-build` | debug APK生成可否 | 新規 `task flutter:build-android` | URL注入済みdebug APK buildが0で成果物pathを表示 |
| `android-runtime` | emulator/実機の疎通 | setup skillの `task dev:run` を実行・監督 | 指定端末上でhealth表示を確認し、scriptが所有プロセスとDB状態をcleanup |

`component` は変更中のfeedback用であり、PR前の十分条件にしない。変更pathだけから検証を省略せず、
契約、生成設定、`mobile/packages/api_client` の変更では必ず `full` を選ぶ。DB/APIのruntime変更には
`full` に加えて `smoke`、Android build設定には `android-build`、端末固有の接続確認には
`android-runtime` を追加する。

`android-build` はAndroid SDK/ライセンスを前提とし、`fvm flutter build apk --debug` を使う。
`API_BASE_URL` 未指定時は `taskfiles/Flutter.yml` と同じ `http://10.0.2.2:8080` を
`--dart-define`で注入し、指定時は同じURL検証を行う。これは空設定のAPKを作らないためのbuild契約
であり、artifact生成はそのURLへ端末から接続できたruntime証拠ではない。
`android-runtime` は対象を `emulator` または `device` とし、前者の既定URLは
`http://10.0.2.2:8080`、後者は端末から到達可能な開発MacのLAN URLを指定する。具体的な
`DEVICE_ID` を必須とし、setup skillの `dev:run` と同じ取得、起動、URL検証、
状態所有権、cleanupを使う。remote URLは初期対象外とする。実機時はAPI bind先とfirewallも確認する。
APK build成功をruntime成功へ読み替えない。

`smoke` の入力は既存の `SMOKE_API_ADDR`、`SMOKE_API_PORT`、`SMOKE_API_TIMEOUT` に限定し、既存の
入力検証を再利用する。同一Compose projectで並行実行しない。cleanup後にDBのcontainer状態は
復元されてもmigrationデータは残ることを毎回の結果へ記載する。`db:down` はCompose全体へ作用する
ため、skillがsmoke後の個別cleanup代わりに呼ばない。

## `docs/development.md` の着地点

実装後の文書は、対応OS、構成、固定version、手動Android要件、代表的な開始コマンドを残す。
セットアップ、契約更新、検証の各節は「人間が直接使う正規Task」と「エージェントへ依頼する際の
skill名」を短く示す。詳細なstep順はTaskfile、判断規則は各 `SKILL.md` を正とし、Issue #4固有の
再実行チェックリストと重複トラブルシューティングは整理する。破壊的な `db:reset` と
`CONFIRM_DB_RESET=1`、smokeのDBデータ非巻き戻しは入口文書にも残す。

## 実装順と検証計画

次の順に実装した。

1. Dart `*.g.dart` の隔離生成比較を実装し、既存 `dart:verify` を直す。
2. `dev:*`、`contract:*`、`flutter:build-android` のTask入口、`scripts/dev-session.sh` と入力検証を足す。
3. 3つの `SKILL.md` を作り、既存/新規Taskへの写像、停止条件、副作用を記す。
4. `docs/development.md` を薄い入口へ更新する。

意味のあるテストは、文言や見出しの一致ではなく観測可能な契約を検証する。

- Dart検査: clean生成物で成功、内容変更・欠落・余分な`*.g.dart`で失敗、正当な未ステージ生成物で成功、Git index不変。
- 入力検証: 未知profile、不正URL、不正portを副作用発生前に拒否する。
- fail-fast: 中間stepを意図的に失敗させ、後続生成・サービス起動が行われない。
- 開発session: 不明なDEVICE_IDと既存listenerを開始前に拒否し、timeout/INT/TERMでも所有PIDとDB状態を復元する。
- smoke: DBがrunning/stopped/nonexistentの各開始状態でcontainer状態を復元し、migrationデータは残る。
- Android: SDKがある環境でAPK成果物を確認し、別にemulatorで`API_BASE_URL`注入後のhealth表示を確認する。
- skill: 現実的な依頼例で正しいprofile/Taskを選び、commit、DB reset、任意command実行へ範囲を広げない。

この文書は、Taskfile・スクリプト・3つのskillへ反映した実装仕様である。
