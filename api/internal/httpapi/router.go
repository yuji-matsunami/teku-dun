package httpapi

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/yuji-matsunami/teku-dun/api/internal/openapi"
)

// NewRouterは、入力検証とOpenAPIのルーティングを組み合わせたAPIサーバーのHTTPハンドラーを生成する。
func NewRouter(h *Handler) (http.Handler, error) {
	requestValidator, err := NewOpenAPIRequestValidator()
	if err != nil {
		return nil, err
	}

	router := chi.NewRouter()
	router.Use(ValidateRequestBody, requestValidator)
	return openapi.HandlerFromMux(h, router), nil
}
