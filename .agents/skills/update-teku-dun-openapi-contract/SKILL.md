---
name: update-teku-dun-openapi-contract
description: teku-dun の openapi/openapi.yaml に決定済みの契約変更を反映し、Go API・Dart client の生成物を更新して検証するときに使う。契約の未決事項を設計したり生成コードを手編集したりする用途には使わない。
---

# teku-dun OpenAPI 契約の更新

## 対象と前提

リポジトリルートを `git rev-parse --show-toplevel` で確定し、`Taskfile.yml`、`api/go.mod`、`mobile/app/.fvmrc` を確認する。対象が teku-dun でない場合は停止する。扱う契約と生成先は `openapi/openapi.yaml`、Go API、Dart API client に限り、generatorや出力先を自由入力で変更しない。

契約の変更内容が依頼から確定できない場合は、必要な仕様判断だけをユーザーに確認する。意味が確定している場合は、作業ツリーの既存差分を確認してから反映する。Go側の層や依存関係を追従させるときは [Go APIアーキテクチャ](../../../docs/api-architecture.md) を正とする。

## 更新と追従

契約と生成物の更新には `task contract:update` を使う。このTaskが0で終わったことは契約検証と生成完了を示すが、手書きコードの追従や全体検証の成功までは示さない。生成コードを直接編集せず、生成された型や `ServerInterface` に合わせて必要なHTTP実装、Flutter呼び出し側、テストを更新する。契約変更に無関係な実装変更へ広げない。

追従変更が揃ったら `task contract:verify` を実行する。更新段階で失敗した場合はそれ以上のTaskを実行せず、失敗stepと残った差分を報告する。verifyで契約変更と無関係な既存失敗が出た場合も停止し、ログと失敗Taskを示す。

## 副作用と停止条件

生成Taskは既存ファイルを上書き・削除し、途中失敗でも作業ツリーに部分的な差分を残すことがある。cacheや `.dart_tool` も作られ得る。失敗しても `git` による復元、stage、commitを自動で行わない。依存定義を意図して変更した場合以外はlockfile更新を追加しない。

ブランチ・commit・push・PRの操作はこのskillの範囲外であり、依頼された場合は [manage-git-workflow](../manage-git-workflow/SKILL.md) の手順へ移る。

## 結果を報告する

実行した固定Task、契約検証・生成・追従後verifyの各結果、失敗したstepを分けて伝える。`git diff --stat` と対象パスの `git status --short` を使ってOpenAPI・Go・Dartの差分を列挙する。生成差分がない場合もその結果を明記し、残っているcacheや部分生成物があれば報告する。
