package walk

import (
	"context"
	"errors"
	"math"
	"testing"
	"time"
)

const (
	testSessionID = "10000000-0000-4000-8000-000000000001"
	testEventID   = "20000000-0000-4000-8000-000000000001"
)

type serviceTestRepository struct {
	session         Session
	location        Location
	steps           Steps
	sessionCalls    int
	locationCalls   int
	stepsCalls      int
	sessionErr      error
	getSessionCalls int
	getSessionErr   error
	locationErr     error
	stepsErr        error
}

func (r *serviceTestRepository) PutSession(_ context.Context, session Session) error {
	r.sessionCalls++
	r.session = session
	return r.sessionErr
}

func (r *serviceTestRepository) GetSession(_ context.Context, id string) (Session, error) {
	r.getSessionCalls++
	if r.getSessionErr != nil {
		return Session{}, r.getSessionErr
	}
	if r.session.ID != id {
		return Session{}, ErrNotFound
	}
	return r.session, nil
}

func (r *serviceTestRepository) PutLocation(_ context.Context, location Location) error {
	r.locationCalls++
	r.location = location
	return r.locationErr
}

func (r *serviceTestRepository) PutSteps(_ context.Context, steps Steps) error {
	r.stepsCalls++
	r.steps = steps
	return r.stepsErr
}

func newTestService(repo *serviceTestRepository) (*Service, time.Time) {
	now := time.Date(2026, time.January, 1, 10, 0, 0, 0, time.UTC)
	service := NewService(repo)
	service.now = func() time.Time { return now }
	return service, now
}

func TestServicePutSessionTimeValidation(t *testing.T) {
	_, now := newTestService(&serviceTestRepository{})
	startWithOffset := time.Date(2026, time.January, 1, 18, 0, 0, 123456789, time.FixedZone("JST", 9*60*60))

	tests := []struct {
		name      string
		start     time.Time
		wantErr   error
		wantStart time.Time
	}{
		{
			name:      "future boundary is accepted",
			start:     now.Add(5 * time.Minute),
			wantStart: now.Add(5 * time.Minute).UTC(),
		},
		{
			name:    "future beyond boundary is rejected",
			start:   now.Add(5*time.Minute + time.Microsecond),
			wantErr: ErrInvalid,
		},
		{
			name:      "past is accepted",
			start:     now.Add(-24 * time.Hour),
			wantStart: now.Add(-24 * time.Hour).UTC(),
		},
		{
			name:      "timezone and sub-microseconds are normalized",
			start:     startWithOffset,
			wantStart: startWithOffset.UTC().Truncate(time.Microsecond),
		},
		{
			name:    "zero time is rejected",
			start:   time.Time{},
			wantErr: ErrInvalid,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repo := &serviceTestRepository{}
			service, _ := newTestService(repo)
			err := service.PutSession(context.Background(), Session{
				ID:            testSessionID,
				StartDatetime: tt.start,
			})
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("error = %v, want %v", err, tt.wantErr)
			}
			if tt.wantErr != nil {
				if repo.sessionCalls != 0 {
					t.Fatalf("repository calls = %d, want 0", repo.sessionCalls)
				}
				return
			}
			if repo.sessionCalls != 1 {
				t.Fatalf("repository calls = %d, want 1", repo.sessionCalls)
			}
			if !repo.session.StartDatetime.Equal(tt.wantStart) || repo.session.StartDatetime.Location() != time.UTC {
				t.Fatalf("stored start = %s, want %s", repo.session.StartDatetime, tt.wantStart)
			}
		})
	}
}

