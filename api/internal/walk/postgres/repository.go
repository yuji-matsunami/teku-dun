// Package postgresは、PostgreSQLとPostGISを使ってwalk.WalkRepositoryを実装する。
package postgres

import (
	"context"
	"errors"
	"math"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk/postgres/sqlc"
)

// Repositoryは、散歩イベントをPostgreSQLに保存する。
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepositoryは、PostgreSQLを使用する散歩リポジトリを生成する。
func NewRepository(pool *pgxpool.Pool) *Repository {
	if pool == nil {
		panic("postgres: pool must not be nil")
	}
	return &Repository{pool: pool}
}

var _ walk.WalkRepository = (*Repository)(nil)

// PutSessionは、セッションを保存する。同じ内容の再送は成功として扱う。
func (r *Repository) PutSession(ctx context.Context, session walk.Session) error {
	id, ok := parseUUID(session.ID)
	if !ok || session.StartDatetime.IsZero() {
		return walk.ErrInvalid
	}
	start := canonicalTime(session.StartDatetime)
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	queries := sqlc.New(tx)
	if err := queries.InsertSession(ctx, sqlc.InsertSessionParams{ID: id, StartDatetime: timestamp(start)}); err != nil {
		return err
	}
	existing, err := queries.GetSessionForUpdate(ctx, id)
	if err != nil {
		return err
	}
	if !sameTimestamp(existing.StartDatetime, start) {
		return walk.ErrConflict
	}
	return tx.Commit(ctx)
}

// PutLocationは、位置情報を保存する。同じ内容の再送は成功として扱う。
func (r *Repository) PutLocation(ctx context.Context, location walk.Location) error {
	id, idOK := parseUUID(location.ID)
	sessionID, sessionOK := parseUUID(location.SessionID)
	if !idOK || !sessionOK || location.RecordedAt.IsZero() || !validCoordinate(location.Latitude, location.Longitude, location.AccuracyM) {
		return walk.ErrInvalid
	}
	recordedAt := canonicalTime(location.RecordedAt)
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	queries := sqlc.New(tx)
	session, err := queries.GetSessionForUpdate(ctx, sessionID)
	if errors.Is(err, pgx.ErrNoRows) {
		return walk.ErrNotFound
	}
	if err != nil {
		return err
	}
	sessionStart, ok := timeValue(session.StartDatetime)
	if !ok {
		return errors.New("stored session has an invalid start time")
	}
	if recordedAt.Before(sessionStart) {
		return walk.ErrInvalid
	}
	if err := queries.InsertLocation(ctx, sqlc.InsertLocationParams{
		ID:         id,
		SessionID:  sessionID,
		RecordedAt: timestamp(recordedAt),
		Longitude:  location.Longitude,
		Latitude:   location.Latitude,
		AccuracyM:  location.AccuracyM,
	}); err != nil {
		return err
	}
	existing, err := queries.GetLocationForUpdate(ctx, id)
	if err != nil {
		return err
	}
	if !sameLocation(existing, id, sessionID, recordedAt, location) {
		return walk.ErrConflict
	}
	return tx.Commit(ctx)
}

