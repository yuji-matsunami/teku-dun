// Package httpapi implements the HTTP endpoints exposed by the API.
package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
)

const (
	serviceUnavailableCode    = "service_unavailable"
	serviceUnavailableMessage = "Service is not ready."
)

// DBChecker is the small database contract required by readiness checks. The
// process supplies a pgxpool-backed PostGIS checker, while tests can provide a
// function adapter without opening a database connection.
type DBChecker interface {
	Ping(context.Context) error
}

// Handler implements the generated OpenAPI server interface.
type Handler struct {
	db          DBChecker
	pingTimeout time.Duration
}

// NewHandler constructs a health/readiness handler. A non-positive timeout is
// replaced with the same short default used by the process configuration.
func NewHandler(db DBChecker, pingTimeout time.Duration) *Handler {
	if pingTimeout <= 0 {
		pingTimeout = 2 * time.Second
	}
	return &Handler{db: db, pingTimeout: pingTimeout}
}

// GetHealthz reports process liveness without consulting any dependency.
func (h *Handler) GetHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, openapi.HealthResponse{Status: "ok"})
}

// GetReadyz reports whether the database is available. The underlying database
// error is deliberately not returned to callers because it can contain
// implementation details or connection information.
func (h *Handler) GetReadyz(w http.ResponseWriter, r *http.Request) {
	if h.db == nil {
		writeUnavailable(w)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), h.pingTimeout)
	defer cancel()
	if err := h.db.Ping(ctx); err != nil {
		writeUnavailable(w)
		return
	}

	writeJSON(w, http.StatusOK, openapi.ReadyResponse{Status: "ready"})
}

func writeUnavailable(w http.ResponseWriter) {
	writeJSON(w, http.StatusServiceUnavailable, openapi.ErrorResponse{
		Code:    serviceUnavailableCode,
		Message: serviceUnavailableMessage,
	})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	// All response values are local structs. If encoding ever fails, headers
	// have already been sent and there is no safe alternate response to write.
	_ = json.NewEncoder(w).Encode(value)
}
