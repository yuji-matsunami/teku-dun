package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"regexp"
	"strings"

	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
	"github.com/yuji-matsunami/teku-dun/api/internal/walk"
)

const (
	maxWalkBodyBytes = 16 * 1024

	invalidRequestCode    = "invalid_request"
	invalidRequestMessage = "Request is invalid."
	notFoundCode          = "not_found"
	notFoundMessage       = "Session not found."
	conflictCode          = "conflict"
	conflictMessage       = "Request conflicts with stored data."
)

var canonicalUUID = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// WalkServiceはHTTP層が必要とする歩行データ操作だけを定義する。
// 業務ルールや永続化の詳細はinternal/walkへ閉じ込める。
type WalkService interface {
	PutSession(context.Context, walk.Session) error
	PutLocation(context.Context, walk.Location) error
	PutSteps(context.Context, walk.Steps) error
}

// decodeWalkJSONは歩行API共通のJSON境界を検証して、生成された入力型へ変換する。
// oapi-codegenのchiラッパーはbodyを自動で読み込まないため、ここでHTTP固有の
// 制約を一箇所に集約する。requiredの値はJSONの値として0やfalseを許可する。
func decodeWalkJSON(r *http.Request, dst any, required ...string) error {
	if r.Body == nil {
		return errors.New("request body is missing")
	}

	contentType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || !strings.EqualFold(contentType, "application/json") {
		return errors.New("content type must be application/json")
	}
	if r.ContentLength > maxWalkBodyBytes {
		return errors.New("request body is too large")
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, maxWalkBodyBytes+1))
	if err != nil {
		return errors.New("request body could not be read")
	}
	if len(body) > maxWalkBodyBytes {
		return errors.New("request body is too large")
	}

	var fields map[string]json.RawMessage
	decoder := json.NewDecoder(bytes.NewReader(body))
	if err := decoder.Decode(&fields); err != nil {
		return errors.New("request body is not a JSON object")
	}
	if fields == nil {
		return errors.New("request body is not a JSON object")
	}
	if err := rejectTrailingJSON(decoder); err != nil {
		return err
	}

	allowed := make(map[string]struct{}, len(required))
	for _, name := range required {
		allowed[name] = struct{}{}
		value, ok := fields[name]
		if !ok || bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return fmt.Errorf("required field %q is missing", name)
		}
	}
	for name := range fields {
		if _, ok := allowed[name]; !ok {
			return fmt.Errorf("unknown field %q", name)
		}
	}

	decoder = json.NewDecoder(bytes.NewReader(body))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(dst); err != nil {
		return errors.New("request body has an invalid value")
	}
	if err := rejectTrailingJSON(decoder); err != nil {
		return err
	}
	return nil
}

func rejectTrailingJSON(decoder *json.Decoder) error {
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		if err == nil {
			return errors.New("request body has trailing JSON")
		}
		return errors.New("request body has trailing data")
	}
	return nil
}

func validUUID(value string) bool {
	if !canonicalUUID.MatchString(value) {
		return false
	}
	for _, character := range value {
		if character != '-' && character != '0' {
			return true
		}
	}
	return false
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
		// Repository and driver details must never cross the HTTP boundary.
		writeUnavailable(w)
	}
}

func walkError(code, message string) openapi.ErrorResponse {
	return openapi.ErrorResponse{Code: code, Message: message}
}
