package walk

import "context"

// WalkRepositoryは、散歩データを冪等に永続化する。
// 同一データの再送を許可し、同じIDが異なるデータに使用された場合はErrConflictを返す。
type WalkRepository interface {
	PutSession(context.Context, Session) error
	// GetSessionは、IDに対応するセッションを返す。未保存の場合はErrNotFoundを返す。
	GetSession(context.Context, string) (Session, error)
	PutLocation(context.Context, Location) error
	PutSteps(context.Context, Steps) error
}
