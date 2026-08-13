package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

const (
	upstreamURL              = "https://api.deepseek.com/v1/chat/completions"
	maxBodySize              = 64 * 1024 // 64 KB
	requestTimeout           = 180 * time.Second
	defaultUnauthRatePerMin  = 12
	unauthRateWindowDuration = time.Minute
)

type Proxy struct {
	APIKey               string
	AppTokens            map[string]string // token -> app label (e.g. "zhiji", "cycle", "nvc")
	AllowUnauthenticated bool
	UnauthRatePerMinute  int

	mu           sync.Mutex
	unauthCounts map[string]rateCounter
}

type rateCounter struct {
	windowStart time.Time
	count       int
}

func (p *Proxy) HandleCompletions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	// Authenticate. Static app tokens are optional only when explicitly enabled for
	// TestFlight/public clients; unauthenticated traffic is rate-limited by IP.
	token := r.Header.Get("X-App-Token")
	appLabel, ok := p.AppTokens[token]
	if !ok || token == "" {
		if !p.AllowUnauthenticated {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		clientIP := clientIPFromRequest(r)
		if !p.allowUnauthenticatedRequest(clientIP) {
			http.Error(w, `{"error":"rate limited"}`, http.StatusTooManyRequests)
			return
		}
		appLabel = "unauthenticated:" + clientIP
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

func clientIPFromRequest(r *http.Request) string {
	if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
		parts := strings.Split(forwarded, ",")
		if ip := strings.TrimSpace(parts[0]); ip != "" {
			return ip
		}
	}
	if realIP := strings.TrimSpace(r.Header.Get("X-Real-IP")); realIP != "" {
		return realIP
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil && host != "" {
		return host
	}
	return r.RemoteAddr
}

func (p *Proxy) allowUnauthenticatedRequest(clientIP string) bool {
	limit := p.UnauthRatePerMinute
	if limit <= 0 {
		limit = defaultUnauthRatePerMin
	}
	now := time.Now()

	p.mu.Lock()
	defer p.mu.Unlock()
	if p.unauthCounts == nil {
		p.unauthCounts = map[string]rateCounter{}
	}
	counter := p.unauthCounts[clientIP]
	if now.Sub(counter.windowStart) >= unauthRateWindowDuration {
		counter = rateCounter{windowStart: now}
	}
	if counter.count >= limit {
		p.unauthCounts[clientIP] = counter
		return false
	}
	counter.count++
	p.unauthCounts[clientIP] = counter
	return true
}
