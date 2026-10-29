package httpapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
)

const (
	locationTestSessionID = "10000000-0000-4000-8000-000000000001"
	locationTestEventID   = "20000000-0000-4000-8000-000000000001"
	locationTestPath      = "/sessions/" + locationTestSessionID + "/locations/" + locationTestEventID
)

type locationHTTPTestService struct {
	ctx      context.Context
	location walk.Location
	calls    int
	err      error
}

func (*locationHTTPTestService) PutSession(context.Context, walk.Session) error { return nil }

func (s *locationHTTPTestService) PutLocation(ctx context.Context, location walk.Location) error {
	s.ctx = ctx
	s.location = location
	s.calls++
	return s.err
}

func (*locationHTTPTestService) PutSteps(context.Context, walk.Steps) error { return nil }

func putLocationTestRequest(handler http.Handler, request *http.Request) *httptest.ResponseRecorder {
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	return recorder
}

func TestPutLocationMapsRequestToService(t *testing.T) {
	service := &locationHTTPTestService{}
	handler := requestValidationHandler(t, service)
	type contextKey struct{}
	contextValue := "location-request"
	request := httptest.NewRequest(http.MethodPut, locationTestPath, strings.NewReader(
		`{"recorded_at":"2026-01-01T10:00:30Z","latitude":35.681236,"longitude":139.767125,"accuracy_m":4.5}`,
	))
	request = request.WithContext(context.WithValue(request.Context(), contextKey{}, contextValue))

	response := putLocationTestRequest(handler, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d, body = %q, want %d", response.Code, response.Body.String(), http.StatusNoContent)
	}
	if response.Body.Len() != 0 {
		t.Errorf("body = %q, want empty", response.Body.String())
	}
	if service.calls != 1 {
		t.Fatalf("service calls = %d, want 1", service.calls)
	}
	if got := service.ctx.Value(contextKey{}); got != contextValue {
		t.Errorf("context value = %v, want %q", got, contextValue)
	}
	want := walk.Location{
		ID:         locationTestEventID,
		SessionID:  locationTestSessionID,
		RecordedAt: time.Date(2026, time.January, 1, 10, 0, 30, 0, time.UTC),
		Latitude:   35.681236,
		Longitude:  139.767125,
		AccuracyM:  4.5,
	}
	if service.location != want {
		t.Errorf("location = %+v, want %+v", service.location, want)
	}
}

func TestPutLocationRejectsInvalidRequestBeforeService(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{
			name: "missing latitude",
			body: `{"recorded_at":"2026-01-01T10:00:30Z","longitude":139.767125,"accuracy_m":4.5}`,
		},
		{
			name: "unknown field",
			body: `{"recorded_at":"2026-01-01T10:00:30Z","latitude":35.681236,"longitude":139.767125,"accuracy_m":4.5,"extra":true}`,
		},
		{
			name: "latitude out of range",
			body: `{"recorded_at":"2026-01-01T10:00:30Z","latitude":90.1,"longitude":139.767125,"accuracy_m":4.5}`,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := &locationHTTPTestService{}
			request := httptest.NewRequest(http.MethodPut, locationTestPath, strings.NewReader(test.body))

			response := putLocationTestRequest(requestValidationHandler(t, service), request)

			if response.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, body = %q, want %d", response.Code, response.Body.String(), http.StatusBadRequest)
			}
			if service.calls != 0 {
				t.Fatalf("invalid request reached service %d time(s)", service.calls)
			}
			if !strings.Contains(response.Body.String(), `"code":"invalid_request"`) {
				t.Errorf("body = %q, want invalid_request", response.Body.String())
			}
		})
	}
}

func TestPutLocationMapsServiceErrors(t *testing.T) {
	secret := "postgres://user:secret-password@db.example.test:5432/teku_dun"
	tests := []struct {
		name       string
		err        error
		wantStatus int
		wantCode   string
	}{
		{name: "invalid event", err: walk.ErrInvalid, wantStatus: http.StatusBadRequest, wantCode: invalidRequestCode},
		{name: "missing session", err: walk.ErrNotFound, wantStatus: http.StatusNotFound, wantCode: notFoundCode},
		{name: "conflicting event", err: walk.ErrConflict, wantStatus: http.StatusConflict, wantCode: conflictCode},
		{name: "storage failure", err: errors.New(secret), wantStatus: http.StatusServiceUnavailable, wantCode: serviceUnavailableCode},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := &locationHTTPTestService{err: test.err}
			request := httptest.NewRequest(http.MethodPut, locationTestPath, strings.NewReader(
				`{"recorded_at":"2026-01-01T10:00:30Z","latitude":35.681236,"longitude":139.767125,"accuracy_m":4.5}`,
			))

			response := putLocationTestRequest(requestValidationHandler(t, service), request)

			if response.Code != test.wantStatus {
				t.Fatalf("status = %d, body = %q, want %d", response.Code, response.Body.String(), test.wantStatus)
			}
			if service.calls != 1 {
				t.Fatalf("service calls = %d, want 1", service.calls)
			}
			body := response.Body.String()
			if !strings.Contains(body, `"code":"`+test.wantCode+`"`) {
				t.Errorf("body = %q, want code %q", body, test.wantCode)
			}
			if strings.Contains(body, secret) || strings.Contains(body, "secret-password") {
				t.Errorf("response exposes storage error: %q", body)
			}
		})
	}
}