// PutStepsは、固定区間の歩数を保存し、より新しいリビジョンで更新する。
func (r *Repository) PutSteps(ctx context.Context, steps walk.Steps) error {
	id, idOK := parseUUID(steps.ID)
	sessionID, sessionOK := parseUUID(steps.SessionID)
	if !idOK || !sessionOK || steps.StartDatetime.IsZero() || steps.EndDatetime.IsZero() || steps.Steps < 0 || steps.Revision < 1 {
		return walk.ErrInvalid
	}
	start := canonicalTime(steps.StartDatetime)
	end := canonicalTime(steps.EndDatetime)
	if end.Sub(start) <= 0 || end.Sub(start) > time.Minute {
		return walk.ErrInvalid
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	queries := sqlc.New(tx)
	session, err := queries.GetSessionForUpdate(ctx, sessionID)
	if errors.Is(err, pgx.ErrNoRows) {
		return walk.ErrNotFound
	}
	if err != nil {
		return err
	}
	sessionStart, ok := timeValue(session.StartDatetime)
	if !ok {
		return errors.New("stored session has an invalid start time")
	}
	if start.Before(sessionStart) || !wholeMinutesFrom(sessionStart, start) {
		return walk.ErrInvalid
	}

	existing, err := queries.GetStepsByIntervalForUpdate(ctx, sqlc.GetStepsByIntervalForUpdateParams{
		SessionID:     sessionID,
		StartDatetime: timestamp(start),
	})
	if err == nil {
		if !sameUUID(existing.ID, id) || !sameTimestamp(existing.EndDatetime, end) {
			return walk.ErrConflict
		}
		if steps.Revision < existing.Revision {
			return tx.Commit(ctx)
		}
		if steps.Revision == existing.Revision {
			if steps.Steps != existing.Steps {
				return walk.ErrConflict
			}
			return tx.Commit(ctx)
		}
		if err := queries.UpdateSteps(ctx, sqlc.UpdateStepsParams{ID: id, Steps: steps.Steps, Revision: steps.Revision}); err != nil {
			return err
		}
		return tx.Commit(ctx)
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	// UUIDを別の区間へ移すことはできない。
	// 挿入前に確認し、制約違反をドメイン上の競合として返す。
	byID, err := queries.GetStepsByIDForUpdate(ctx, id)
	if err == nil {
		if !sameUUID(byID.SessionID, sessionID) || !sameTimestamp(byID.StartDatetime, start) || !sameTimestamp(byID.EndDatetime, end) {
			return walk.ErrConflict
		}
		return walk.ErrConflict
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	rows, err := queries.InsertSteps(ctx, sqlc.InsertStepsParams{
		ID:            id,
		SessionID:     sessionID,
		StartDatetime: timestamp(start),
		EndDatetime:   timestamp(end),
		Steps:         steps.Steps,
		Revision:      steps.Revision,
	})
	if err != nil {
		return err
	}
	if rows != 1 {
		return walk.ErrConflict
	}
	return tx.Commit(ctx)
}

func sameLocation(existing sqlc.GetLocationForUpdateRow, id, sessionID pgtype.UUID, recordedAt time.Time, location walk.Location) bool {
	return sameUUID(existing.ID, id) && sameUUID(existing.SessionID, sessionID) &&
		sameTimestamp(existing.RecordedAt, recordedAt) && existing.Latitude == location.Latitude &&
		existing.Longitude == location.Longitude && existing.AccuracyM == location.AccuracyM
}

func canonicalTime(value time.Time) time.Time {
	return value.UTC().Truncate(time.Microsecond)
}

func timestamp(value time.Time) pgtype.Timestamptz {
	return pgtype.Timestamptz{Time: value, Valid: true}
}

func timeValue(value pgtype.Timestamptz) (time.Time, bool) {
	return value.Time, value.Valid
}

func sameTimestamp(stored pgtype.Timestamptz, value time.Time) bool {
	return stored.Valid && stored.Time.Equal(value)
}

func wholeMinutesFrom(start, value time.Time) bool {
	// time.Durationは約290年を超えると上限値になるため、
	// RFC 3339が扱う年の範囲でも計算できるUnixMicroを使用する。
	delta := value.UnixMicro() - start.UnixMicro()
	return delta >= 0 && delta%time.Minute.Microseconds() == 0
}

func validCoordinate(latitude, longitude, accuracy float64) bool {
	return !math.IsNaN(latitude) && !math.IsInf(latitude, 0) && latitude >= -90 && latitude <= 90 &&
		!math.IsNaN(longitude) && !math.IsInf(longitude, 0) && longitude >= -180 && longitude <= 180 &&
		!math.IsNaN(accuracy) && !math.IsInf(accuracy, 0) && accuracy >= 0
}
