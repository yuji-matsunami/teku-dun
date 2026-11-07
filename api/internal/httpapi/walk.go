package httpapi

import (
	"context"
	"errors"
	"net/http"

	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
)

const (
	invalidRequestCode    = "invalid_request"
	invalidRequestMessage = "Request is invalid."
	notFoundCode          = "not_found"
	notFoundMessage       = "Session not found."
	conflictCode          = "conflict"
	conflictMessage       = "Request conflicts with stored data."
)

// WalkServiceはHTTP層が必要とする歩行データ操作だけを定義する。
// 業務ルールや永続化の詳細はinternal/walkへ閉じ込める。
type WalkService interface {
	PutSession(context.Context, walk.Session) error
	PutLocation(context.Context, walk.Location) error
	PutSteps(context.Context, walk.Steps) error
}

func writeWalkBadRequest(w http.ResponseWriter, message string) {
	if message == "" {
		message = invalidRequestMessage
	}
	writeJSON(w, http.StatusBadRequest, walkError(invalidRequestCode, message))
}

func writeWalkServiceError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, walk.ErrInvalid):
		writeJSON(w, http.StatusBadRequest, walkError(invalidRequestCode, invalidRequestMessage))
	case errors.Is(err, walk.ErrNotFound):
		writeJSON(w, http.StatusNotFound, walkError(notFoundCode, notFoundMessage))
	case errors.Is(err, walk.ErrConflict):
		writeJSON(w, http.StatusConflict, walkError(conflictCode, conflictMessage))
	default:
		// Repositoryやドライバーの詳細をHTTP境界の外へ漏らさない。
		writeUnavailable(w)
	}
}

func walkError(code, message string) openapi.ErrorResponse {
	return openapi.ErrorResponse{Code: code, Message: message}
}
