package walk

import (
	"context"
	"errors"
	"math"
	"time"
)

var (
	// ErrInvalidは、イベントが散歩記録の入力規則に違反していることを表す。
	ErrInvalid = errors.New("invalid walk event")
	// ErrNotFoundは、イベントが未保存のセッションを参照していることを表す。
	ErrNotFound = errors.New("walk session not found")
	// ErrConflictは、同じ冪等性キーが異なるデータで再利用されたことを表す。
	ErrConflict = errors.New("walk event conflict")
)

// Serviceは、Repositoryへ渡す前に散歩イベントを検証する。
type Service struct {
	repo Repository
	now  func() time.Time
}

// NewServiceは、散歩イベントを扱うServiceを生成する。
func NewService(repo Repository) *Service {
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
	return !math.IsNaN(latitude) && !math.IsInf(latitude, 0) && latitude >= -90 && latitude <= 90 &&
		!math.IsNaN(longitude) && !math.IsInf(longitude, 0) && longitude >= -180 && longitude <= 180 &&
		!math.IsNaN(accuracy) && !math.IsInf(accuracy, 0) && accuracy >= 0
}

func validUUID(value string) bool {
	if len(value) != 36 || value[8] != '-' || value[13] != '-' || value[18] != '-' || value[23] != '-' {
		return false
	}
	allZero := true
	for i := range value {
		if i == 8 || i == 13 || i == 18 || i == 23 {
			continue
		}
		c := value[i]
		if !isHex(c) {
			return false
		}
		if c != '0' {
			allZero = false
		}
	}
	// 全桁0のUUIDは、この境界では未指定値として予約する。
	return !allZero
}

func isHex(value byte) bool {
	return value >= '0' && value <= '9' || value >= 'a' && value <= 'f' || value >= 'A' && value <= 'F'
}
