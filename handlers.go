// handlers.go
// This file contains the HTTP handlers for the Certbot API. Each handler is responsible for a specific endpoint and action, such as health checks, retrieving certificates, adding new certificates, and reloading the Certbot container. The handlers use the CertStore struct to interact with the CSV file that stores certificate information, ensuring thread-safe access through mutex locking. Additionally, the handlers include professional logging to provide clear visibility into API actions and errors in the console output.

package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os/exec"
	"time"
)

// HealthCheck is a simple handler that returns a JSON response indicating the service is up, along with a timestamp. It also logs the health check status to the console.
// This is useful for monitoring and can be called by tools like Swagger UI to verify that the API is running.
func HealthCheck(w http.ResponseWriter, req *http.Request) {
	// Allow any origin (common for development) and set JSON header
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")

	// Handle preflight OPTIONS requests if Swagger sends them
	if req.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.WriteHeader(http.StatusOK)
		return
	}

	currentTime := time.Now()
	io.WriteString(w, fmt.Sprintf(`{"status": "UP", "timestamp": "%s"}`, currentTime.Format(time.RFC3339)))
	log.Printf(`{"status": "UP", "timestamp": "%s"}`, currentTime.Format(time.RFC3339))
}

// GetCerts is a handler that retrieves all certificates and returns them as JSON
// It uses the List method of CertStore to read from the CSV file safely, and logs the number of certificates found along with the client's remote address for better visibility in the console.
func (s *CertStore) GetCerts(w http.ResponseWriter, r *http.Request) {
	certs, err := s.List()
	if err != nil {
		// Standardize your error logging to match your [API] and [REQ] style
		log.Printf("%s %s: %v\n",
			Color("[ERROR]").Bold().Red(),
			Color("Failed to read CSV").White(),
			err,
		)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	// Set JSON header for your Swagger UI
	w.Header().Set("Content-Type", "application/json")
	// Professional Log Output
	log.Printf("%s Found %s certificates for %s\n",
		Color("[API]").Green(),
		Color(fmt.Sprint(len(certs))).Bold().Yellow(),
		Color(r.RemoteAddr).Cyan(),
	)
	json.NewEncoder(w).Encode(certs)
}

// NewCert is a handler that accepts a new certificate in JSON format and saves it to the CSV
// It uses the Add method of CertStore to write to the CSV file safely.
func (s *CertStore) NewCert(w http.ResponseWriter, r *http.Request) {
	defer r.Body.Close()
	// Limit body to 1MB
	r.Body = http.MaxBytesReader(w, r.Body, 1048576)

	var cert Certificate
	// Decode JSON from the request body
	if err := json.NewDecoder(r.Body).Decode(&cert); err != nil {
		sendJSONError(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// Use the receiver 's' to access the Add method
	if err := s.Add(cert); err != nil {
		sendJSONError(w, "Failed to save to CSV", http.StatusInternalServerError)
		return
	}
	// Professional Log Output
	log.Printf("%s %s %s (%s)\n",
		Color("[API]").Green(),
		Color("ADDED:").Bold().Cyan(),
		Color(cert.FQDN).White(),
		Color(cert.Email).Yellow(),
	)
	// Headers and Body: Send a success response to the client
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated) // Status 201
	w.Write([]byte(`{"message": "Certificate added successfully"}`))
}

// DeleteCert handles the removal of a certificate from the CSV via query parameter
// It uses the Remove method of CertStore to delete the certificate safely, and logs the deletion action with the FQDN for better traceability in the console.
func (s *CertStore) DeleteCert(w http.ResponseWriter, r *http.Request) {
	fqdn := r.URL.Query().Get("fqdn")
	if fqdn == "" {
		sendJSONError(w, "Missing 'fqdn' parameter", http.StatusBadRequest)
		return
	}

	if err := s.Remove(fqdn); err != nil {
		sendJSONError(w, "Failed to delete certificate", http.StatusInternalServerError)
		return
	}

	log.Printf("%s %s %s\n",
		Color("[API]").Green(),
		Color("DELETED:").Bold().Red(),
		Color(fqdn).White(),
	)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"message": "Certificate deleted successfully"}`))
}

// reloadCertbot is a handler that restarts the Certbot container using Docker commands
// It executes a system command to restart the container and handles any errors that may occur during the process.
func (s *CertStore) ReloadCertbot(w http.ResponseWriter, r *http.Request) {
	// Action Log
	log.Printf("%s %s...\n", Color("[SYS]").Purple(), Color("Triggering Certbot Restart").White())

	// Execute: docker restart <container_name>
	cmd := exec.Command("docker", "restart", s.ContainerName)
	err := cmd.Run()

	if err != nil {
		// Log the internal error but send a 500 to the client
		log.Printf("%s %s: %v\n", Color("[ERROR]").Red(), Color("Docker Restart Failed").White(), err)
		sendJSONError(w, "Failed to restart Certbot container", http.StatusInternalServerError)
		return
	}
	// Success Log
	log.Printf("%s %s\n", Color("[SYS]").Green(),
		Color(fmt.Sprintf("Container '%s' restarted successfully", s.ContainerName)).Bold().White())

	// Headers and Body: Send a success response to the client
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"message": "Container restarted successfully"}`))
}
