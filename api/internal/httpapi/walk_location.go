package httpapi

import (
	"net/http"

	openapiRuntime "github.com/oapi-codegen/runtime"
	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
)

// PutLocationは、位置イベントを冪等に保存する。
func (h *Handler) PutLocation(w http.ResponseWriter, r *http.Request, sessionID, eventID string) {
	if h.walk == nil {
		writeUnavailable(w)
		return
	}

	var request openapi.PutLocationJSONRequestBody
	if err := openapiRuntime.BindJSONBody(r, &request); err != nil {
		writeWalkBadRequest(w, invalidRequestMessage)
		return
	}

	err := h.walk.PutLocation(r.Context(), walk.Location{
		ID:         eventID,
		SessionID:  sessionID,
		RecordedAt: request.RecordedAt,
		Latitude:   request.Latitude,
		Longitude:  request.Longitude,
		AccuracyM:  request.AccuracyM,
	})
	if err != nil {
		writeWalkServiceError(w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
