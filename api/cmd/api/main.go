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
		// run returns deliberately sanitized errors. In particular, do not log
		// DATABASE_URL or a raw database driver error here.
		log.Print(err)
		os.Exit(1)
	}
}

func run(parent context.Context) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("configuration error: %s", err)
	}

	poolConfig, err := pgxpool.ParseConfig(cfg.DatabaseURL)
	if err != nil {
		return errors.New("database configuration is invalid")
	}
	db, err := pgxpool.NewWithConfig(parent, poolConfig)
	if err != nil {
		return errors.New("database connection failed")
	}
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
		db.Close()
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return errors.New("HTTP server failed")
	case <-serverCtx.Done():
		shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
		defer cancelShutdown()
		if err := server.Shutdown(shutdownCtx); err != nil {
			db.Close()
			return errors.New("graceful shutdown failed")
		}
		db.Close()
		return nil
	}
}

// postGISChecker makes readiness verify the extension used by the API, rather
// than only checking that a PostgreSQL socket accepts connections.
type postGISChecker struct {
	pool *pgxpool.Pool
}

func (c postGISChecker) Ping(ctx context.Context) error {
	var version string
	return c.pool.QueryRow(ctx, "SELECT PostGIS_Version()").Scan(&version)
}
