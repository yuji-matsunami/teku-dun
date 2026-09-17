---
name: verify-teku-dun-changes
description: teku-dun の変更内容に応じて component・full・smoke・Android build/runtime の検証Taskを選び、結果と残る副作用を報告するときに使う。実装修正や生成物更新が目的の依頼には使わない。
---

# teku-dun 変更の検証

## 変更とprofileを選ぶ

リポジトリルートを `git rev-parse --show-toplevel` で確認し、`Taskfile.yml`、`api/go.mod`、`mobile/app/.fvmrc` を確認する。対象外なら停止する。作業ツリーの既存差分を含めて対象を把握し、どのprofileを選ぶかを先に示す。

- `component`: 開発中のフィードバックには、変更した領域に対応する `task api:verify`、`task dart:verify`、`task flutter:verify` を使う。OpenAPI定義だけなら `task openapi:validate` と `task openapi:lint` を使う。component検証だけをPR前の十分な確認とは扱わない。
- `full`: PR前、全体検証の依頼、OpenAPI・生成設定・`mobile/packages/api_client` の変更には `task verify` を使う。
- `smoke`: DB/APIの起動を含む結合確認には `task smoke` を使う。必要な場合も入力は `SMOKE_API_ADDR`、`SMOKE_API_PORT`、`SMOKE_API_TIMEOUT` に限り、同じCompose projectで並行実行しない。
- `android-build`: APKのdebug build可否には `task flutter:build-android` を使う。Android SDK/ライセンスが使えない場合は開始せず未実行と報告する。成功はAPKの生成だけを示し、実機接続の証拠とは扱わない。
- `android-runtime`: emulatorまたは実機上の疎通確認には、指定した端末IDを使い、[setup-teku-dun-development](../setup-teku-dun-development/SKILL.md) と同じ `task dev:run TARGET=... DEVICE_ID=... API_BASE_URL=...` を使う。具体的な端末を特定できず、依頼からも選べない場合はユーザーに確認する。

契約・生成物の変更ではpathだけを理由に検証を狭めず `full` を選ぶ。DB/APIのruntime変更には `full` に加えて `smoke`、Android build設定には `android-build`、端末固有の接続変更には `android-runtime` を加える。該当するprofileは独立した固定Taskとして順に実行し、一つの失敗を隠さない。

## 停止条件と副作用

選んだTaskが失敗したら検証を止め、失敗stepとログを報告する。実装の修正や生成物の更新は行わず、生成ドリフトなら契約更新用skillへ案内する。stageやGitによる復元をせず、検証を通すために失敗を無視しない。

`verify` や各component Taskはローカルの依存cache・build出力を作ることがある。`smoke` はDBコンテナ状態を開始前に戻すが、適用したmigrationや変更されたDBデータは残す。cleanup目的で `task db:down` やDB resetを追加実行しない。`android-build` はAPK等のbuild出力を作り、`android-runtime` はsetup skillに記したAPI・Flutter・DB状態のcleanupとmigrationの制約に従う。

## 結果を報告する

選択したprofileと理由、実行Task、各Taskの成功/失敗と失敗stepを伝える。APKを作った場合はTaskが表示する成果物pathを記す。smokeではHTTP応答とcleanup結果、runtimeでは端末ID・API接続先・画面で確認できたhealth表示を記し、migrationデータが残ることも伝える。確認できないprofileは成功とせず、未実行として理由を分ける。
