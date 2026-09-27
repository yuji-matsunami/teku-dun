package postgres

import (
	"encoding/hex"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"
)

func parseUUID(value string) (pgtype.UUID, bool) {
	if len(value) != 36 || value[8] != '-' || value[13] != '-' || value[18] != '-' || value[23] != '-' {
		return pgtype.UUID{}, false
	}
	compact := strings.ReplaceAll(value, "-", "")
	if len(compact) != 32 {
		return pgtype.UUID{}, false
	}
	decoded, err := hex.DecodeString(compact)
	if err != nil || len(decoded) != 16 {
		return pgtype.UUID{}, false
	}
	var result pgtype.UUID
	copy(result.Bytes[:], decoded)
	result.Valid = true
	if result.Bytes == [16]byte{} {
		return pgtype.UUID{}, false
	}
	return result, true
}

func sameUUID(left, right pgtype.UUID) bool {
	return left.Valid == right.Valid && left.Bytes == right.Bytes
}
