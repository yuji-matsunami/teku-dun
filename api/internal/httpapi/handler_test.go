package httpapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
)

type checkerFunc func(context.Context) error

func (f checkerFunc) Ping(ctx context.Context) error {
	return f(ctx)
}

func TestGetHealthz(t *testing.T) {
	h := NewHandler(checkerFunc(func(context.Context) error {
		t.Fatal("healthz must not check the database")
		return nil
	}), time.Second)
	recorder := httptest.NewRecorder()
	h.GetHealthz(recorder, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusOK)
	}
	assertJSONContentType(t, recorder)
	if got, want := recorder.Body.String(), "{\"status\":\"ok\"}\n"; got != want {
		t.Errorf("body = %q, want %q", got, want)
	}
}

func TestGetReadyzSuccess(t *testing.T) {
	called := false
	h := NewHandler(checkerFunc(func(ctx context.Context) error {
		called = true
		if _, ok := ctx.Deadline(); !ok {
			t.Error("readiness context has no deadline")
		}
		return nil
	}), time.Second)
	recorder := httptest.NewRecorder()
	h.GetReadyz(recorder, httptest.NewRequest(http.MethodGet, "/readyz", nil))

	if !called {
		t.Fatal("readiness did not check the database")
	}
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusOK)
	}
	assertJSONContentType(t, recorder)
	if got, want := recorder.Body.String(), "{\"status\":\"ready\"}\n"; got != want {
		t.Errorf("body = %q, want %q", got, want)
	}
}

func TestGetReadyzFailureDoesNotExposeDatabaseError(t *testing.T) {
	secret := "postgres://user:secret-password@db.example.test:5432/teku_dun"
	h := NewHandler(checkerFunc(func(context.Context) error {
		return errors.New(secret)
	}), time.Second)
	recorder := httptest.NewRecorder()
	h.GetReadyz(recorder, httptest.NewRequest(http.MethodGet, "/readyz", nil))

	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusServiceUnavailable)
	}
	assertJSONContentType(t, recorder)
	body := recorder.Body.String()
	if strings.Contains(body, secret) || strings.Contains(body, "secret-password") {
		t.Fatalf("response exposes database error: %q", body)
	}
	if want := "{\"code\":\"service_unavailable\",\"message\":\"Service is not ready.\"}\n"; body != want {
		t.Errorf("body = %q, want %q", body, want)
	}
}

func TestGetReadyzNilChecker(t *testing.T) {
	h := NewHandler(nil, time.Second)
	recorder := httptest.NewRecorder()
	h.GetReadyz(recorder, httptest.NewRequest(http.MethodGet, "/readyz", nil))

	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusServiceUnavailable)
	}
}

func TestGetReadyzHonorsRequestCancellation(t *testing.T) {
	started := make(chan struct{})
	finished := make(chan struct{})
	h := NewHandler(checkerFunc(func(ctx context.Context) error {
		close(started)
		<-ctx.Done()
		close(finished)
		return ctx.Err()
	}), time.Minute)
	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	requestCtx, cancel := context.WithCancel(req.Context())
	req = req.WithContext(requestCtx)
	recorder := httptest.NewRecorder()

	done := make(chan struct{})
	go func() {
		h.GetReadyz(recorder, req)
		close(done)
	}()
	<-started
	cancel()
	select {
	case <-finished:
	case <-time.After(time.Second):
		t.Fatal("checker did not observe request cancellation")
	}
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("handler did not return after request cancellation")
	}
	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusServiceUnavailable)
	}
}

func assertJSONContentType(t *testing.T, recorder *httptest.ResponseRecorder) {
	t.Helper()
	if got, want := recorder.Header().Get("Content-Type"), "application/json"; got != want {
		t.Errorf("Content-Type = %q, want %q", got, want)
	}
}

var _ openapi.ServerInterface = (*Handler)(nil)
