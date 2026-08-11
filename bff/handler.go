package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"time"
)

const (
	upstreamURL    = "https://api.deepseek.com/v1/chat/completions"
	maxBodySize    = 64 * 1024 // 64 KB
	requestTimeout = 180 * time.Second
)

type Proxy struct {
	APIKey    string
	AppTokens map[string]string // token -> app label (e.g. "zhiji", "cycle", "nvc")
}

func (p *Proxy) HandleCompletions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	// Authenticate
	token := r.Header.Get("X-App-Token")
	appLabel, ok := p.AppTokens[token]
	if !ok || token == "" {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	// Read request body with size limit
	body, err := io.ReadAll(io.LimitReader(r.Body, maxBodySize+1))
	if err != nil {
		http.Error(w, `{"error":"failed to read request body"}`, http.StatusBadRequest)
		return
	}
	if len(body) > maxBodySize {
		http.Error(w, `{"error":"request body too large"}`, http.StatusRequestEntityTooLarge)
		return
	}

	// Peek at "stream" field to decide response handling
	isStream := peekStream(body)
	log.Printf("app=%s stream=%t bytes=%d", appLabel, isStream, len(body))

	// Build upstream request
	ctx := r.Context()
	upReq, err := http.NewRequestWithContext(ctx, http.MethodPost, upstreamURL, bytes.NewReader(body))
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	upReq.Header.Set("Content-Type", "application/json")
	upReq.Header.Set("Authorization", "Bearer "+p.APIKey)

	// Send upstream
	client := &http.Client{Timeout: requestTimeout}
	upResp, err := client.Do(upReq)
	if err != nil {
		log.Printf("upstream error: %v", err)
		http.Error(w, `{"error":"upstream request failed"}`, http.StatusBadGateway)
		return
	}
	defer upResp.Body.Close()

	if !isStream {
		// Non-streaming: relay JSON response
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(upResp.StatusCode)
		io.Copy(w, upResp.Body)
		return
	}

	// Streaming: relay SSE
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, `{"error":"streaming not supported"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(upResp.StatusCode)

	scanner := bufio.NewScanner(upResp.Body)
	// Increase scanner buffer for potentially large SSE lines
	scanner.Buffer(make([]byte, 0, 64*1024), 64*1024)
	for scanner.Scan() {
		line := scanner.Bytes()
		w.Write(line)
		w.Write([]byte("\n"))
		flusher.Flush()
	}
	if err := scanner.Err(); err != nil {
		log.Printf("stream relay error: %v", err)
	}
}

// peekStream checks if the JSON body contains "stream":true without full parsing.
func peekStream(body []byte) bool {
	var peek struct {
		Stream bool `json:"stream"`
	}
	if err := json.Unmarshal(body, &peek); err != nil {
		return false
	}
	return peek.Stream
}
