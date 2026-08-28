# Go APIアーキテクチャ

## 目的

本書は、Go APIへ業務機能を追加するときのパッケージ構成と依存関係の方針をまとめる。

現時点では将来必要になる層やディレクトリを先に作らない。最初の業務APIからこの方針を適用し、実装を通じて必要性が確認できた単位で構成を拡張する。

## 基本方針

- 業務コードはミッション、インベントリなどの機能単位でまとめる。
- OpenAPI生成コードはHTTP境界に限定し、業務モデルとして使用しない。
- HTTPハンドラーには入出力の変換とHTTP固有の判断だけを置く。
- 業務ルールとユースケースは機能パッケージに置く。
- Repositoryのインターフェースは、それを利用する機能パッケージに置く。
- PostgreSQL実装も機能配下に置き、機能固有のコードを共通ディレクトリへ集めない。
- 依存関係は`cmd/api`で手動で組み立てる。

## 依存関係

依存関係は次の向きに限定する。

```text
OpenAPI定義
    ↓ コード生成
internal/openapi
    ↓
internal/httpapi
    ↓
internal/<feature>
    ↑ implements
internal/<feature>/postgres

cmd/apiは各実装を生成して接続する
```

業務パッケージはHTTP、OpenAPI、PostgreSQLの詳細に依存しない。PostgreSQL実装は業務パッケージが定義したRepositoryインターフェースを実装する。

## ディレクトリ構成

機能追加後は、次のような構成を基本とする。

```text
api/
├── cmd/api/
│   └── main.go
└── internal/
    ├── openapi/
    ├── httpapi/
    │   ├── handler.go
    │   ├── health.go
    │   ├── mission.go
    │   └── response.go
    ├── mission/
    │   ├── model.go
    │   ├── service.go
    │   ├── repository.go
    │   └── postgres/
    │       ├── repository.go
    │       └── queries.sql
    ├── inventory/
    │   ├── model.go
    │   ├── service.go
    │   ├── repository.go
    │   └── postgres/
    │       ├── repository.go
    │       └── queries.sql
    └── config/
```

この構成は完成形を示すものではない。空のパッケージは作らず、対応する機能を実装するときに追加する。

## 各パッケージの責務

### `internal/openapi`

- `oapi-codegen`で生成したHTTPの入出力型、ルーティング、インターフェースを置く。
- 生成物は直接編集しない。
- 業務ルールを置かない。

### `internal/httpapi`

- 生成された`ServerInterface`を実装する。
- OpenAPIの入出力型と業務パッケージの型を相互変換する。
- HTTPステータス、ヘッダー、エラーレスポンスを決定する。
- SQLの実行やゲームルールの判定を行わない。

生成される`ServerInterface`は1つだが、エンドポイントの実装は`mission.go`などの機能別ファイルへ分割する。

### `internal/<feature>`

- 業務モデル、ユースケース、ゲームルールを置く。
- 必要なRepositoryインターフェースを定義する。
- `net/http`、OpenAPI生成パッケージ、`pgx`、`sqlc`には依存しない。
- ユースケースとドメインは、分離する必要性が明確になるまで同じパッケージに置く。

### `internal/<feature>/postgres`

- 機能パッケージのRepositoryインターフェースを実装する。
- SQL、`pgx`、`sqlc`、PostGIS固有の処理を閉じ込める。
- DB固有の型を業務パッケージやHTTP層へ漏らさない。

接続プールやトランザクションなど、本当に複数機能で共有する処理が生じた場合だけ共通パッケージを検討する。それまでは`pgxpool.Pool`など必要な依存を各Repositoryへ直接渡す。

### `cmd/api`

- 設定を読み込む。
- DB接続を作成する。
- Repository、Service、HTTP Handlerを生成して接続する。
- サーバーの起動と終了を管理する。
- 業務ロジックを置かない。

DIフレームワークは使用せず、コンストラクタによる手動DIを続ける。組み立てが実際に複雑になった時点で再検討する。

## 型の境界

OpenAPI生成型は通信形式を表し、業務モデルとは分ける。

```text
openapi.StartMissionRequest
    ↓ HTTP層で変換
mission.StartInput
    ↓ 業務処理
mission.Result
    ↓ HTTP層で変換
openapi.StartMissionResponse
```

health checkのように業務ルールを持たない単純なレスポンスでは、HTTP層がOpenAPI生成型を直接使用してよい。

## テスト方針

- `internal/httpapi`ではServiceを偽物に差し替え、入出力変換、HTTPステータス、エラー変換を検証する。
- `internal/<feature>`ではRepositoryを偽物に差し替え、業務ルールを単体テストする。
- `internal/<feature>/postgres`では実際のPostgreSQL/PostGISを使ってSQLと型変換を検証する。
- `cmd/api`では依存関係の組み立て、起動、正常終了を最小限検証する。
- 主要な業務APIには、生成ルーターを通してパス、HTTPメソッド、パラメーターを確認するテストを設ける。
- OpenAPIの検証と生成差分検査を継続する。

## 現在のhealth check

現在の`healthz`と`readyz`は業務ロジックを持たないため、独立した機能パッケージを作らず`internal/httpapi`に実装する。DB疎通確認用の小さなインターフェースをHTTP層に置く現在の構成も維持する。

最初の業務APIを実装するときに本書の構成を適用し、過不足があれば実装と文書を同じPRで更新する。
