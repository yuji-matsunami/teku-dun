package httpapi

import (
	"net/http"

	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
)

// PutSteps stores or corrects a versioned steps interval.
func (h *Handler) PutSteps(w http.ResponseWriter, r *http.Request, sessionID, eventID string) {
	if !validUUID(sessionID) || !validUUID(eventID) {
		writeWalkBadRequest(w, "Path parameter is invalid.")
		return
	}
	if h.walk == nil {
		writeUnavailable(w)
		return
	}

	var request openapi.PutStepsJSONRequestBody
	if err := decodeWalkJSON(r, &request, "start_datetime", "end_datetime", "steps", "revision"); err != nil {
		writeWalkBadRequest(w, invalidRequestMessage)
		return
	}

	err := h.walk.PutSteps(r.Context(), walk.Steps{
		ID:            eventID,
		SessionID:     sessionID,
		StartDatetime: request.StartDatetime,
		EndDatetime:   request.EndDatetime,
		Steps:         request.Steps,
		Revision:      request.Revision,
	})
	if err != nil {
		writeWalkServiceError(w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
