package httpapi

import (
	"net/http"

	openapiRuntime "github.com/oapi-codegen/runtime"
	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
)

// PutSessionは、散歩セッションの開始時刻をサービスへ渡して保存する。
func (h *Handler) PutSession(w http.ResponseWriter, r *http.Request, sessionID string) {
	if h.walk == nil {
		writeUnavailable(w)
		return
	}

	var request openapi.PutSessionJSONRequestBody
	if err := openapiRuntime.BindJSONBody(r, &request); err != nil {
		writeWalkBadRequest(w, invalidRequestMessage)
		return
	}

	err := h.walk.PutSession(r.Context(), walk.Session{
		ID:            sessionID,
		StartDatetime: request.StartDatetime,
	})
	if err != nil {
		writeWalkServiceError(w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
