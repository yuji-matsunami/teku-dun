# 開発手順

## 対象環境と構成

この手順の対象は macOS と Android emulator / Android 実機です。iOS、Windows、Linux は対象外です。
PostGIS は Docker Compose、Go API と Flutter アプリは Mac 上で実行します。

| コンポーネント | 場所 | 役割 |
| --- | --- | --- |
| PostGIS | `compose.yaml` の `db` | ローカルDB |
| Go API | `api/` | health check API |
| OpenAPI | `openapi/openapi.yaml` | Go API・Dart client の契約 |
| Dart API client | `mobile/packages/api_client/` | Flutter から使う型付きclient |
| Flutter app | `mobile/app/` | Androidでの接続確認 |

## 必要なツール

- Go 1.24.6（`api/go.mod` の toolchain）
- FVM と Flutter 3.47.0（`mobile/app/.fvmrc`）
- go-task 3.53.1 以上（最小版は [scripts/dev-check.sh](../scripts/dev-check.sh) で確認）
- Docker Desktop（Docker Engine と Compose CLI v2以降、`up --wait`対応）
- Android Studio、Android SDK、Android Emulator。Android SDKのライセンス承諾とAVD作成は人がAndroid Studioで行います。
- `curl`

環境診断・依存取得は `task dev:check PROFILE=core` と
`task dev:setup PROFILE=core` を使います。Android toolchainも診断する場合は
`PROFILE=android` を指定します。Agentには [setup skill](../.agents/skills/setup-teku-dun-development/SKILL.md)
を依頼できます。Android向けsetupもAVDの作成やlicenseの代理同意はしません。

## アプリの起動とAndroid手動確認

emulatorでは `http://10.0.2.2:8080` が開発MacのAPIを指します。Android実機ではMacと端末を
同じLANにつなぎ、MacのLAN IPを使います。アプリは接続先を含む `API_BASE_URL` の指定が必要です。

起動中端末の一覧に表示される具体的な `DEVICE_ID` を指定して、次のいずれかを実行します。

```sh
task dev:run TARGET=emulator DEVICE_ID=<DEVICE_ID> API_BASE_URL=http://10.0.2.2:8080
task dev:run TARGET=device DEVICE_ID=<DEVICE_ID> API_BASE_URL=http://<MacのLAN IP>:8080
```

実機ではAPIがLANから到達できるアドレスで待ち受け、MacのファイアウォールがTCP 8080を
許可している必要があります。アプリ画面に `API is healthy` と
`The health check returned OK.` が表示されたら `/healthz` への接続を確認できています。
APKのbuild成功だけでは端末上の接続確認になりません。setup・通常起動・実行時検証の使い分けは
[setup skill](../.agents/skills/setup-teku-dun-development/SKILL.md) と
[検証skill](../.agents/skills/verify-teku-dun-changes/SKILL.md) を参照してください。

PR #24ではFlutter 3.47.0とAndroid 16（API 36）ARM64のPixel 10 Emulatorを使い、
debug APKの生成、Go APIとの疎通、エラー表示、API復旧後の再試行を確認しています。
Android実機での動作は未検証です。

## 検証と契約更新

端末を使わない開発スクリプトと全コンポーネントの検証は `task verify`、DBとAPIを起動する統合スモークテストは
`task smoke` です。Android debug APKのbuild可否はAndroid SDKが使える環境で
`task flutter:build-android` を実行します。

OpenAPIを変更したら `task contract:update` で契約の検証とGo・Dart生成物の更新を行い、
生成物に合わせた手書き実装を直した後に `task contract:verify` を実行します。
Agentには [contract update skill](../.agents/skills/update-teku-dun-openapi-contract/SKILL.md)
を依頼できます。生成手順の詳細はTaskfileとskillを正とし、生成コードを直接編集しません。

## DBの状態と破壊的操作

`task dev:setup` と `task smoke` はDBを起動してmigrationを適用することがあります。
smoke終了後はDBコンテナの開始前状態へ戻りますが、migrationやDBデータの変更は巻き戻りません。
同じCompose projectでsmokeを並行実行しないでください。

`task db:down` はDB volumeを保持してコンテナを停止します。
`task db:reset CONFIRM_DB_RESET=1` はDB volumeを削除してデータを破棄する操作です。
必要なローカルデータがないことを確認し、明示的にresetを依頼された場合に限って使ってください。
