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
	stepsTestSessionID = "10000000-0000-4000-8000-000000000002"
	stepsTestEventID   = "20000000-0000-4000-8000-000000000002"
	stepsTestPath      = "/sessions/" + stepsTestSessionID + "/steps/" + stepsTestEventID
)

type stepsHTTPTestService struct {
	ctx   context.Context
	steps walk.Steps
	calls int
	err   error
}

func (*stepsHTTPTestService) PutSession(context.Context, walk.Session) error { return nil }

func (*stepsHTTPTestService) PutLocation(context.Context, walk.Location) error { return nil }

func (s *stepsHTTPTestService) PutSteps(ctx context.Context, steps walk.Steps) error {
	s.ctx = ctx
	s.steps = steps
	s.calls++
	return s.err
}

func putStepsTestRequest(handler http.Handler, request *http.Request) *httptest.ResponseRecorder {
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	return recorder
}

func TestPutStepsMapsRequestToService(t *testing.T) {
	service := &stepsHTTPTestService{}
	handler := requestValidationHandler(t, service)
	type contextKey struct{}
	contextValue := "steps-request"
	request := httptest.NewRequest(http.MethodPut, stepsTestPath, strings.NewReader(
		`{"start_datetime":"2026-01-01T10:01:00Z","end_datetime":"2026-01-01T10:02:00Z","steps":90,"revision":2}`,
	))
	request = request.WithContext(context.WithValue(request.Context(), contextKey{}, contextValue))

	response := putStepsTestRequest(handler, request)

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
	want := walk.Steps{
		ID:            stepsTestEventID,
		SessionID:     stepsTestSessionID,
		StartDatetime: time.Date(2026, time.January, 1, 10, 1, 0, 0, time.UTC),
		EndDatetime:   time.Date(2026, time.January, 1, 10, 2, 0, 0, time.UTC),
		Steps:         90,
		Revision:      2,
	}
	if service.steps != want {
		t.Errorf("steps = %+v, want %+v", service.steps, want)
	}
}

func TestPutStepsRejectsInvalidRequestBeforeService(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{
			name: "missing revision",
			body: `{"start_datetime":"2026-01-01T10:01:00Z","end_datetime":"2026-01-01T10:02:00Z","steps":90}`,
		},
		{
			name: "unknown field",
			body: `{"start_datetime":"2026-01-01T10:01:00Z","end_datetime":"2026-01-01T10:02:00Z","steps":90,"revision":2,"extra":true}`,
		},
		{
			name: "negative steps",
			body: `{"start_datetime":"2026-01-01T10:01:00Z","end_datetime":"2026-01-01T10:02:00Z","steps":-1,"revision":2}`,
		},
		{
			name: "revision zero",
			body: `{"start_datetime":"2026-01-01T10:01:00Z","end_datetime":"2026-01-01T10:02:00Z","steps":90,"revision":0}`,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := &stepsHTTPTestService{}
			request := httptest.NewRequest(http.MethodPut, stepsTestPath, strings.NewReader(test.body))

			response := putStepsTestRequest(requestValidationHandler(t, service), request)

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

func TestPutStepsValidatesRFC3339OffsetsAtHTTPBoundary(t *testing.T) {
	tests := []struct {
		name       string
		start      string
		end        string
		wantStatus int
		wantCalls  int
	}{
		{
			name:       "positive 24-hour offset",
			start:      "2026-01-01T10:01:00+24:00",
			end:        "2026-01-01T10:02:00Z",
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "negative 24-hour offset",
			start:      "2026-01-01T10:01:00-24:00",
			end:        "2026-01-01T10:02:00Z",
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "minute 60 in start offset",
			start:      "2026-01-01T10:01:00+00:60",
			end:        "2026-01-01T10:02:00Z",
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "minute 60 in end offset",
			start:      "2026-01-01T10:01:00Z",
			end:        "2026-01-01T10:02:00+09:60",
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "positive maximum offset",
			start:      "2026-01-01T10:01:00+23:59",
			end:        "2026-01-01T10:02:00Z",
			wantStatus: http.StatusNoContent,
			wantCalls:  1,
		},
		{
			name:       "negative maximum offset",
			start:      "2026-01-01T10:01:00-23:59",
			end:        "2026-01-01T10:02:00Z",
			wantStatus: http.StatusNoContent,
			wantCalls:  1,
		},
		{
			name:       "ordinary offset",
			start:      "2026-01-01T10:01:00+09:00",
			end:        "2026-01-01T10:02:00Z",
			wantStatus: http.StatusNoContent,
			wantCalls:  1,
		},
		{
			name:       "UTC with fractional seconds",
			start:      "2026-01-01T10:01:00.123456789Z",
			end:        "2026-01-01T10:02:00Z",
			wantStatus: http.StatusNoContent,
			wantCalls:  1,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := &stepsHTTPTestService{}
			body := `{"start_datetime":"` + test.start + `","end_datetime":"` + test.end + `","steps":90,"revision":2}`
			request := httptest.NewRequest(http.MethodPut, stepsTestPath, strings.NewReader(body))

			response := putStepsTestRequest(requestValidationHandler(t, service), request)

			if response.Code != test.wantStatus {
				t.Fatalf("status = %d, body = %q, want %d", response.Code, response.Body.String(), test.wantStatus)
			}
			if service.calls != test.wantCalls {
				t.Fatalf("service calls = %d, want %d", service.calls, test.wantCalls)
			}
			if test.wantStatus == http.StatusBadRequest && !strings.Contains(response.Body.String(), `"code":"invalid_request"`) {
				t.Errorf("body = %q, want invalid_request", response.Body.String())
			}
		})
	}
}

func TestPutStepsMapsServiceErrors(t *testing.T) {
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
			service := &stepsHTTPTestService{err: test.err}
			request := httptest.NewRequest(http.MethodPut, stepsTestPath, strings.NewReader(
				`{"start_datetime":"2026-01-01T10:01:00Z","end_datetime":"2026-01-01T10:02:00Z","steps":90,"revision":2}`,
			))

			response := putStepsTestRequest(requestValidationHandler(t, service), request)

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
