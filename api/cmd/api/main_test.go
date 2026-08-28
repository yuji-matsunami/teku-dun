package main

import (
	"context"
	"testing"
	"time"
)

func TestRunStopsOnContextCancellation(t *testing.T) {
	t.Setenv("API_ADDR", "127.0.0.1:0")
	t.Setenv("DATABASE_URL", "postgres://teku_dun:teku_dun@127.0.0.1:1/teku_dun?sslmode=disable")
	for _, name := range []string{
		"DB_PING_TIMEOUT",
		"HTTP_READ_HEADER_TIMEOUT",
		"HTTP_READ_TIMEOUT",
		"HTTP_WRITE_TIMEOUT",
		"HTTP_IDLE_TIMEOUT",
		"SHUTDOWN_TIMEOUT",
	} {
		t.Setenv(name, "")
	}

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- run(ctx)
	}()

	// ListenAndServeが待ち受けを開始してからキャンセル経路を確認する。
	// OSが選んだ一時ポートをテスト側で知る必要はない。
	time.Sleep(50 * time.Millisecond)
	cancel()

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("run() error = %v, want nil", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("run() did not stop after context cancellation")
	}
}
