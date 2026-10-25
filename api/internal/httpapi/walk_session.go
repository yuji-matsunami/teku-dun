package httpapi

import (
	"net/http"

	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
)

// PutSession stores a walking session start time through the walk service.
func (h *Handler) PutSession(w http.ResponseWriter, r *http.Request, sessionID string) {
	if h.walk == nil {
		writeUnavailable(w)
		return
	}

	var request openapi.PutSessionJSONRequestBody
	if err := decodeWalkJSON(r, &request, "start_datetime"); err != nil {
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