func TestServicePutLocationValidation(t *testing.T) {
	_, now := newTestService(&serviceTestRepository{})
	recordedAt := now.Add(123456789 * time.Nanosecond)

	tests := []struct {
		name                string
		location            Location
		sessionStart        time.Time
		wantErr             error
		wantAt              time.Time
		wantGetSessionCalls int
	}{
		{
			name: "valid location is normalized",
			location: Location{
				ID:         testEventID,
				SessionID:  testSessionID,
				RecordedAt: recordedAt,
				Latitude:   35.681236,
				Longitude:  139.767125,
				AccuracyM:  3.5,
			},
			wantAt:              recordedAt.Truncate(time.Microsecond),
			wantGetSessionCalls: 1,
		},
		{
			name: "future boundary is accepted",
			location: Location{
				ID:         testEventID,
				SessionID:  testSessionID,
				RecordedAt: now.Add(5 * time.Minute),
				Latitude:   0,
				Longitude:  0,
				AccuracyM:  0,
			},
			wantAt:              now.UTC().Add(5 * time.Minute),
			wantGetSessionCalls: 1,
		},
		{
			name: "future beyond boundary is rejected",
			location: Location{
				ID:         testEventID,
				SessionID:  testSessionID,
				RecordedAt: now.Add(5*time.Minute + time.Microsecond),
				Latitude:   0,
				Longitude:  0,
				AccuracyM:  0,
			},
			wantErr: ErrInvalid,
		},
		{
			name: "past is accepted",
			location: Location{
				ID:         testEventID,
				SessionID:  testSessionID,
				RecordedAt: now.Add(-time.Hour),
				Latitude:   -90,
				Longitude:  180,
				AccuracyM:  0,
			},
			wantAt:              now.UTC().Add(-time.Hour),
			wantGetSessionCalls: 1,
		},
		{
			name:         "event before session start is rejected",
			sessionStart: now,
			location: Location{
				ID:         testEventID,
				SessionID:  testSessionID,
				RecordedAt: now.Add(-time.Minute),
				Latitude:   35.681236,
				Longitude:  139.767125,
				AccuracyM:  3.5,
			},
			wantErr:             ErrInvalid,
			wantGetSessionCalls: 1,
		},
		{
			name: "event UUID is invalid",
			location: Location{
				ID:         "not-a-uuid",
				SessionID:  testSessionID,
				RecordedAt: recordedAt,
			},
			wantErr: ErrInvalid,
		},
		{
			name: "session UUID is invalid",
			location: Location{
				ID:         testEventID,
				SessionID:  "00000000-0000-0000-0000-000000000000",
				RecordedAt: recordedAt,
			},
			wantErr: ErrInvalid,
		},
		{
			name: "latitude is outside range",
			location: Location{
				ID:         testEventID,
				SessionID:  testSessionID,
				RecordedAt: recordedAt,
				Latitude:   90.000001,
			},
			wantErr: ErrInvalid,
		},
		{
			name: "longitude is outside range",
			location: Location{
				ID:         testEventID,
				SessionID:  testSessionID,
				RecordedAt: recordedAt,
				Longitude:  -180.000001,
			},
			wantErr: ErrInvalid,
		},
		{
			name: "accuracy cannot be negative",
			location: Location{
				ID:         testEventID,
				SessionID:  testSessionID,
				RecordedAt: recordedAt,
				AccuracyM:  -0.001,
			},
			wantErr: ErrInvalid,
		},
		{
			name: "non-finite coordinate is rejected",
			location: Location{
				ID:         testEventID,
				SessionID:  testSessionID,
				RecordedAt: recordedAt,
				Latitude:   math.NaN(),
			},
			wantErr: ErrInvalid,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sessionStart := tt.sessionStart
			if sessionStart.IsZero() {
				sessionStart = now.Add(-time.Hour)
			}
			repo := &serviceTestRepository{session: Session{ID: testSessionID, StartDatetime: sessionStart}}
			service, _ := newTestService(repo)
			err := service.PutLocation(context.Background(), tt.location)
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("error = %v, want %v", err, tt.wantErr)
			}
			if repo.getSessionCalls != tt.wantGetSessionCalls {
				t.Fatalf("GetSession calls = %d, want %d", repo.getSessionCalls, tt.wantGetSessionCalls)
			}
			if tt.wantErr != nil {
				if repo.locationCalls != 0 {
					t.Fatalf("repository calls = %d, want 0", repo.locationCalls)
				}
				return
			}
			if repo.locationCalls != 1 {
				t.Fatalf("repository calls = %d, want 1", repo.locationCalls)
			}
			if !repo.location.RecordedAt.Equal(tt.wantAt) || repo.location.RecordedAt.Location() != time.UTC {
				t.Fatalf("stored recorded_at = %s, want %s", repo.location.RecordedAt, tt.wantAt)
			}
		})
	}
}

