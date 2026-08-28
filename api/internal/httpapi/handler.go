// Package httpapi はAPIが公開するHTTPエンドポイントを実装する。
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

// DBCheckerはreadiness確認に必要な最小限のDB操作を定義する。
// 本番ではPostGISを確認し、テストではDB接続なしの実装へ差し替える。
type DBChecker interface {
	Ping(context.Context) error
}

// HandlerはOpenAPIから生成されたサーバーインターフェースを実装する。
type Handler struct {
	db          DBChecker
	pingTimeout time.Duration
}

// NewHandlerは検証済みの設定とDB依存を受け取り、health/readinessハンドラーを生成する。
func NewHandler(db DBChecker, pingTimeout time.Duration) *Handler {
	return &Handler{db: db, pingTimeout: pingTimeout}
}

// GetHealthzは外部依存を確認せず、プロセスの稼働状態を返す。
func (h *Handler) GetHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, openapi.HealthResponse{Status: "ok"})
}

// GetReadyzはDBが利用可能かを返す。接続情報を含む可能性があるため、
// DBの生のエラーはレスポンスへ含めない。
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
	// 値はローカルで組み立てた構造体に限る。エンコード失敗時はヘッダー送信済みのため、
	// 代替レスポンスを安全に書き込めない。
	_ = json.NewEncoder(w).Encode(value)
}
