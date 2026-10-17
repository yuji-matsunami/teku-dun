package walk

import "context"

// WalkRepositoryは、散歩データを冪等に永続化する。
// 同一データの再送を許可し、同じIDが異なるデータに使用された場合はErrConflictを返す。
type WalkRepository interface {
	PutSession(context.Context, Session) error
	PutLocation(context.Context, Location) error
	PutSteps(context.Context, Steps) error
}
