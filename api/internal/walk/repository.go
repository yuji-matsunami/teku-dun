package walk

import "context"

// Repository persists walk events. Implementations must provide idempotency
// and conflict handling for each operation.
type Repository interface {
	PutSession(context.Context, Session) error
	PutLocation(context.Context, Location) error
	PutSteps(context.Context, Steps) error
}
