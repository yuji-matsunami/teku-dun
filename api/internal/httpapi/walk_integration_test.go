package httpapi

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
	walkpostgres "github.com/yuji-matsunami/teku-dun/api/internal/walk/postgres"
)

// 各テスト専用のスキーマを使う。TEST_DATABASE_URLには破棄可能なPostGISデータベースを指定する。
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
	applicationName := schema + "_http_api"
	cfg.ConnConfig.RuntimeParams["application_name"] = applicationName
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal("cannot create isolated test pool")
	}
	defer pool.Close()
	_, file, _, _ := runtime.Caller(0)
	migrations, err := filepath.Glob(filepath.Join(filepath.Dir(file), "../../../db/migrations/*.up.sql"))
	if err != nil {
		t.Fatal(err)
	}
	if len(migrations) == 0 {
		t.Fatal("no up migrations found")
	}
	sort.Strings(migrations)
	for _, migrationPath := range migrations {
		migration, err := os.ReadFile(migrationPath)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := pool.Exec(ctx, string(migration)); err != nil {
			t.Fatalf("apply migration %s: %v", filepath.Base(migrationPath), err)
		}
	}
	h := NewHandler(pool, time.Second).WithWalkService(walk.NewService(walkpostgres.NewRepository(pool)))
	validator, err := NewOpenAPIRequestValidator()
	if err != nil {
		t.Fatalf("create request validator: %v", err)
	}
	router := chi.NewRouter()
	router.Use(ValidateRequestBody, validator)
	openapi.HandlerFromMux(h, router)
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
	otherSession := "/sessions/10000000-0000-4000-8000-000000000002"
	missingSession := "/sessions/10000000-0000-4000-8000-000000000099"
	location := session + "/locations/20000000-0000-4000-8000-000000000001"
	steps := session + "/steps/30000000-0000-4000-8000-000000000001"
	var serverBefore time.Time
	if err := pool.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&serverBefore); err != nil {
		t.Fatal(err)
	}
	put(session, `{"start_datetime":"2026-01-01T10:00:20Z"}`, 204)
	var sessionReceived time.Time
	if err := pool.QueryRow(ctx, `SELECT received_at FROM walk_sessions WHERE id='10000000-0000-4000-8000-000000000001'`).Scan(&sessionReceived); err != nil {
		t.Fatal(err)
	}
	put(session, `{"start_datetime":"2026-01-01T19:00:20+09:00"}`, 204)
	var replayedSessionReceived time.Time
	if err := pool.QueryRow(ctx, `SELECT received_at FROM walk_sessions WHERE id='10000000-0000-4000-8000-000000000001'`).Scan(&replayedSessionReceived); err != nil {
		t.Fatal(err)
	}
	if !replayedSessionReceived.Equal(sessionReceived) {
		t.Fatal("session replay changed received_at")
	}
	put(session, `{"start_datetime":"2026-01-01T10:00:21Z"}`, 409)
	put(otherSession, `{"start_datetime":"2026-01-01T10:00:20Z"}`, 204)
	put(location, `{"recorded_at":"2026-01-01T10:00:30Z","latitude":35.5,"longitude":139.5,"accuracy_m":3}`, 204)
	var locationReceived time.Time
	if err := pool.QueryRow(ctx, `SELECT received_at FROM location_events WHERE id='20000000-0000-4000-8000-000000000001'`).Scan(&locationReceived); err != nil {
		t.Fatal(err)
	}
	put(location, `{"recorded_at":"2026-01-01T10:00:30Z","latitude":35.5,"longitude":139.5,"accuracy_m":3}`, 204)
	var replayedLocationReceived time.Time
	if err := pool.QueryRow(ctx, `SELECT received_at FROM location_events WHERE id='20000000-0000-4000-8000-000000000001'`).Scan(&replayedLocationReceived); err != nil {
		t.Fatal(err)
	}
	if !replayedLocationReceived.Equal(locationReceived) {
		t.Fatal("location replay changed received_at")
	}
	put(location, `{"recorded_at":"2026-01-01T10:00:30Z","latitude":35.6,"longitude":139.5,"accuracy_m":3}`, 409)
	put(otherSession+"/locations/20000000-0000-4000-8000-000000000001", `{"recorded_at":"2026-01-01T10:00:30Z","latitude":35.5,"longitude":139.5,"accuracy_m":3}`, 409)
	put(missingSession+"/locations/20000000-0000-4000-8000-000000000099", `{"recorded_at":"2026-01-01T10:00:30Z","latitude":35.5,"longitude":139.5,"accuracy_m":3}`, 404)
	put(location, `{"recorded_at":"2026-01-01T10:00:30Z","latitude":91,"longitude":139.5,"accuracy_m":3}`, 400)
	put(session+"/locations/20000000-0000-4000-8000-000000000002", `{"recorded_at":"2026-01-01T10:00:19Z","latitude":35.5,"longitude":139.5,"accuracy_m":3}`, 400)
	put(steps, `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":100,"revision":1}`, 204)
	var firstReceived, initialLastReceived time.Time
	if err := pool.QueryRow(ctx, `SELECT first_received_at, last_received_at FROM step_events WHERE id='30000000-0000-4000-8000-000000000001'`).Scan(&firstReceived, &initialLastReceived); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `SELECT pg_sleep(0.002)`); err != nil {
		t.Fatal(err)
	}
	put(steps, `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":90,"revision":2}`, 204)
	var correctedFirstReceived, correctedLastReceived time.Time
	if err := pool.QueryRow(ctx, `SELECT first_received_at, last_received_at FROM step_events WHERE id='30000000-0000-4000-8000-000000000001'`).Scan(&correctedFirstReceived, &correctedLastReceived); err != nil {
		t.Fatal(err)
	}
	if !correctedFirstReceived.Equal(firstReceived) || !correctedLastReceived.After(initialLastReceived) {
		t.Fatal("step correction did not preserve first_received_at and advance last_received_at")
	}
	if _, err := pool.Exec(ctx, `UPDATE step_events SET last_received_at='2000-01-01T00:00:00Z' WHERE id='30000000-0000-4000-8000-000000000001'`); err != nil {
		t.Fatal(err)
	}
	var sameRevisionLastReceived time.Time
	if err := pool.QueryRow(ctx, `SELECT last_received_at FROM step_events WHERE id='30000000-0000-4000-8000-000000000001'`).Scan(&sameRevisionLastReceived); err != nil {
		t.Fatal(err)
	}
	put(steps, `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":90,"revision":2}`, 204)
	var replayedCorrectionLastReceived time.Time
	if err := pool.QueryRow(ctx, `SELECT last_received_at FROM step_events WHERE id='30000000-0000-4000-8000-000000000001'`).Scan(&replayedCorrectionLastReceived); err != nil {
		t.Fatal(err)
	}
	if !replayedCorrectionLastReceived.Equal(sameRevisionLastReceived) {
		t.Fatal("same-revision step replay changed last_received_at")
	}
	if _, err := pool.Exec(ctx, `UPDATE step_events SET last_received_at=$1 WHERE id='30000000-0000-4000-8000-000000000001'`, correctedLastReceived); err != nil {
		t.Fatal(err)
	}
	put(steps, `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":100,"revision":1}`, 204)
	var staleFirstReceived, staleLastReceived time.Time
	if err := pool.QueryRow(ctx, `SELECT first_received_at, last_received_at FROM step_events WHERE id='30000000-0000-4000-8000-000000000001'`).Scan(&staleFirstReceived, &staleLastReceived); err != nil {
		t.Fatal(err)
	}
	if !staleFirstReceived.Equal(correctedFirstReceived) || !staleLastReceived.Equal(correctedLastReceived) {
		t.Fatal("stale step replay changed receive timestamps")
	}
	put(steps, `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":80,"revision":2}`, 409)
	assertConcurrentStepCorrections(t, ctx, admin, pool, router, applicationName, steps,
		`{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":98,"revision":4}`,
		`{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":95,"revision":3}`)
	put(steps, `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:19Z","steps":98,"revision":5}`, 409)
	put(location, `{"recorded_at":"2026-01-01T10:00:31Z","latitude":35.5,"longitude":139.5,"accuracy_m":3}`, 409)
	put(location, `{"recorded_at":"2026-01-01T10:00:30Z","latitude":35.5,"longitude":139.6,"accuracy_m":3}`, 409)
	put(location, `{"recorded_at":"2026-01-01T10:00:30Z","latitude":35.5,"longitude":139.5,"accuracy_m":4}`, 409)
	put(session+"/steps/30000000-0000-4000-8000-000000000002", `{"start_datetime":"2026-01-01T10:01:20Z","end_datetime":"2026-01-01T10:01:45Z","steps":0,"revision":1}`, 204)
	put(session+"/steps/30000000-0000-4000-8000-000000000003", `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":100,"revision":1}`, 409)
	put(session+"/steps/30000000-0000-4000-8000-000000000004", `{"start_datetime":"2026-01-01T10:01:21Z","end_datetime":"2026-01-01T10:01:45Z","steps":1,"revision":1}`, 400)
	put(session+"/steps/30000000-0000-4000-8000-000000000005", `{"start_datetime":"2026-01-01T10:02:20Z","end_datetime":"2026-01-01T10:03:20Z","revision":1}`, 400)
	put(session+"/steps/30000000-0000-4000-8000-000000000007", `{"start_datetime":"2026-01-01T10:00:19Z","end_datetime":"2026-01-01T10:01:19Z","steps":1,"revision":1}`, 400)
	put(otherSession+"/steps/30000000-0000-4000-8000-000000000001", `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":98,"revision":4}`, 409)
	put(missingSession+"/steps/30000000-0000-4000-8000-000000000099", `{"start_datetime":"2026-01-01T10:00:20Z","end_datetime":"2026-01-01T10:01:20Z","steps":1,"revision":1}`, 404)
	assertConcurrentInitialStepPut(t, ctx, admin, pool, router, applicationName,
		session+"/steps/30000000-0000-4000-8000-000000000006",
		`{"start_datetime":"2026-01-01T10:04:20Z","end_datetime":"2026-01-01T10:05:20Z","steps":42,"revision":1}`)
	var simultaneousCount int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM step_events WHERE id='30000000-0000-4000-8000-000000000006'`).Scan(&simultaneousCount); err != nil {
		t.Fatal(err)
	}
	if simultaneousCount != 1 {
		t.Fatalf("simultaneous initial step row count = %d, want 1", simultaneousCount)
	}
	var simultaneousSteps int32
	var simultaneousRevision int64
	if err := pool.QueryRow(ctx, `SELECT steps, revision FROM step_events WHERE id='30000000-0000-4000-8000-000000000006'`).Scan(&simultaneousSteps, &simultaneousRevision); err != nil {
		t.Fatal(err)
	}
	if simultaneousSteps != 42 || simultaneousRevision != 1 {
		t.Fatalf("simultaneous initial step = steps %d, revision %d; want 42, 1", simultaneousSteps, simultaneousRevision)
	}
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
	if count != 3 {
		t.Fatalf("step count = %d, want 3", count)
	}
	var serverAfter time.Time
	if err := pool.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&serverAfter); err != nil {
		t.Fatal(err)
	}
	for name, receivedAt := range map[string]time.Time{
		"session":    sessionReceived,
		"location":   locationReceived,
		"step first": firstReceived,
		"step last":  correctedLastReceived,
	} {
		if receivedAt.Before(serverBefore) || receivedAt.After(serverAfter) {
			t.Errorf("%s receive time %s is outside server request window [%s, %s]", name, receivedAt, serverBefore, serverAfter)
		}
	}
}

func assertConcurrentInitialStepPut(
	t *testing.T,
	ctx context.Context,
	admin, pool *pgxpool.Pool,
	router http.Handler,
	applicationName, path, body string,
) {
	t.Helper()

	lockTx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	lockHeld := true
	requestCtx, cancelRequests := context.WithTimeout(ctx, 10*time.Second)
	var requestsStarted bool
	requestsDone := make(chan struct{})
	defer func() {
		if lockHeld {
			_ = lockTx.Rollback(context.Background())
		}
		cancelRequests()
		if requestsStarted {
			select {
			case <-requestsDone:
			case <-time.After(5 * time.Second):
				t.Error("concurrent step requests did not stop after lock release and cancellation")
			}
		}
	}()
	if _, err := lockTx.Exec(ctx, `LOCK TABLE step_events IN SHARE ROW EXCLUSIVE MODE`); err != nil {
		t.Fatal(err)
	}

	startRequests := make(chan struct{})
	statuses := make(chan int, 2)
	var requests sync.WaitGroup
	for range 2 {
		requests.Add(1)
		go func() {
			defer requests.Done()
			<-startRequests
			req := httptest.NewRequest(http.MethodPut, path, strings.NewReader(body)).WithContext(requestCtx)
			req.Header.Set("Content-Type", "application/json")
			res := httptest.NewRecorder()
			router.ServeHTTP(res, req)
			statuses <- res.Code
		}()
	}
	requestsStarted = true
	go func() {
		requests.Wait()
		close(requestsDone)
	}()
	close(startRequests)

	pollCtx, cancelPoll := context.WithTimeout(requestCtx, 8*time.Second)
	err = waitForBlockedStepInserts(pollCtx, admin, applicationName)
	cancelPoll()
	if err != nil {
		t.Fatalf("waiting for both step inserts to block: %v", err)
	}
	if err := lockTx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	lockHeld = false

	for range 2 {
		select {
		case status := <-statuses:
			if status != http.StatusNoContent {
				t.Fatalf("concurrent initial step status = %d, want %d", status, http.StatusNoContent)
			}
		case <-requestCtx.Done():
			t.Fatalf("waiting for concurrent step responses: %v", requestCtx.Err())
		}
	}
	select {
	case <-requestsDone:
	case <-requestCtx.Done():
		t.Fatalf("waiting for concurrent step requests to finish: %v", requestCtx.Err())
	}
}

func waitForBlockedStepInserts(ctx context.Context, admin *pgxpool.Pool, applicationName string) error {
	ticker := time.NewTicker(20 * time.Millisecond)
	defer ticker.Stop()
	for {
		var blocked int
		if err := admin.QueryRow(ctx, `
			SELECT count(*)
			FROM pg_stat_activity
			WHERE application_name = $1
			  AND wait_event_type = 'Lock'
			  AND query ILIKE '%INSERT INTO step_events%'
		`, applicationName).Scan(&blocked); err != nil {
			return err
		}
		if blocked == 2 {
			return nil
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("timed out waiting for two blocked INSERTs; found %d: %w", blocked, ctx.Err())
		case <-ticker.C:
		}
	}
}

func assertConcurrentStepCorrections(
	t *testing.T,
	ctx context.Context,
	admin, pool *pgxpool.Pool,
	router http.Handler,
	applicationName, path, newerBody, olderBody string,
) {
	t.Helper()

	lockTx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	lockHeld := true
	requestCtx, cancelRequests := context.WithTimeout(ctx, 10*time.Second)
	var requests sync.WaitGroup
	statuses := make(chan struct {
		revision int
		status   int
	}, 2)
	defer func() {
		if lockHeld {
			_ = lockTx.Rollback(context.Background())
		}
		cancelRequests()
		requestsDone := make(chan struct{})
		go func() {
			requests.Wait()
			close(requestsDone)
		}()
		select {
		case <-requestsDone:
		case <-time.After(5 * time.Second):
			t.Error("concurrent step correction requests did not stop after lock release and cancellation")
		}
	}()

	var lockedID string
	if err := lockTx.QueryRow(ctx, `SELECT id FROM step_events WHERE id='30000000-0000-4000-8000-000000000001' FOR UPDATE`).Scan(&lockedID); err != nil {
		t.Fatal(err)
	}
	startCorrection := func(revision int, body string) {
		requests.Add(1)
		go func() {
			defer requests.Done()
			req := httptest.NewRequest(http.MethodPut, path, strings.NewReader(body)).WithContext(requestCtx)
			req.Header.Set("Content-Type", "application/json")
			res := httptest.NewRecorder()
			router.ServeHTTP(res, req)
			statuses <- struct {
				revision int
				status   int
			}{revision: revision, status: res.Code}
		}()
	}

	startCorrection(4, newerBody)
	pollCtx, cancelPoll := context.WithTimeout(requestCtx, 8*time.Second)
	err = waitForBlockedStepQueries(pollCtx, admin, applicationName, 1)
	cancelPoll()
	if err != nil {
		t.Fatalf("waiting for revision 4 step query to block: %v", err)
	}

	startCorrection(3, olderBody)
	pollCtx, cancelPoll = context.WithTimeout(requestCtx, 8*time.Second)
	err = waitForBlockedStepQueries(pollCtx, admin, applicationName, 2)
	cancelPoll()
	if err != nil {
		t.Fatalf("waiting for revisions 4 and 3 step queries to block: %v", err)
	}

	if err := lockTx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	lockHeld = false

	for range 2 {
		select {
		case result := <-statuses:
			if result.status != http.StatusNoContent {
				t.Fatalf("revision %d concurrent correction status = %d, want %d", result.revision, result.status, http.StatusNoContent)
			}
		case <-requestCtx.Done():
			t.Fatalf("waiting for concurrent correction responses: %v", requestCtx.Err())
		}
	}
}

func waitForBlockedStepQueries(ctx context.Context, admin *pgxpool.Pool, applicationName string, want int) error {
	ticker := time.NewTicker(20 * time.Millisecond)
	defer ticker.Stop()
	for {
		var blocked int
		if err := admin.QueryRow(ctx, `
			SELECT count(*)
			FROM pg_stat_activity
			WHERE application_name = $1
			  AND wait_event_type = 'Lock'
			  AND (query ILIKE '%FROM step_events%' OR query ILIKE '%UPDATE step_events%')
		`, applicationName).Scan(&blocked); err != nil {
			return err
		}
		if blocked == want {
			return nil
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("timed out waiting for %d blocked step queries; found %d: %w", want, blocked, ctx.Err())
		case <-ticker.C:
		}
	}
}