func TestServicePutStepsValidation(t *testing.T) {
	_, now := newTestService(&serviceTestRepository{})
	startWithOffset := time.Date(2026, time.January, 1, 19, 0, 0, 123456789, time.FixedZone("JST", 9*60*60))
	endWithOffset := startWithOffset.Add(time.Minute)

	tests := []struct {
		name                string
		steps               Steps
		sessionStart        time.Time
		wantErr             error
		wantStart           time.Time
		wantEnd             time.Time
		wantGetSessionCalls int
	}{
		{
			name: "one minute interval and revision are accepted",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: startWithOffset,
				EndDatetime:   endWithOffset,
				Steps:         120,
				Revision:      7,
			},
			sessionStart:        startWithOffset.UTC().Truncate(time.Microsecond),
			wantStart:           startWithOffset.UTC().Truncate(time.Microsecond),
			wantEnd:             endWithOffset.UTC().Truncate(time.Microsecond),
			wantGetSessionCalls: 1,
		},
		{
			name: "short final interval is accepted",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: now.Add(-time.Minute),
				EndDatetime:   now.Add(-30 * time.Second),
				Steps:         0,
				Revision:      1,
			},
			sessionStart:        now.Add(-time.Minute),
			wantStart:           now.UTC().Add(-time.Minute),
			wantEnd:             now.UTC().Add(-30 * time.Second),
			wantGetSessionCalls: 1,
		},
		{
			name: "future boundary is accepted",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: now.Add(4 * time.Minute),
				EndDatetime:   now.Add(5 * time.Minute),
				Steps:         1,
				Revision:      1,
			},
			sessionStart:        now,
			wantStart:           now.UTC().Add(4 * time.Minute),
			wantEnd:             now.UTC().Add(5 * time.Minute),
			wantGetSessionCalls: 1,
		},
		{
			name: "future beyond boundary is rejected",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: now.Add(4 * time.Minute),
				EndDatetime:   now.Add(5*time.Minute + time.Microsecond),
				Steps:         1,
				Revision:      1,
			},
			wantErr: ErrInvalid,
		},
		{
			name: "past is accepted",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: now.Add(-2 * time.Minute),
				EndDatetime:   now.Add(-time.Minute),
				Steps:         10,
				Revision:      2,
			},
			sessionStart:        now.Add(-3 * time.Minute),
			wantStart:           now.UTC().Add(-2 * time.Minute),
			wantEnd:             now.UTC().Add(-time.Minute),
			wantGetSessionCalls: 1,
		},
		{
			name: "start on session minute boundary is accepted",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: now,
				EndDatetime:   now.Add(time.Minute),
				Steps:         12,
				Revision:      1,
			},
			sessionStart:        now.Add(-time.Minute),
			wantStart:           now.UTC(),
			wantEnd:             now.UTC().Add(time.Minute),
			wantGetSessionCalls: 1,
		},
		{
			name: "start before session start is rejected",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: now.Add(-time.Minute),
				EndDatetime:   now,
				Revision:      1,
			},
			sessionStart:        now,
			wantErr:             ErrInvalid,
			wantGetSessionCalls: 1,
		},
		{
			name: "start outside session minute boundary is rejected",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: now,
				EndDatetime:   now.Add(30 * time.Second),
				Revision:      1,
			},
			sessionStart:        now.Add(-30 * time.Second),
			wantErr:             ErrInvalid,
			wantGetSessionCalls: 1,
		},
		{
			name: "duration over one minute is rejected",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: now,
				EndDatetime:   now.Add(time.Minute + time.Microsecond),
				Revision:      1,
			},
			wantErr: ErrInvalid,
		},
		{
			name: "zero duration is rejected",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: now,
				EndDatetime:   now,
				Revision:      1,
			},
			wantErr: ErrInvalid,
		},
		{
			name: "duration collapsed by microsecond normalization is rejected",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: now.Add(100 * time.Nanosecond),
				EndDatetime:   now.Add(900 * time.Nanosecond),
				Revision:      1,
			},
			wantErr: ErrInvalid,
		},
		{
			name: "negative duration is rejected",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: now.Add(time.Minute),
				EndDatetime:   now,
				Revision:      1,
			},
			wantErr: ErrInvalid,
		},
		{
			name: "zero revision is rejected",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: now,
				EndDatetime:   now.Add(time.Second),
				Revision:      0,
			},
			wantErr: ErrInvalid,
		},
		{
			name: "negative steps are rejected",
			steps: Steps{
				ID:            testEventID,
				SessionID:     testSessionID,
				StartDatetime: now,
				EndDatetime:   now.Add(time.Second),
				Steps:         -1,
				Revision:      1,
			},
			wantErr: ErrInvalid,
		},
		{
			name: "event UUID is invalid",
			steps: Steps{
				ID:            "bad",
				SessionID:     testSessionID,
				StartDatetime: now,
				EndDatetime:   now.Add(time.Second),
				Revision:      1,
			},
			wantErr: ErrInvalid,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repo := &serviceTestRepository{}
			if tt.wantGetSessionCalls > 0 {
				repo.session = Session{ID: testSessionID, StartDatetime: tt.sessionStart}
			}
			service, _ := newTestService(repo)
			err := service.PutSteps(context.Background(), tt.steps)
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("error = %v, want %v", err, tt.wantErr)
			}
			if repo.getSessionCalls != tt.wantGetSessionCalls {
				t.Fatalf("GetSession calls = %d, want %d", repo.getSessionCalls, tt.wantGetSessionCalls)
			}
			if tt.wantErr != nil {
				if repo.stepsCalls != 0 {
					t.Fatalf("repository calls = %d, want 0", repo.stepsCalls)
				}
				return
			}
			if repo.stepsCalls != 1 {
				t.Fatalf("repository calls = %d, want 1", repo.stepsCalls)
			}
			if !repo.steps.StartDatetime.Equal(tt.wantStart) || !repo.steps.EndDatetime.Equal(tt.wantEnd) ||
				repo.steps.StartDatetime.Location() != time.UTC || repo.steps.EndDatetime.Location() != time.UTC {
				t.Fatalf("stored interval = %s-%s, want %s-%s", repo.steps.StartDatetime, repo.steps.EndDatetime, tt.wantStart, tt.wantEnd)
			}
			if repo.steps.Steps != tt.steps.Steps || repo.steps.Revision != tt.steps.Revision {
				t.Fatalf("stored step payload = %+v, want steps=%d revision=%d", repo.steps, tt.steps.Steps, tt.steps.Revision)
			}
		})
	}
}

