package walk

import "context"

// Repositoryは、散歩イベントを永続化する。
// 実装は、各操作の冪等性と競合処理を保証する必要がある。
type Repository interface {
	PutSession(context.Context, Session) error
	PutLocation(context.Context, Location) error
	PutSteps(context.Context, Steps) error
}
