package httpapi

import (
	"net/http"

	openapiRuntime "github.com/oapi-codegen/runtime"
	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
)

// PutStepsは、歩数区間をリビジョンに従って保存または補正する。
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
	if err := openapiRuntime.BindJSONBody(r, &request); err != nil {
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