func TestServicePropagatesRepositoryError(t *testing.T) {
	wantErr := errors.New("repository unavailable")
	repo := &serviceTestRepository{sessionErr: wantErr}
	service, now := newTestService(repo)

	err := service.PutSession(context.Background(), Session{ID: testSessionID, StartDatetime: now})
	if !errors.Is(err, wantErr) {
		t.Fatalf("error = %v, want %v", err, wantErr)
	}
}

func TestServicePropagatesMissingSessionWithoutSaving(t *testing.T) {
	t.Run("location", func(t *testing.T) {
		repo := &serviceTestRepository{getSessionErr: ErrNotFound}
		service, now := newTestService(repo)
		location := Location{
			ID:         testEventID,
			SessionID:  testSessionID,
			RecordedAt: now,
			Latitude:   35.681236,
			Longitude:  139.767125,
			AccuracyM:  3.5,
		}

		err := service.PutLocation(context.Background(), location)
		if !errors.Is(err, ErrNotFound) {
			t.Fatalf("error = %v, want %v", err, ErrNotFound)
		}
		if repo.getSessionCalls != 1 || repo.locationCalls != 0 {
			t.Fatalf("GetSession calls = %d, PutLocation calls = %d, want 1 and 0", repo.getSessionCalls, repo.locationCalls)
		}
	})

	t.Run("steps", func(t *testing.T) {
		repo := &serviceTestRepository{getSessionErr: ErrNotFound}
		service, now := newTestService(repo)
		steps := Steps{
			ID:            testEventID,
			SessionID:     testSessionID,
			StartDatetime: now,
			EndDatetime:   now.Add(time.Minute),
			Steps:         10,
			Revision:      1,
		}

		err := service.PutSteps(context.Background(), steps)
		if !errors.Is(err, ErrNotFound) {
			t.Fatalf("error = %v, want %v", err, ErrNotFound)
		}
		if repo.getSessionCalls != 1 || repo.stepsCalls != 0 {
			t.Fatalf("GetSession calls = %d, PutSteps calls = %d, want 1 and 0", repo.getSessionCalls, repo.stepsCalls)
		}
	})
}

