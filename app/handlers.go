package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"runtime"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	startTime = time.Now()

	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "path", "status"},
	)

	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "Duration of HTTP requests in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "path"},
	)

	appInfo = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "app_info",
			Help: "Application build information",
		},
		[]string{"version", "go_version"},
	)
)

func init() {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
	prometheus.MustRegister(appInfo)

	appInfo.WithLabelValues(version, runtime.Version()).Set(1)
}

func registerRoutes(mux *http.ServeMux, logger *log.Logger) {
	mux.HandleFunc("/health", handleHealth(logger))
	mux.Handle("/metrics", promhttp.Handler())
	mux.HandleFunc("/api/v1/status", handleStatus(logger))
	mux.HandleFunc("/", handleRoot(logger))
}

// handleHealth returns 200 if the service is healthy. This is used by
// the ALB target group health check and by the Docker HEALTHCHECK.
func handleHealth(logger *log.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{
			"status": "healthy",
			"uptime": time.Since(startTime).String(),
		})
	}
}

// handleStatus returns detailed application status including
// environment, version, and resource metadata.
func handleStatus(logger *log.Logger) http.HandlerFunc {
	hostname, _ := os.Hostname()
	env := getEnv("ENVIRONMENT", "development")

	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var mem runtime.MemStats
		runtime.ReadMemStats(&mem)

		resp := map[string]interface{}{
			"service":     "infra-deployer",
			"version":     version,
			"environment": env,
			"hostname":    hostname,
			"uptime":      time.Since(startTime).String(),
			"go_version":  runtime.Version(),
			"goroutines":  runtime.NumGoroutine(),
			"memory": map[string]interface{}{
				"alloc_mb":       mem.Alloc / 1024 / 1024,
				"total_alloc_mb": mem.TotalAlloc / 1024 / 1024,
				"sys_mb":         mem.Sys / 1024 / 1024,
				"gc_cycles":      mem.NumGC,
			},
			"timestamp": time.Now().UTC().Format(time.RFC3339),
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}
}

// handleRoot returns a simple welcome message.
func handleRoot(logger *log.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"message": "infra-deployer is running",
			"docs":    "/api/v1/status",
			"health":  "/health",
			"metrics": "/metrics",
		})
	}
}
