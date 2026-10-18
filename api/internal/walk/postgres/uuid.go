package postgres

import (
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

func parseUUID(value string) (pgtype.UUID, bool) {
	parsed, err := uuid.Parse(value)
	if err != nil || parsed == uuid.Nil || !strings.EqualFold(parsed.String(), value) {
		return pgtype.UUID{}, false
	}
	return pgtype.UUID{Bytes: [16]byte(parsed), Valid: true}, true
}

func sameUUID(left, right pgtype.UUID) bool {
	return left.Valid == right.Valid && left.Bytes == right.Bytes
}
