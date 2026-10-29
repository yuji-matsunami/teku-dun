package httpapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
)

const (
	httpTestSessionID = "10000000-0000-4000-8000-000000000001"
	httpTestEventID   = "20000000-0000-4000-8000-000000000001"
)

type walkHTTPTestService struct {
	session       walk.Session
	location      walk.Location
	steps         walk.Steps
	sessionCalls  int
	locationCalls int
	stepsCalls    int
	sessionErr    error
	locationErr   error
	stepsErr      error
}

func (s *walkHTTPTestService) PutSession(_ context.Context, session walk.Session) error {
	s.sessionCalls++
	s.session = session
	return s.sessionErr
}

func (s *walkHTTPTestService) PutLocation(_ context.Context, location walk.Location) error {
	s.locationCalls++
	s.location = location
	return s.locationErr
}

func (s *walkHTTPTestService) PutSteps(_ context.Context, steps walk.Steps) error {
	s.stepsCalls++
	s.steps = steps
	return s.stepsErr
}

func (s *walkHTTPTestService) calls() int {
	return s.sessionCalls + s.locationCalls + s.stepsCalls
}

func newWalkTestRouter(t *testing.T, service WalkService) http.Handler {
	t.Helper()
	validator, err := NewOpenAPIRequestValidator()
	if err != nil {
		t.Fatalf("create request validator: %v", err)
	}
	router := chi.NewRouter()
	router.Use(ValidateRequestBody, validator)
	openapi.HandlerFromMux(NewHandler(nil, time.Second).WithWalkService(service), router)
	return router
}

func putWalkTestRequest(router http.Handler, path, body, contentType string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(http.MethodPut, path, strings.NewReader(body))
	if contentType != "" {
		request.Header.Set("Content-Type", contentType)
	}
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)
	return recorder
}

