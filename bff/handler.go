package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
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
	extractTimeout           = 30 * time.Second
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
	appLabel, ok := p.authorize(w, r)
	if !ok {
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

// authorize validates X-App-Token (or rate-limited unauthenticated access) and
// returns the app label. On failure it writes the error response and returns ok=false.
func (p *Proxy) authorize(w http.ResponseWriter, r *http.Request) (appLabel string, ok bool) {
	token := r.Header.Get("X-App-Token")
	appLabel, ok = p.AppTokens[token]
	if !ok || token == "" {
		if !p.AllowUnauthenticated {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return "", false
		}
		clientIP := clientIPFromRequest(r)
		if !p.allowUnauthenticatedRequest(clientIP) {
			http.Error(w, `{"error":"rate limited"}`, http.StatusTooManyRequests)
			return "", false
		}
		appLabel = "unauthenticated:" + clientIP
	}
	return appLabel, true
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

// MARK: - Symptom Extraction (备孕模式)

// symptomExtractionRequest is the client's request body for /v1/extract/symptoms.
type symptomExtractionRequest struct {
	Message  string `json:"message"`
	Language string `json:"language"`
}

// symptomItem is a single extracted early-pregnancy symptom.
type symptomItem struct {
	Type    string  `json:"type"`
	DateRef *string `json:"date_ref"` // "today" | "yesterday" | null
}

// symptomExtractionResponse is returned to the client. Symptoms is always a
// non-nil slice so it marshals as [] rather than null.
type symptomExtractionResponse struct {
	Symptoms []symptomItem `json:"symptoms"`
}

// deepseekResponse is the subset of DeepSeek's chat completion we need.
type deepseekResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
}

// allowedSymptomTypes is the whitelist of early-pregnancy symptom types.
var allowedSymptomTypes = map[string]struct{}{
	"nausea": {}, "vomiting": {}, "fatigue": {}, "breastTenderness": {},
	"bloating": {}, "abdominalCramps": {}, "headache": {}, "spotting": {},
	"appetiteChange": {}, "moodChange": {}, "dizziness": {},
}

// HandleExtractSymptoms runs the symptom extraction pipeline: authenticate →
// call DeepSeek with a fixed extraction prompt → parse and whitelist-filter.
// Any failure returns {"symptoms":[]} so the client never blocks on it.
func (p *Proxy) HandleExtractSymptoms(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	appLabel, ok := p.authorize(w, r)
	if !ok {
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, maxBodySize+1))
	if err != nil {
		http.Error(w, `{"error":"failed to read request body"}`, http.StatusBadRequest)
		return
	}
	if len(body) > maxBodySize {
		http.Error(w, `{"error":"request body too large"}`, http.StatusRequestEntityTooLarge)
		return
	}

	var req symptomExtractionRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, symptomExtractionResponse{Symptoms: []symptomItem{}})
		return
	}

	// 与客户端节流一致：少于 4 个字符的消息不抽取
	if len([]rune(strings.TrimSpace(req.Message))) < 4 {
		writeJSON(w, symptomExtractionResponse{Symptoms: []symptomItem{}})
		return
	}

	symptoms, err := p.extractSymptomsUpstream(r, strings.TrimSpace(req.Message))
	if err != nil {
		log.Printf("extract symptoms upstream error (app=%s): %v", appLabel, err)
		writeJSON(w, symptomExtractionResponse{Symptoms: []symptomItem{}})
		return
	}
	writeJSON(w, symptomExtractionResponse{Symptoms: symptoms})
}

func (p *Proxy) extractSymptomsUpstream(r *http.Request, message string) ([]symptomItem, error) {
	const (
		modelName = "deepseek-chat"
		maxTokens = 300
	)
	systemPrompt := `从用户消息中抽取早孕相关症状。只抽取用户明确提到的症状，不要推测。
输出 JSON：{"symptoms": [{"type": "<症状>", "date_ref": "today" | "yesterday" | null}]}
type 只能是：nausea, vomiting, fatigue, breastTenderness, bloating, abdominalCramps, headache, spotting, appetiteChange, moodChange, dizziness
没有提到任何症状时输出 {"symptoms": []}`

	reqBody, err := json.Marshal(map[string]any{
		"model": modelName,
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": message},
		},
		"stream":          false,
		"temperature":     0,
		"max_tokens":      maxTokens,
		"response_format": map[string]string{"type": "json_object"},
	})
	if err != nil {
		return nil, err
	}

	upReq, err := http.NewRequestWithContext(r.Context(), http.MethodPost, upstreamURL, bytes.NewReader(reqBody))
	if err != nil {
		return nil, err
	}
	upReq.Header.Set("Content-Type", "application/json")
	upReq.Header.Set("Authorization", "Bearer "+p.APIKey)

	client := &http.Client{Timeout: extractTimeout}
	upResp, err := client.Do(upReq)
	if err != nil {
		return nil, err
	}
	defer upResp.Body.Close()

	respBody, err := io.ReadAll(io.LimitReader(upResp.Body, maxBodySize))
	if err != nil {
		return nil, err
	}
	if upResp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("upstream status %d: %s", upResp.StatusCode, string(respBody))
	}

	var ds deepseekResponse
	if err := json.Unmarshal(respBody, &ds); err != nil {
		return nil, err
	}
	if len(ds.Choices) == 0 {
		return nil, fmt.Errorf("upstream returned no choices")
	}
	return parseExtractedSymptoms(ds.Choices[0].Message.Content), nil
}

// parseExtractedSymptoms cleans the DeepSeek content and returns only whitelisted
// symptom types. Malformed JSON yields an empty (non-nil) slice, never an error.
func parseExtractedSymptoms(content string) []symptomItem {
	cleaned := cleanLLMContent(content)
	var parsed struct {
		Symptoms []symptomItem `json:"symptoms"`
	}
	if err := json.Unmarshal([]byte(cleaned), &parsed); err != nil {
		return []symptomItem{}
	}
	out := make([]symptomItem, 0, len(parsed.Symptoms))
	for _, item := range parsed.Symptoms {
		if _, ok := allowedSymptomTypes[item.Type]; ok {
			out = append(out, item)
		}
	}
	return out
}

// cleanLLMContent strips DeepSeek reasoning blocks and markdown code fences.
func cleanLLMContent(raw string) string {
	s := raw
	if idx := strings.Index(s, "</think>"); idx >= 0 {
		s = s[idx+len("</think>"):]
	}
	s = strings.ReplaceAll(s, "```json", "")
	s = strings.ReplaceAll(s, "```", "")
	return strings.TrimSpace(s)
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("writeJSON: %v", err)
	}
}
