package config

import (
	"testing"
	"time"
)

func TestLoadDefaults(t *testing.T) {
	for _, name := range []string{
		"API_ADDR",
		"DATABASE_URL",
		"DB_PING_TIMEOUT",
		"HTTP_READ_HEADER_TIMEOUT",
		"HTTP_READ_TIMEOUT",
		"HTTP_WRITE_TIMEOUT",
		"HTTP_IDLE_TIMEOUT",
		"SHUTDOWN_TIMEOUT",
	} {
		t.Setenv(name, "")
	}

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Address != defaultAddress {
		t.Errorf("Address = %q, want %q", cfg.Address, defaultAddress)
	}
	if cfg.DatabaseURL != defaultDatabaseURL {
		t.Errorf("DatabaseURL = %q, want local default", cfg.DatabaseURL)
	}
	if cfg.DBPingTimeout != defaultDBPingTimeout {
		t.Errorf("DBPingTimeout = %s, want %s", cfg.DBPingTimeout, defaultDBPingTimeout)
	}
	if cfg.ReadHeaderTimeout != defaultReadHeaderTimeout {
		t.Errorf("ReadHeaderTimeout = %s, want %s", cfg.ReadHeaderTimeout, defaultReadHeaderTimeout)
	}
	if cfg.ReadTimeout != defaultReadTimeout {
		t.Errorf("ReadTimeout = %s, want %s", cfg.ReadTimeout, defaultReadTimeout)
	}
	if cfg.WriteTimeout != defaultWriteTimeout {
		t.Errorf("WriteTimeout = %s, want %s", cfg.WriteTimeout, defaultWriteTimeout)
	}
	if cfg.IdleTimeout != defaultIdleTimeout {
		t.Errorf("IdleTimeout = %s, want %s", cfg.IdleTimeout, defaultIdleTimeout)
	}
	if cfg.ShutdownTimeout != defaultShutdownTimeout {
		t.Errorf("ShutdownTimeout = %s, want %s", cfg.ShutdownTimeout, defaultShutdownTimeout)
	}
}

func TestLoadEnvironment(t *testing.T) {
	t.Setenv("API_ADDR", "127.0.0.1:9090")
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/db?sslmode=disable")
	t.Setenv("DB_PING_TIMEOUT", "750ms")
	t.Setenv("HTTP_READ_HEADER_TIMEOUT", "3s")
	t.Setenv("HTTP_READ_TIMEOUT", "4s")
	t.Setenv("HTTP_WRITE_TIMEOUT", "5s")
	t.Setenv("HTTP_IDLE_TIMEOUT", "6s")
	t.Setenv("SHUTDOWN_TIMEOUT", "9s")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Address != "127.0.0.1:9090" || cfg.DatabaseURL == "" {
		t.Fatalf("environment values were not loaded: %+v", cfg)
	}
	if cfg.DBPingTimeout != 750*time.Millisecond {
		t.Errorf("DBPingTimeout = %s, want 750ms", cfg.DBPingTimeout)
	}
	if cfg.ReadHeaderTimeout != 3*time.Second {
		t.Errorf("ReadHeaderTimeout = %s, want 3s", cfg.ReadHeaderTimeout)
	}
	if cfg.ReadTimeout != 4*time.Second {
		t.Errorf("ReadTimeout = %s, want 4s", cfg.ReadTimeout)
	}
	if cfg.WriteTimeout != 5*time.Second {
		t.Errorf("WriteTimeout = %s, want 5s", cfg.WriteTimeout)
	}
	if cfg.IdleTimeout != 6*time.Second {
		t.Errorf("IdleTimeout = %s, want 6s", cfg.IdleTimeout)
	}
	if cfg.ShutdownTimeout != 9*time.Second {
		t.Errorf("ShutdownTimeout = %s, want 9s", cfg.ShutdownTimeout)
	}
}

func TestLoadRejectsInvalidDuration(t *testing.T) {
	for _, test := range []struct {
		name string
		env  string
	}{
		{name: "DB ping", env: "DB_PING_TIMEOUT"},
		{name: "read header", env: "HTTP_READ_HEADER_TIMEOUT"},
		{name: "read", env: "HTTP_READ_TIMEOUT"},
		{name: "write", env: "HTTP_WRITE_TIMEOUT"},
		{name: "idle", env: "HTTP_IDLE_TIMEOUT"},
		{name: "shutdown", env: "SHUTDOWN_TIMEOUT"},
	} {
		t.Run(test.name, func(t *testing.T) {
			t.Setenv(test.env, "not-a-duration")

			_, err := Load()
			if err == nil {
				t.Fatal("Load() error = nil, want invalid duration error")
			}
			want := test.env + " must be a positive duration"
			if got := err.Error(); got != want {
				t.Errorf("error = %q, want %q", got, want)
			}
		})
	}
}

func TestLoadRejectsEmptyAddress(t *testing.T) {
	t.Setenv("API_ADDR", "   ")

	_, err := Load()
	if err == nil {
		t.Fatal("Load() error = nil, want empty address error")
	}
	if got, want := err.Error(), "API_ADDR must not be empty"; got != want {
		t.Errorf("error = %q, want %q", got, want)
	}
}

func TestLoadRejectsWriteTimeoutNotGreaterThanDBPingTimeout(t *testing.T) {
	for _, test := range []struct {
		name  string
		write string
	}{
		{name: "equal", write: "2s"},
		{name: "less", write: "1s"},
	} {
		t.Run(test.name, func(t *testing.T) {
			t.Setenv("DB_PING_TIMEOUT", "2s")
			t.Setenv("HTTP_WRITE_TIMEOUT", test.write)

			_, err := Load()
			if err == nil {
				t.Fatal("Load() error = nil, want timeout ordering error")
			}
			if got, want := err.Error(), "HTTP_WRITE_TIMEOUT must be greater than DB_PING_TIMEOUT"; got != want {
				t.Errorf("error = %q, want %q", got, want)
			}
		})
	}
}

func TestLoadAcceptsWriteTimeoutGreaterThanDBPingTimeout(t *testing.T) {
	t.Setenv("DB_PING_TIMEOUT", "2s")
	t.Setenv("HTTP_WRITE_TIMEOUT", "3s")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.WriteTimeout != 3*time.Second {
		t.Errorf("WriteTimeout = %s, want 3s", cfg.WriteTimeout)
	}
}
