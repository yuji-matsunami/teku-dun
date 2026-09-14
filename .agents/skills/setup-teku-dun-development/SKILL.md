---
name: setup-teku-dun-development
description: この teku-dun リポジトリで、macOS 上の Go・PostGIS・Flutter 開発環境を診断または準備し、指定した Android emulator / device でアプリを通常起動するときに使う。OpenAPI 契約更新や変更の合否検証には使わない。
---

# teku-dun 開発環境の準備と起動

## 対象と判断

まずリポジトリルートを `git rev-parse --show-toplevel` で確認し、`Taskfile.yml`、`api/go.mod`、`mobile/app/.fvmrc` があることを確かめる。どれかが見つからない場合は実行せず、対象リポジトリを報告する。

依頼を次のどれかに分ける。

- 開発環境の診断: `task dev:check PROFILE=core`。Android SDKや端末環境も確認する依頼なら `PROFILE=android`。
- 初期準備・依存取得: `task dev:setup PROFILE=core`。Android環境も診断する依頼なら `PROFILE=android`。
- 通常のアプリ起動: 下記の端末選択を済ませてから `task dev:run`。
- 実行時の疎通を検証して合否を出す依頼: [verify-teku-dun-changes](../verify-teku-dun-changes/SKILL.md) の `android-runtime` を使う。

## 端末を選んで起動する

Android実機・emulatorを使う依頼では、`mobile/app` で `fvm flutter devices --machine` を実行し、emulatorが必要なら `fvm flutter emulators` で候補を確認する。候補が複数あり、依頼から対象を決められない場合はIDをユーザーに確認する。未起動emulatorは既存候補だけを起動し、AVDの作成やSDKライセンスへの代理同意はしない。起動後、対象がdevices一覧に現れたことを確認する。

一覧にある具体的な `DEVICE_ID` を必ず使い、「最初の端末」を推測しない。emulatorは `TARGET=emulator` と `API_BASE_URL=http://10.0.2.2:8080` を使う。実機は `TARGET=device` と、端末から到達できるMacのLAN IPを使う。remote URLはこのローカル開発セッションの対象外とする。

起動には固定入口を使う。

```sh
task dev:run TARGET=emulator DEVICE_ID=<DEVICE_ID> API_BASE_URL=http://10.0.2.2:8080
task dev:run TARGET=device DEVICE_ID=<DEVICE_ID> API_BASE_URL=http://<MacのLAN IP>:8080
```

## 停止条件と副作用

Taskの前提条件やprofileの検証に失敗したら、下位コマンドへ切り替えず停止する。不足しているツールや確認が必要な端末を示し、ユーザーが環境を整えた後に再開できるよう失敗したTaskとstepを報告する。SDK解決を伴う診断では不足SDKのdownloadが起きる場合がある。

setupはSDK・依存cacheやローカル生成物を作り、DBを起動してmigrationを適用する。成功後のDBはrunningのまま残り、失敗してもmigration済みデータや取得済みcacheは戻らない。DB停止が必要なら明示的に `task db:down` を案内する。`task db:reset CONFIRM_DB_RESET=1` はvolumeを削除するため、ユーザーが明示していない限り実行しない。

dev:runは自分が起動したAPI・FlutterとDBコンテナ状態を後片付けするが、適用済みmigrationやDBデータを巻き戻さない。Task失敗時も残った変更や状態をGit操作やDB resetで自動復元しない。

## 結果を報告する

実行したprofileまたはtarget、固定Task、成功/失敗と失敗stepを伝える。setupでは取得・生成されたcacheやDB状態を、runでは選んだ端末ID、接続先、画面で確認できたhealth表示、cleanup結果と残るmigrationデータを伝える。画面表示を確認できなければ起動成功を疎通成功と扱わない。
