package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
)

type requestValidationWalkService struct {
	called  bool
	session walk.Session
}

func (s *requestValidationWalkService) PutSession(_ context.Context, session walk.Session) error {
	s.called = true
	s.session = session
	return nil
}

func (*requestValidationWalkService) PutLocation(context.Context, walk.Location) error { return nil }
func (*requestValidationWalkService) PutSteps(context.Context, walk.Steps) error       { return nil }

func requestValidationHandler(t *testing.T, service WalkService) http.Handler {
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

func TestOpenAPIRequestValidationRejectsInvalidSessionRequests(t *testing.T) {
	tests := []struct {
		name        string
		contentType string
		body        string
	}{
		{name: "required field", contentType: "application/json", body: `{}`},
		{name: "null required field", contentType: "application/json", body: `{"start_datetime":null}`},
		{name: "null body", contentType: "application/json", body: `null`},
		{name: "array body", contentType: "application/json", body: `[]`},
		{name: "empty body", contentType: "application/json", body: ``},
		{name: "malformed JSON", contentType: "application/json", body: `{"start_datetime":`},
		{name: "trailing JSON", contentType: "application/json", body: `{"start_datetime":"2025-01-02T03:04:05Z"}{}`},
		{name: "unknown field", contentType: "application/json", body: `{"start_datetime":"2025-01-02T03:04:05Z","extra":true}`},
		{name: "missing content type", body: `{"start_datetime":"2025-01-02T03:04:05Z"}`},
		{name: "wrong content type", contentType: "text/plain", body: `{"start_datetime":"2025-01-02T03:04:05Z"}`},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := &requestValidationWalkService{}
			handler := requestValidationHandler(t, service)
			req := httptest.NewRequest(http.MethodPut, "/sessions/00000000-0000-4000-8000-000000000001", strings.NewReader(test.body))
			if test.contentType != "" {
				req.Header.Set("Content-Type", test.contentType)
			}
			recorder := httptest.NewRecorder()
			handler.ServeHTTP(recorder, req)

			if recorder.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want %d; body = %q", recorder.Code, http.StatusBadRequest, recorder.Body.String())
			}
			assertJSONContentType(t, recorder)
			if got, want := recorder.Body.String(), "{\"code\":\"invalid_request\",\"message\":\"Request is invalid.\"}\n"; got != want {
				t.Errorf("body = %q, want %q", got, want)
			}
			if service.called {
				t.Fatal("invalid request reached the walk service")
			}
		})
	}
}

func TestValidateRequestBodyRejectsOversizedKnownAndUnknownLengths(t *testing.T) {
	body := `{"start_datetime":"2025-01-02T03:04:05Z","padding":"` + strings.Repeat("x", maxRequestBodyBytes) + `"}`
	for _, unknownLength := range []bool{false, true} {
		name := "known content length"
		if unknownLength {
			name = "unknown content length"
		}
		t.Run(name, func(t *testing.T) {
			service := &requestValidationWalkService{}
			handler := requestValidationHandler(t, service)
			req := httptest.NewRequest(http.MethodPut, "/sessions/00000000-0000-4000-8000-000000000001", strings.NewReader(body))
			req.Header.Set("Content-Type", "application/json")
			if unknownLength {
				req.ContentLength = -1
				req.TransferEncoding = []string{"chunked"}
			}
			recorder := httptest.NewRecorder()
			handler.ServeHTTP(recorder, req)

			if recorder.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want %d; body = %q", recorder.Code, http.StatusBadRequest, recorder.Body.String())
			}
			assertJSONContentType(t, recorder)
			if !strings.Contains(recorder.Body.String(), `"code":"invalid_request"`) {
				t.Errorf("body = %q, want invalid_request response", recorder.Body.String())
			}
			if service.called {
				t.Fatal("oversized request reached the walk service")
			}
		})
	}
}

func TestValidateRequestBodyEnforcesExactByteBoundary(t *testing.T) {
	tests := []struct {
		name       string
		body       string
		wantStatus int
		wantCalled bool
	}{
		{name: "exact limit", body: `"` + strings.Repeat("x", maxRequestBodyBytes-2) + `"`, wantStatus: http.StatusNoContent, wantCalled: true},
		{name: "one byte over", body: `"` + strings.Repeat("x", maxRequestBodyBytes-1) + `"`, wantStatus: http.StatusBadRequest},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			called := false
			handler := ValidateRequestBody(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				called = true
				w.WriteHeader(http.StatusNoContent)
			}))
			req := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(test.body))
			req.Header.Set("Content-Type", "application/json")
			recorder := httptest.NewRecorder()

			handler.ServeHTTP(recorder, req)

			if recorder.Code != test.wantStatus {
				t.Fatalf("status = %d, want %d", recorder.Code, test.wantStatus)
			}
			if called != test.wantCalled {
				t.Errorf("downstream called = %t, want %t", called, test.wantCalled)
			}
		})
	}
}

func TestOpenAPIRequestValidationPreservesRouterMethodHandling(t *testing.T) {
	handler := requestValidationHandler(t, &requestValidationWalkService{})
	req := httptest.NewRequest(http.MethodPost, "/sessions/00000000-0000-4000-8000-000000000001", nil)
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusMethodNotAllowed)
	}
	if got := recorder.Header().Get("Allow"); got != http.MethodPut {
		t.Errorf("Allow = %q, want %q", got, http.MethodPut)
	}
}

func TestOpenAPIRequestValidationRejectsUnknownPath(t *testing.T) {
	handler := requestValidationHandler(t, &requestValidationWalkService{})
	req := httptest.NewRequest(http.MethodGet, "/unknown", nil)
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusNotFound)
	}
	assertJSONContentType(t, recorder)
}

func TestOpenAPIRequestValidationPreservesBodyForTypedHandlerDecoding(t *testing.T) {
	service := &requestValidationWalkService{}
	handler := requestValidationHandler(t, service)
	req := httptest.NewRequest(http.MethodPut, "/sessions/00000000-0000-4000-8000-000000000001", strings.NewReader(`{"start_datetime":"2025-01-02T03:04:05Z"}`))
	req.Header.Set("Content-Type", "application/json; charset=utf-8")
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want %d; body = %q", recorder.Code, http.StatusNoContent, recorder.Body.String())
	}
	if !service.called {
		t.Fatal("valid request did not reach the walk service")
	}
	if got, want := service.session.StartDatetime, time.Date(2025, time.January, 2, 3, 4, 5, 0, time.UTC); !got.Equal(want) {
		t.Errorf("StartDatetime = %s, want %s", got, want)
	}
}
