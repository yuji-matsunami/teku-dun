package walk

import (
	"context"
	"errors"
	"math"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	// ErrInvalidは、イベントが散歩記録の入力規則に違反していることを表す。
	ErrInvalid = errors.New("invalid walk event")
	// ErrNotFoundは、イベントが未保存のセッションを参照していることを表す。
	ErrNotFound = errors.New("walk session not found")
	// ErrConflictは、同じ冪等性キーが異なるデータで再利用されたことを表す。
	ErrConflict = errors.New("walk event conflict")
)

// Serviceは、WalkRepositoryへ渡す前に散歩イベントを検証する。
type Service struct {
	repo WalkRepository
	now  func() time.Time
}

// NewServiceは、散歩イベントを扱うServiceを生成する。
func NewService(repo WalkRepository) *Service {
	return &Service{repo: repo, now: time.Now}
}

// PutSessionは、散歩セッションを検証して永続化する。
func (s *Service) PutSession(ctx context.Context, session Session) error {
	if s == nil || s.repo == nil {
		return ErrInvalid
	}
	now := s.currentTime()
	if !validUUID(session.ID) {
		return ErrInvalid
	}
	start, ok := normalizeAndValidateTime(session.StartDatetime, now)
	if !ok {
		return ErrInvalid
	}
	session.StartDatetime = start
	return s.repo.PutSession(ctx, session)
}

// PutLocationは、位置情報を検証して永続化する。
func (s *Service) PutLocation(ctx context.Context, location Location) error {
	if s == nil || s.repo == nil {
		return ErrInvalid
	}
	now := s.currentTime()
	if !validUUID(location.ID) || !validUUID(location.SessionID) ||
		!validCoordinate(location.Latitude, location.Longitude, location.AccuracyM) {
		return ErrInvalid
	}
	recordedAt, ok := normalizeAndValidateTime(location.RecordedAt, now)
	if !ok {
		return ErrInvalid
	}
	location.RecordedAt = recordedAt
	session, err := s.repo.GetSession(ctx, location.SessionID)
	if err != nil {
		return err
	}
	if location.RecordedAt.Before(session.StartDatetime) {
		return ErrInvalid
	}
	return s.repo.PutLocation(ctx, location)
}

// PutStepsは、1つの固定区間の歩数を検証して永続化する。
func (s *Service) PutSteps(ctx context.Context, steps Steps) error {
	if s == nil || s.repo == nil {
		return ErrInvalid
	}
	now := s.currentTime()
	if !validUUID(steps.ID) || !validUUID(steps.SessionID) || steps.Steps < 0 || steps.Revision < 1 {
		return ErrInvalid
	}
	start, ok := normalizeAndValidateTime(steps.StartDatetime, now)
	if !ok {
		return ErrInvalid
	}
	end, ok := normalizeAndValidateTime(steps.EndDatetime, now)
	if !ok {
		return ErrInvalid
	}
	duration := end.Sub(start)
	if duration <= 0 || duration > time.Minute {
		return ErrInvalid
	}
	steps.StartDatetime = start
	steps.EndDatetime = end
	session, err := s.repo.GetSession(ctx, steps.SessionID)
	if err != nil {
		return err
	}
	if steps.StartDatetime.Before(session.StartDatetime) || !wholeMinutesFrom(session.StartDatetime, steps.StartDatetime) {
		return ErrInvalid
	}
	return s.repo.PutSteps(ctx, steps)
}

func (s *Service) currentTime() time.Time {
	if s.now == nil {
		return time.Now()
	}
	return s.now()
}

func normalizeAndValidateTime(value, now time.Time) (time.Time, bool) {
	if value.IsZero() || value.Year() < 1 || value.Year() > 9999 {
		return time.Time{}, false
	}
	// RFC3339Nanoによる文字列化と再解析で、通信契約に表現できない年や
	// タイムゾーンオフセットを拒否し、単調時計の情報も取り除く。
	encoded := value.Format(time.RFC3339Nano)
	parsed, err := time.Parse(time.RFC3339Nano, encoded)
	if err != nil || !parsed.Equal(value) {
		return time.Time{}, false
	}
	normalized := value.UTC().Truncate(time.Microsecond)
	if normalized.IsZero() || normalized.After(now.Add(5*time.Minute)) {
		return time.Time{}, false
	}
	return normalized, true
}

func validCoordinate(latitude, longitude, accuracy float64) bool {
	return isFinite(latitude) && latitude >= -90 && latitude <= 90 &&
		isFinite(longitude) && longitude >= -180 && longitude <= 180 &&
		isFinite(accuracy) && accuracy >= 0
}

func isFinite(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}

func validUUID(value string) bool {
	id, err := uuid.Parse(value)
	return err == nil && id != uuid.Nil && strings.EqualFold(id.String(), value)
}

func wholeMinutesFrom(start, value time.Time) bool {
	// time.Durationは約290年を超えると上限値になるため、UnixMicroで差分を計算する。
	delta := value.UnixMicro() - start.UnixMicro()
	return delta >= 0 && delta%time.Minute.Microseconds() == 0
}
