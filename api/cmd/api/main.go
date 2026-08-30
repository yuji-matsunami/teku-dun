package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yuji-matsunami/teku-dun/api/internal/config"
	"github.com/yuji-matsunami/teku-dun/api/internal/httpapi"
	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
)

func main() {
	if err := run(context.Background()); err != nil {
		// runは機密情報を除いたエラーだけを返す。DATABASE_URLやDBドライバーの
		// 生のエラーはここでログに出さない。
		log.Print(err)
		os.Exit(1)
	}
}

func run(parent context.Context) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("configuration error: %s", err)
	}

	db, err := newPostgresPool(parent, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer db.Close()
	postGIS := postGISChecker{pool: db}

	router := chi.NewRouter()
	openapi.HandlerFromMux(httpapi.NewHandler(postGIS, cfg.DBPingTimeout), router)
	server := &http.Server{
		Addr:              cfg.Address,
		Handler:           router,
		ReadHeaderTimeout: cfg.ReadHeaderTimeout,
		ReadTimeout:       cfg.ReadTimeout,
		WriteTimeout:      cfg.WriteTimeout,
		IdleTimeout:       cfg.IdleTimeout,
	}

	serverCtx, stop := signal.NotifyContext(parent, os.Interrupt, syscall.SIGTERM)
	defer stop()
	serverErrors := make(chan error, 1)
	go func() {
		serverErrors <- server.ListenAndServe()
	}()

	select {
	case err := <-serverErrors:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return errors.New("HTTP server failed")
	case <-serverCtx.Done():
		shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
		defer cancelShutdown()
		if err := server.Shutdown(shutdownCtx); err != nil {
			return errors.New("graceful shutdown failed")
		}
		return nil
	}
}

func newPostgresPool(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
	poolConfig, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, errors.New("database configuration is invalid")
	}

	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return nil, errors.New("database pool creation failed")
	}

	return pool, nil
}

// postGISCheckerはPostgreSQLへの接続だけでなく、APIが利用するPostGISも確認する。
type postGISChecker struct {
	pool *pgxpool.Pool
}

func (c postGISChecker) Ping(ctx context.Context) error {
	var version string
	return c.pool.QueryRow(ctx, "SELECT PostGIS_Version()").Scan(&version)
}
