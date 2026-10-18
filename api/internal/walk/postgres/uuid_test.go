package postgres

import (
	"testing"

	"github.com/google/uuid"
)

func TestParseUUID(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name  string
		value string
		want  bool
	}{
		{name: "標準形式", value: "6ba7b810-9dad-11d1-80b4-00c04fd430c8", want: true},
		{name: "大文字の標準形式", value: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8", want: true},
		{name: "ハイフンなし", value: "6ba7b8109dad11d180b400c04fd430c8", want: false},
		{name: "URN形式", value: "urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8", want: false},
		{name: "波括弧付き", value: "{6ba7b810-9dad-11d1-80b4-00c04fd430c8}", want: false},
		{name: "nil UUID", value: "00000000-0000-0000-0000-000000000000", want: false},
		{name: "不正な文字", value: "6ba7b810-9dad-11d1-80b4-00c04fd430cg", want: false},
	}

	wantBytes := [16]byte(uuid.MustParse("6ba7b810-9dad-11d1-80b4-00c04fd430c8"))
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			got, ok := parseUUID(tt.value)
			if ok != tt.want {
				t.Fatalf("parseUUID(%q) ok = %v, want %v", tt.value, ok, tt.want)
			}
			if !tt.want {
				return
			}
			if !got.Valid || got.Bytes != wantBytes {
				t.Errorf("parseUUID(%q) = %+v, want valid UUID %x", tt.value, got, wantBytes)
			}
		})
	}
}
