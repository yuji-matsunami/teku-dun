// Package config contains configuration loaded by the API process.
package config

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"time"
)

const (
	defaultAddress           = ":8080"
	defaultDatabaseURL       = "postgres://teku_dun:teku_dun@127.0.0.1:5432/teku_dun?sslmode=disable"
	defaultDBPingTimeout     = 2 * time.Second
	defaultReadHeaderTimeout = 5 * time.Second
	defaultReadTimeout       = 10 * time.Second
	defaultWriteTimeout      = 10 * time.Second
	defaultIdleTimeout       = 60 * time.Second
	defaultShutdownTimeout   = 5 * time.Second
)

// Config is the process configuration. DatabaseURL is intentionally never
// included in an API response or log message.
type Config struct {
	Address           string
	DatabaseURL       string
	DBPingTimeout     time.Duration
	ReadHeaderTimeout time.Duration
	ReadTimeout       time.Duration
	WriteTimeout      time.Duration
	IdleTimeout       time.Duration
	ShutdownTimeout   time.Duration
}

// Load reads configuration from environment variables and applies safe local
// defaults. The default database URL points at the local PostGIS compose
// service and is suitable for development only.
func Load() (Config, error) {
	cfg := Config{
		Address:           envOrDefault("API_ADDR", defaultAddress),
		DatabaseURL:       envOrDefault("DATABASE_URL", defaultDatabaseURL),
		DBPingTimeout:     defaultDBPingTimeout,
		ReadHeaderTimeout: defaultReadHeaderTimeout,
		ReadTimeout:       defaultReadTimeout,
		WriteTimeout:      defaultWriteTimeout,
		IdleTimeout:       defaultIdleTimeout,
		ShutdownTimeout:   defaultShutdownTimeout,
	}

	var err error
	if cfg.DBPingTimeout, err = durationFromEnv("DB_PING_TIMEOUT", cfg.DBPingTimeout); err != nil {
		return Config{}, err
	}
	if cfg.ReadHeaderTimeout, err = durationFromEnv("HTTP_READ_HEADER_TIMEOUT", cfg.ReadHeaderTimeout); err != nil {
		return Config{}, err
	}
	if cfg.ReadTimeout, err = durationFromEnv("HTTP_READ_TIMEOUT", cfg.ReadTimeout); err != nil {
		return Config{}, err
	}
	if cfg.WriteTimeout, err = durationFromEnv("HTTP_WRITE_TIMEOUT", cfg.WriteTimeout); err != nil {
		return Config{}, err
	}
	if cfg.IdleTimeout, err = durationFromEnv("HTTP_IDLE_TIMEOUT", cfg.IdleTimeout); err != nil {
		return Config{}, err
	}
	if cfg.ShutdownTimeout, err = durationFromEnv("SHUTDOWN_TIMEOUT", cfg.ShutdownTimeout); err != nil {
		return Config{}, err
	}
	if cfg.WriteTimeout <= cfg.DBPingTimeout {
		return Config{}, errors.New("HTTP_WRITE_TIMEOUT must be greater than DB_PING_TIMEOUT")
	}
	if strings.TrimSpace(cfg.Address) == "" {
		return Config{}, errors.New("API_ADDR must not be empty")
	}
	if strings.TrimSpace(cfg.DatabaseURL) == "" {
		return Config{}, errors.New("DATABASE_URL must not be empty")
	}

	return cfg, nil
}

func envOrDefault(name, fallback string) string {
	value, exists := os.LookupEnv(name)
	if !exists || value == "" {
		return fallback
	}
	return strings.TrimSpace(value)
}

func durationFromEnv(name string, fallback time.Duration) (time.Duration, error) {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback, nil
	}
	duration, err := time.ParseDuration(value)
	if err != nil || duration <= 0 {
		return 0, fmt.Errorf("%s must be a positive duration", name)
	}
	return duration, nil
}