func TestWalkHTTPAcceptsSessionLocationAndSteps(t *testing.T) {
	service := &walkHTTPTestService{}
	router := newWalkTestRouter(t, service)

	tests := []struct {
		name string
		path string
		body string
	}{
		{
			name: "session",
			path: "/sessions/" + httpTestSessionID,
			body: `{"start_datetime":"2026-01-01T10:00:00Z"}`,
		},
		{
			name: "location",
			path: "/sessions/" + httpTestSessionID + "/locations/" + httpTestEventID,
			body: `{"recorded_at":"2026-01-01T10:00:30Z","latitude":35.5,"longitude":139.5,"accuracy_m":3}`,
		},
		{
			name: "steps",
			path: "/sessions/" + httpTestSessionID + "/steps/" + httpTestEventID,
			body: `{"start_datetime":"2026-01-01T10:00:00Z","end_datetime":"2026-01-01T10:01:00Z","steps":100,"revision":1}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			before := service.calls()
			response := putWalkTestRequest(router, tt.path, tt.body, "application/json")
			if response.Code != http.StatusNoContent {
				t.Fatalf("status = %d, body = %q, want %d", response.Code, response.Body.String(), http.StatusNoContent)
			}
			if response.Body.Len() != 0 {
				t.Fatalf("204 response body = %q, want empty", response.Body.String())
			}
			if service.calls() != before+1 {
				t.Fatalf("service calls = %d, want %d", service.calls(), before+1)
			}
		})
	}

	if service.session.ID != httpTestSessionID {
		t.Errorf("session ID = %q, want %q", service.session.ID, httpTestSessionID)
	}
	if service.location.ID != httpTestEventID || service.location.SessionID != httpTestSessionID {
		t.Errorf("location IDs = %q/%q, want %q/%q", service.location.ID, service.location.SessionID, httpTestEventID, httpTestSessionID)
	}
	if service.steps.ID != httpTestEventID || service.steps.SessionID != httpTestSessionID || service.steps.Steps != 100 || service.steps.Revision != 1 {
		t.Errorf("steps = %+v, want event/session %q/%q, steps=100 revision=1", service.steps, httpTestEventID, httpTestSessionID)
	}
}

func TestWalkHTTPRejectsInvalidRequests(t *testing.T) {
	validBody := `{"start_datetime":"2026-01-01T10:00:00Z"}`
	validPath := "/sessions/" + httpTestSessionID
	oversizedBody := strings.Repeat("x", maxRequestBodyBytes+1)

	tests := []struct {
		name        string
		path        string
		body        string
		contentType string
		wantStatus  int
	}{
		{
			name:        "missing required field",
			path:        validPath,
			body:        `{}`,
			contentType: "application/json",
			wantStatus:  http.StatusBadRequest,
		},
		{
			name:        "null required field",
			path:        validPath,
			body:        `{"start_datetime":null}`,
			contentType: "application/json",
			wantStatus:  http.StatusBadRequest,
		},
		{
			name:        "malformed JSON",
			path:        validPath,
			body:        `{"start_datetime":`,
			contentType: "application/json",
			wantStatus:  http.StatusBadRequest,
		},
		{
			name:        "unknown field",
			path:        validPath,
			body:        `{"start_datetime":"2026-01-01T10:00:00Z","extra":true}`,
			contentType: "application/json",
			wantStatus:  http.StatusBadRequest,
		},
		{
			name:        "trailing JSON",
			path:        validPath,
			body:        validBody + `{}`,
			contentType: "application/json",
			wantStatus:  http.StatusBadRequest,
		},
		{
			name:        "oversized body",
			path:        validPath,
			body:        oversizedBody,
			contentType: "application/json",
			wantStatus:  http.StatusBadRequest,
		},
		{
			name:        "wrong content type",
			path:        validPath,
			body:        validBody,
			contentType: "text/plain",
			wantStatus:  http.StatusBadRequest,
		},
		{
			name:       "missing content type",
			path:       validPath,
			body:       validBody,
			wantStatus: http.StatusBadRequest,
		},
		{
			name:        "trailing path segment",
			path:        validPath + "/extra",
			body:        validBody,
			contentType: "application/json",
			wantStatus:  http.StatusNotFound,
		},
		{
			name:        "unknown path",
			path:        "/unknown",
			body:        validBody,
			contentType: "application/json",
			wantStatus:  http.StatusNotFound,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			service := &walkHTTPTestService{}
			response := putWalkTestRequest(newWalkTestRouter(t, service), tt.path, tt.body, tt.contentType)
			if response.Code != tt.wantStatus {
				t.Fatalf("status = %d, body = %q, want %d", response.Code, response.Body.String(), tt.wantStatus)
			}
			if service.calls() != 0 {
				t.Fatalf("invalid request reached service %d time(s)", service.calls())
			}
		})
	}
}

func TestWalkHTTPValidatesUUIDAtEachBoundary(t *testing.T) {
	tests := []struct {
		name             string
		id               string
		wantServiceCalls int
	}{
		{name: "invalid format is rejected by OpenAPI", id: "not-a-uuid"},
		{name: "nil UUID is rejected by Service", id: "00000000-0000-0000-0000-000000000000", wantServiceCalls: 1},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := &walkHTTPTestService{sessionErr: walk.ErrInvalid}
			response := putWalkTestRequest(
				newWalkTestRouter(t, service),
				"/sessions/"+test.id,
				`{"start_datetime":"2026-01-01T10:00:00Z"}`,
				"application/json",
			)

			if response.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, body = %q, want %d", response.Code, response.Body.String(), http.StatusBadRequest)
			}
			if service.sessionCalls != test.wantServiceCalls {
				t.Fatalf("service calls = %d, want %d", service.sessionCalls, test.wantServiceCalls)
			}
			if test.wantServiceCalls == 1 && service.session.ID != test.id {
				t.Fatalf("service received ID = %q, want %q", service.session.ID, test.id)
			}
		})
	}
}

func TestWalkHTTPMapsDomainErrorsAndHidesStorageDetails(t *testing.T) {
	secret := "postgres://user:secret-password@db.example.test:5432/teku_dun"
	tests := []struct {
		name       string
		serviceErr error
		wantStatus int
		wantCode   string
	}{
		{
			name:       "invalid event",
			serviceErr: walk.ErrInvalid,
			wantStatus: http.StatusBadRequest,
			wantCode:   invalidRequestCode,
		},
		{
			name:       "missing session",
			serviceErr: walk.ErrNotFound,
			wantStatus: http.StatusNotFound,
			wantCode:   notFoundCode,
		},
		{
			name:       "conflicting event",
			serviceErr: walk.ErrConflict,
			wantStatus: http.StatusConflict,
			wantCode:   conflictCode,
		},
		{
			name:       "raw storage error",
			serviceErr: errors.New(secret),
			wantStatus: http.StatusServiceUnavailable,
			wantCode:   serviceUnavailableCode,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			service := &walkHTTPTestService{sessionErr: tt.serviceErr}
			response := putWalkTestRequest(newWalkTestRouter(t, service), "/sessions/"+httpTestSessionID, `{"start_datetime":"2026-01-01T10:00:00Z"}`, "application/json")
			if response.Code != tt.wantStatus {
				t.Fatalf("status = %d, body = %q, want %d", response.Code, response.Body.String(), tt.wantStatus)
			}
			body := response.Body.String()
			if !strings.Contains(body, `"code":"`+tt.wantCode+`"`) {
				t.Fatalf("body = %q, want code %q", body, tt.wantCode)
			}
			if strings.Contains(body, secret) || strings.Contains(body, "secret-password") {
				t.Fatalf("response exposes storage error: %q", body)
			}
		})
	}
}
