// Package postgresは、PostgreSQLとPostGISを使ってwalk.WalkRepositoryを実装する。
package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk/postgres/sqlc"
)

// Repositoryは、Serviceで入力検証と時刻のUTC・マイクロ秒正規化を済ませた散歩イベントをPostgreSQLに保存する。
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
	id, ok := toPgUUID(session.ID)
	if !ok {
		return walk.ErrInvalid
	}
	start := session.StartDatetime
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

// GetSessionは、セッションを取得する。保存されていない場合はErrNotFoundを返す。
func (r *Repository) GetSession(ctx context.Context, id string) (walk.Session, error) {
	pgID, ok := toPgUUID(id)
	if !ok {
		return walk.Session{}, walk.ErrInvalid
	}
	existing, err := sqlc.New(r.pool).GetSession(ctx, pgID)
	if errors.Is(err, pgx.ErrNoRows) {
		return walk.Session{}, walk.ErrNotFound
	}
	if err != nil {
		return walk.Session{}, err
	}
	start, ok := timeValue(existing.StartDatetime)
	if !ok {
		return walk.Session{}, errors.New("stored session has an invalid start time")
	}
	return walk.Session{ID: id, StartDatetime: start}, nil
}

// PutLocationは、位置情報を保存する。同じ内容の再送は成功として扱う。
func (r *Repository) PutLocation(ctx context.Context, location walk.Location) error {
	id, idOK := toPgUUID(location.ID)
	sessionID, sessionOK := toPgUUID(location.SessionID)
	if !idOK || !sessionOK {
		return walk.ErrInvalid
	}
	recordedAt := location.RecordedAt
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	queries := sqlc.New(tx)
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
	id, idOK := toPgUUID(steps.ID)
	sessionID, sessionOK := toPgUUID(steps.SessionID)
	if !idOK || !sessionOK {
		return walk.ErrInvalid
	}
	start := steps.StartDatetime
	end := steps.EndDatetime
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	queries := sqlc.New(tx)
	existing, err := queries.GetStepsByIntervalForUpdate(ctx, sqlc.GetStepsByIntervalForUpdateParams{
		SessionID:     sessionID,
		StartDatetime: timestamp(start),
	})
	switch {
	case err == nil:
		return applyExistingSteps(ctx, tx, queries, existing, id, sessionID, start, end, steps)
	case errors.Is(err, pgx.ErrNoRows):
		return insertOrResolveSteps(ctx, tx, queries, id, sessionID, start, end, steps)
	default:
		return err
	}
}

func insertOrResolveSteps(
	ctx context.Context,
	tx pgx.Tx,
	queries *sqlc.Queries,
	id, sessionID pgtype.UUID,
	start, end time.Time,
	steps walk.Steps,
) error {
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
	switch rows {
	case 1:
		return tx.Commit(ctx)
	case 0:
		// 競合した既存行を再取得する。
	default:
		return fmt.Errorf("unexpected inserted step row count: %d", rows)
	}

	// 親Sessionをロックしないため、区間確認後に別トランザクションが同じ区間を挿入することがある。
	// ON CONFLICTで挿入されなかった場合は区間を再取得して冪等性を判定し、区間がなければID競合を確認する。
	existing, err := queries.GetStepsByIntervalForUpdate(ctx, sqlc.GetStepsByIntervalForUpdateParams{
		SessionID:     sessionID,
		StartDatetime: timestamp(start),
	})
	if err == nil {
		return applyExistingSteps(ctx, tx, queries, existing, id, sessionID, start, end, steps)
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if _, err := queries.GetStepsByIDForUpdate(ctx, id); err == nil {
		return walk.ErrConflict
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	return walk.ErrConflict
}

func applyExistingSteps(
	ctx context.Context,
	tx pgx.Tx,
	queries *sqlc.Queries,
	existing sqlc.GetStepsByIntervalForUpdateRow,
	id, sessionID pgtype.UUID,
	start, end time.Time,
	steps walk.Steps,
) error {
	if !sameUUID(existing.ID, id) || !sameUUID(existing.SessionID, sessionID) ||
		!sameTimestamp(existing.StartDatetime, start) || !sameTimestamp(existing.EndDatetime, end) {
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

func sameLocation(existing sqlc.GetLocationForUpdateRow, id, sessionID pgtype.UUID, recordedAt time.Time, location walk.Location) bool {
	return sameUUID(existing.ID, id) && sameUUID(existing.SessionID, sessionID) &&
		sameTimestamp(existing.RecordedAt, recordedAt) && existing.Latitude == location.Latitude &&
		existing.Longitude == location.Longitude && existing.AccuracyM == location.AccuracyM
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
