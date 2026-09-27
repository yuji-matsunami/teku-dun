package httpapi

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
	walkpostgres "github.com/yuji-matsunami/teku-dun/api/internal/walk/postgres"
)

// Each test owns its schema; TEST_DATABASE_URL must point to a disposable PostGIS database.
func TestWalkHTTPPostGIS(t *testing.T) {
	databaseURL := os.Getenv("TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("set TEST_DATABASE_URL to run PostGIS integration tests")
	}
	ctx := context.Background()
	admin, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		t.Fatal("cannot create test database pool")
	}
	defer admin.Close()
	schema := fmt.Sprintf("walk_http_%d", time.Now().UnixNano())
	if _, err := admin.Exec(ctx, "CREATE SCHEMA "+schema); err != nil {
		t.Fatal(err)
	}
	defer func() {
		if _, err := admin.Exec(ctx, "DROP SCHEMA "+schema+" CASCADE"); err != nil {
			t.Error(err)
		}
	}()
	cfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		t.Fatal("invalid TEST_DATABASE_URL")
	}
	cfg.ConnConfig.RuntimeParams["search_path"] = schema + ",public"
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal("cannot create isolated test pool")
	}
	defer pool.Close()
	_, file, _, _ := runtime.Caller(0)
	migration, err := os.ReadFile(filepath.Join(filepath.Dir(file), "../../../db/migrations/000002_walk_events.up.sql"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, string(migration)); err != nil {
		t.Fatal(err)
	}
	h := NewHandler(pool, time.Second).WithWalkService(walk.NewService(walkpostgres.NewRepository(pool)))
	router := openapi.Handler(h)
	put := func(path, body string, want int) {
		t.Helper()
		req := httptest.NewRequest(http.MethodPut, path, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		res := httptest.NewRecorder()
		router.ServeHTTP(res, req)
		if res.Code != want {
			t.Fatalf("PUT %s: got %d (%s), want %d", path, res.Code, res.Body.String(), want)
		}
		if want == http.StatusNoContent && res.Body.Len() != 0 {
			t.Fatal("204 response must be empty")
		}
	}
	session := "/sessions/10000000-0000-4000-8000-000000000001"
	location := session + "/locations/20000000-0000-4000-8000-000000000001"
	steps := session + "/steps/30000000-0000-4000-8000-000000000001"
	put(session, `{"start_datetime":"2026-01-01T10:00:20Z"}`, 204)
	put(session, `{"start_datetime":"2026-01-01T19:00:20+09:00"}`, 204)
	put(location, `{"recorded_at":"2026-01-01T10:00:30Z","latitude":35.5,"longitude":139.5,"accuracy_m":3}`, 204)
	put(location, `{"recorded_at":"2026-01-01T10:00:30Z","latitude":35.5,"longitude":139.5,"accuracy_m":3}`, 204)
	put(location, `{"recorded_at":"2026-01-01T10:00:30Z","latitude":91,"longitude":139.5,"accuracy_m":3}`, 400)
	put(steps, `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":100,"revision":1}`, 204)
	put(steps, `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":90,"revision":2}`, 204)
	put(steps, `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":100,"revision":1}`, 204)
	put(steps, `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":80,"revision":2}`, 409)
	var corrections sync.WaitGroup
	correctionStatuses := make(chan int, 2)
	for _, body := range []string{
		`{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":95,"revision":3}`,
		`{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":98,"revision":4}`,
	} {
		corrections.Add(1)
		go func(body string) {
			defer corrections.Done()
			req := httptest.NewRequest(http.MethodPut, steps, strings.NewReader(body))
			req.Header.Set("Content-Type", "application/json")
			res := httptest.NewRecorder()
			router.ServeHTTP(res, req)
			correctionStatuses <- res.Code
		}(body)
	}
	corrections.Wait()
	close(correctionStatuses)
	for status := range correctionStatuses {
		if status != http.StatusNoContent {
			t.Fatalf("concurrent correction status = %d, want %d", status, http.StatusNoContent)
		}
	}
	put(session+"/steps/30000000-0000-4000-8000-000000000002", `{"start_datetime":"2026-01-01T10:01:20Z","end_datetime":"2026-01-01T10:01:45Z","steps":0,"revision":1}`, 204)
	put(session+"/steps/30000000-0000-4000-8000-000000000003", `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":100,"revision":1}`, 409)
	put(session+"/steps/30000000-0000-4000-8000-000000000004", `{"start_datetime":"2026-01-01T10:01:21Z","end_datetime":"2026-01-01T10:01:45Z","steps":1,"revision":1}`, 400)
	put(session+"/steps/30000000-0000-4000-8000-000000000005", `{"start_datetime":"2026-01-01T10:02:20Z","end_datetime":"2026-01-01T10:03:20Z","revision":1}`, 400)
	var count, srid int
	var latitude, longitude float64
	var recorded, received time.Time
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM location_events`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("location count = %d", count)
	}
	if err := pool.QueryRow(ctx, `SELECT ST_SRID(position::geometry), ST_Y(position::geometry), ST_X(position::geometry), recorded_at, received_at FROM location_events`).Scan(&srid, &latitude, &longitude, &recorded, &received); err != nil {
		t.Fatal(err)
	}
	if srid != 4326 || latitude != 35.5 || longitude != 139.5 || !received.After(recorded) {
		t.Fatalf("incorrect spatial or timestamp persistence: %d, %v, %v", srid, latitude, longitude)
	}
	var storedSteps int32
	var revision int64
	if err := pool.QueryRow(ctx, `SELECT steps, revision FROM step_events WHERE id='30000000-0000-4000-8000-000000000001'`).Scan(&storedSteps, &revision); err != nil {
		t.Fatal(err)
	}
	if storedSteps != 98 || revision != 4 {
		t.Fatalf("stale retry overwrote correction: steps=%d revision=%d", storedSteps, revision)
	}
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM step_events`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 2 {
		t.Fatalf("step count = %d", count)
	}
}
