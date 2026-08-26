package main

import (
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
)

// version is stamped at build time via -ldflags "-X main.version=<commit>" (see deploy.sh).
var version = "dev"

func main() {
	apiKey := os.Getenv("DEEPSEEK_API_KEY")
	if apiKey == "" {
		log.Fatal("DEEPSEEK_API_KEY environment variable is required")
	}

	tokens, err := loadAppTokens()
	if err != nil {
		log.Fatal(err)
	}

	addr := os.Getenv("LISTEN_ADDR")
	if addr == "" {
		addr = ":8080"
	}

	proxy := &Proxy{
		APIKey:               apiKey,
		AppTokens:            tokens,
		AllowUnauthenticated: envBool("ALLOW_UNAUTHENTICATED_APP"),
		UnauthRatePerMinute:  envInt("UNAUTH_RATE_LIMIT_PER_MINUTE", defaultUnauthRatePerMin),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/chat/completions", proxy.HandleCompletions)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
	})

	labels := make([]string, 0, len(tokens))
	for _, l := range tokens {
		labels = append(labels, l)
	}
	log.Printf("BFF proxy listening on %s (version=%s, apps: %s, allow_unauthenticated=%t, unauth_rate_per_minute=%d)",
		addr,
		version,
		strings.Join(labels, ", "),
		proxy.AllowUnauthenticated,
		proxy.UnauthRatePerMinute,
	)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}

// loadAppTokens parses APP_TOKENS as `token1:label1,token2:label2,...`.
// Falls back to single APP_TOKEN (label "default") when APP_TOKENS is not set.
func loadAppTokens() (map[string]string, error) {
	out := map[string]string{}
	if multi := os.Getenv("APP_TOKENS"); multi != "" {
		for _, pair := range strings.Split(multi, ",") {
			pair = strings.TrimSpace(pair)
			if pair == "" {
				continue
			}
			parts := strings.SplitN(pair, ":", 2)
			token := strings.TrimSpace(parts[0])
			label := "unnamed"
			if len(parts) == 2 {
				label = strings.TrimSpace(parts[1])
			}
			if token != "" {
				out[token] = label
			}
		}
	}
	if single := os.Getenv("APP_TOKEN"); single != "" {
		if _, exists := out[single]; !exists {
			out[single] = "default"
		}
	}
	if len(out) == 0 {
		return nil, errEnv("APP_TOKENS or APP_TOKEN environment variable is required")
	}
	return out, nil
}

type errEnv string

func (e errEnv) Error() string { return string(e) }

func envBool(name string) bool {
	value := strings.TrimSpace(strings.ToLower(os.Getenv(name)))
	return value == "1" || value == "true" || value == "yes" || value == "on"
}

func envInt(name string, fallback int) int {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}
