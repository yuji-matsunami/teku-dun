package httpapi

import (
	"net/http"

	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
)

// PutLocation stores or replays an immutable location event.
func (h *Handler) PutLocation(w http.ResponseWriter, r *http.Request, sessionID, eventID string) {
	if !validUUID(sessionID) || !validUUID(eventID) {
		writeWalkBadRequest(w, "Path parameter is invalid.")
		return
	}
	if h.walk == nil {
		writeUnavailable(w)
		return
	}

	var request openapi.PutLocationJSONRequestBody
	if err := decodeWalkJSON(r, &request, "recorded_at", "latitude", "longitude", "accuracy_m"); err != nil {
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