func TestNormalizeAndValidateTime(t *testing.T) {
	now := time.Date(2026, time.January, 1, 10, 0, 0, 0, time.UTC)
	offsetWithSeconds := time.FixedZone("offset-with-seconds", 9*60*60+30)

	tests := []struct {
		name  string
		value time.Time
		now   time.Time
		want  time.Time
		ok    bool
	}{
		{
			name:  "timezone is converted to UTC and nanoseconds are truncated",
			value: time.Date(2026, time.January, 1, 19, 0, 0, 123456789, time.FixedZone("JST", 9*60*60)),
			now:   now,
			want:  time.Date(2026, time.January, 1, 10, 0, 0, 123456000, time.UTC),
			ok:    true,
		},
		{
			name:  "past time is accepted",
			value: now.Add(-24 * time.Hour),
			now:   now,
			want:  now.Add(-24 * time.Hour),
			ok:    true,
		},
		{
			name:  "future boundary is accepted",
			value: now.Add(5 * time.Minute),
			now:   now,
			want:  now.Add(5 * time.Minute),
			ok:    true,
		},
		{
			name:  "sub-microsecond beyond future boundary is truncated and accepted",
			value: now.Add(5*time.Minute + 999*time.Nanosecond),
			now:   now,
			want:  now.Add(5 * time.Minute),
			ok:    true,
		},
		{
			name:  "one microsecond beyond future boundary is rejected",
			value: now.Add(5*time.Minute + time.Microsecond),
			now:   now,
		},
		{
			name:  "non-zero time in year one is accepted",
			value: time.Date(1, time.January, 2, 0, 0, 0, 0, time.UTC),
			now:   now,
			want:  time.Date(1, time.January, 2, 0, 0, 0, 0, time.UTC),
			ok:    true,
		},
		{
			name:  "maximum RFC3339 year is accepted",
			value: time.Date(9999, time.January, 1, 0, 0, 0, 0, time.UTC),
			now:   time.Date(9999, time.January, 1, 0, 0, 0, 0, time.UTC),
			want:  time.Date(9999, time.January, 1, 0, 0, 0, 0, time.UTC),
			ok:    true,
		},
		{
			name: "zero time is rejected",
			now:  now,
		},
		{
			name:  "year zero is rejected",
			value: time.Date(0, time.January, 1, 0, 0, 0, 0, time.UTC),
			now:   now,
		},
		{
			name:  "year ten thousand is rejected",
			value: time.Date(10000, time.January, 1, 0, 0, 0, 0, time.UTC),
			now:   now,
		},
		{
			name:  "timezone offset with seconds is rejected",
			value: time.Date(2026, time.January, 1, 19, 0, 0, 0, offsetWithSeconds),
			now:   now,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := normalizeAndValidateTime(tt.value, tt.now)
			if ok != tt.ok {
				t.Fatalf("ok = %t, want %t", ok, tt.ok)
			}
			if !tt.ok {
				if !got.IsZero() {
					t.Fatalf("time = %s, want zero value", got)
				}
				return
			}
			if !got.Equal(tt.want) || got.Location() != time.UTC {
				t.Fatalf("time = %s (%s), want %s (UTC)", got, got.Location(), tt.want)
			}
		})
	}
}

func TestWholeMinutesFromAcrossRFC3339YearRange(t *testing.T) {
	start := time.Date(1, time.January, 1, 0, 0, 0, 0, time.UTC)
	end := time.Date(9999, time.January, 1, 0, 0, 0, 0, time.UTC)
	if !wholeMinutesFrom(start, end) {
		t.Fatalf("wholeMinutesFrom(%s, %s) = false, want true", start, end)
	}
}

func TestValidUUID(t *testing.T) {
	tests := []struct {
		name  string
		value string
		want  bool
	}{
		{name: "canonical lowercase", value: "10000000-0000-4000-8000-000000000001", want: true},
		{name: "canonical uppercase", value: "A0000000-0000-4000-8000-000000000001", want: true},
		{name: "nil UUID", value: "00000000-0000-0000-0000-000000000000", want: false},
		{name: "compact form", value: "10000000000040008000000000000001", want: false},
		{name: "braced form", value: "{10000000-0000-4000-8000-000000000001}", want: false},
		{name: "URN form", value: "urn:uuid:10000000-0000-4000-8000-000000000001", want: false},
		{name: "invalid text", value: "not-a-uuid", want: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := validUUID(tt.value); got != tt.want {
				t.Fatalf("validUUID(%q) = %t, want %t", tt.value, got, tt.want)
			}
		})
	}
}
