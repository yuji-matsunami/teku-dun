package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"

	"github.com/getkin/kin-openapi/routers"
	openapiMiddleware "github.com/oapi-codegen/nethttp-middleware"
	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
)

const maxRequestBodyBytes = 16 * 1024

// ValidateRequestBodyは、OpenAPI検証より先に本文の上限とJSON文書の形式を検証する。
// OpenAPI検証器が検出しないJSON末尾の余分な値も、ここで拒否する。
func ValidateRequestBody(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Body == nil || r.Body == http.NoBody {
			next.ServeHTTP(w, r)
			return
		}

		body, err := io.ReadAll(io.LimitReader(r.Body, maxRequestBodyBytes+1))
		_ = r.Body.Close()
		if err != nil || len(body) > maxRequestBodyBytes {
			writeWalkBadRequest(w, invalidRequestMessage)
			return
		}
		mediaType, _, _ := mime.ParseMediaType(r.Header.Get("Content-Type"))
		if mediaType == "application/json" && !json.Valid(body) {
			writeWalkBadRequest(w, invalidRequestMessage)
			return
		}

		r.Body = io.NopCloser(bytes.NewReader(body))
		next.ServeHTTP(w, r)
	})
}

// NewOpenAPIRequestValidatorは、埋め込まれたAPI定義から入力検証を生成する。
func NewOpenAPIRequestValidator() (func(http.Handler) http.Handler, error) {
	spec, err := openapi.GetSpec()
	if err != nil {
		return nil, err
	}

	return func(next http.Handler) http.Handler {
		return openapiMiddleware.OapiRequestValidatorWithOptions(spec, &openapiMiddleware.Options{
			DoNotValidateServers: true,
			ErrorHandlerWithOpts: func(_ context.Context, err error, w http.ResponseWriter, r *http.Request, opts openapiMiddleware.ErrorHandlerOpts) {
				// ルート自体が存在する場合はchiへ処理を戻し、405とAllowヘッダーを生成させる。
				if errors.Is(err, routers.ErrMethodNotAllowed) {
					next.ServeHTTP(w, r)
					return
				}
				if opts.StatusCode >= http.StatusInternalServerError || opts.StatusCode < http.StatusBadRequest {
					writeUnavailable(w)
					return
				}
				writeJSON(w, opts.StatusCode, walkError(invalidRequestCode, invalidRequestMessage))
			},
		})(next)
	}, nil
}
