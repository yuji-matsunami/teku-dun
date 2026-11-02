package postgres

import (
	"testing"

	"github.com/google/uuid"
)

func TestToPgUUID(t *testing.T) {
	t.Parallel()

	t.Run("変換成功", func(t *testing.T) {
		t.Parallel()

		value := "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
		got, ok := toPgUUID(value)
		wantBytes := [16]byte(uuid.MustParse(value))
		if !ok {
			t.Fatalf("toPgUUID(%q) ok = false, want true", value)
		}
		if !got.Valid || got.Bytes != wantBytes {
			t.Errorf("toPgUUID(%q) = %+v, want valid UUID %x", value, got, wantBytes)
		}
	})

	t.Run("解析不能", func(t *testing.T) {
		t.Parallel()

		value := "not-a-uuid"
		got, ok := toPgUUID(value)
		if ok || got.Valid {
			t.Errorf("toPgUUID(%q) = (%+v, %v), want invalid UUID and false", value, got, ok)
		}
	})
}
