// middleware.go
// This file contains middleware functions for IP filtering, mTLS authentication, request logging, CORS handling, and JSON error responses.
package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"time"
)

// responseWriter is a wrapper to capture the HTTP status code
// This allows us to log the status code of the response after the request is processed.
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

// WriteHeader captures the status code and writes the header
// This method is called by the HTTP server to set the status code of the response. We override it to capture the status code for logging purposes.
func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

// ipMiddleware checks the client's IP against the ACL before allowing access
// It extracts the client's IP address from the request, checks it against the allowed or denied list based on the configuration, and either blocks the request with a 403 Forbidden or allows it to proceed to the next handler.
func ipMiddleware(filter *IPFilter, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthcheck" {
			next.ServeHTTP(w, r)
			return
		}
		host, _, err := net.SplitHostPort(r.RemoteAddr)
		if err != nil {
			host = r.RemoteAddr
		}
		found := filter.allowedIPs[host]
		if (filter.isDenylist && found) || (!filter.isDenylist && !found) {
			// LOG: Red Blocked IP
			log.Printf("%s %s %s",
				Color("[BLOCK ]").Bold().Red(),
				Color("IP:").White(),
				Color(host).Cyan(),
			)
			http.Error(w, "Forbidden", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// mtlsMiddleware checks the client's mTLS certificate for a valid Common Name (CN) against the allowed list before allowing access
// It extracts the client's certificate from the TLS connection, checks the Common Name against the allowed list, and either blocks the request with a 403 Forbidden or allows it to proceed to the next handler.
func mtlsMiddleware(allowedCNs map[string]bool, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthcheck" {
			next.ServeHTTP(w, r)
			return
		}

		if r.TLS != nil && len(r.TLS.PeerCertificates) > 0 {
			cn := r.TLS.PeerCertificates[0].Subject.CommonName

			if !allowedCNs[cn] {
				// LOG: Red Unauthorized CN
				log.Printf("%s %s %s",
					Color("[AUTH ]").Bold().Red(),
					Color("Unauthorized CN:").White(),
					Color(cn).Cyan(),
				)
				http.Error(w, "Identity Not Authorized", http.StatusForbidden)
				return
			}
		} else {
			// LOG: Red Missing Certificate
			log.Printf("%s %s",
				Color("[AUTH ]").Bold().Red(),
				Color("mTLS Certificate Required").White(),
			)
			http.Error(w, "mTLS Certificate Required", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// requestLogger is a middleware that logs incoming HTTP requests with method, path, remote address, and processing time.
// It uses the Color type to format the log output for better visibility in the console.
// This is useful for debugging and monitoring incoming requests to your API.
func requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Wrap the original writer
		wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		// Process the request using the wrapped writer
		next.ServeHTTP(wrapped, r)

		// Determine status color
		statusColor := Color(fmt.Sprint(wrapped.statusCode)).Green()
		if wrapped.statusCode >= 400 {
			statusColor = Color(fmt.Sprint(wrapped.statusCode)).Red()
		} else if wrapped.statusCode >= 300 {
			statusColor = Color(fmt.Sprint(wrapped.statusCode)).Yellow()
		}

		// Final Log Output with Status Code
		log.Printf("%s %s %s from %s status %s [%s]",
			Color("[REQ   ]").Bold().Blue(),
			Color(r.Method).Yellow(),
			Color(r.URL.Path).White(),
			Color(r.RemoteAddr).Cyan(),
			statusColor.Bold(),
			time.Since(start),
		)
	})
}

// Middleware to add CORS to any handler
// This allows Swagger UI (or any frontend) to call your API without CORS issues during development.
func enableCORS(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next(w, r)
	}
}

// sendJSONError is a helper function to send JSON-formatted error responses
// It sets the appropriate headers and status code, and formats the error message as JSON for consistency in API responses.
func sendJSONError(w http.ResponseWriter, message string, code int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	fmt.Fprintf(w, `{"error": "%s"}`, message)
}
