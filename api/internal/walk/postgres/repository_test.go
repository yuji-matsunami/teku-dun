package postgres

import "testing"

func TestNewRepositoryRejectsNilPool(t *testing.T) {
	t.Parallel()

	defer func() {
		got := recover()
		if got != "postgres: pool must not be nil" {
			t.Errorf("NewRepository(nil) panic = %v, want postgres: pool must not be nil", got)
		}
	}()

	NewRepository(nil)
}
