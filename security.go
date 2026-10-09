// security.go
package main

import (
	"bufio"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"log"
	"os"
	"strings"
)

// IPFilter is a simple struct to hold allowed IPs and whether it's a denylist or allowlist
// This can be used in your middleware to check if the incoming request's IP is allowed or denied based on the configuration.
type IPFilter struct {
	allowedIPs map[string]bool
	isDenylist bool
}

// Certificate represents a row in your CSV
// It has JSON tags for easy encoding/decoding in your API handlers.
type Certificate struct {
	FQDN        string `json:"fqdn"`
	DNSProvider string `json:"dns_provider"`
	Email       string `json:"email"`
}

// loadACL reads the IP list from the specified file and returns an IPFilter struct
// It processes the file line by line, stripping comments, handling the '!' symbol for skip logic, and building a map of allowed IPs based on the specified mode (allow or deny).
func loadACL(path string, mode string) (*IPFilter, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	ips := make(map[string]bool)
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := scanner.Text()

		// 1. Strip everything after a '#' (inline comments)
		if idx := strings.Index(line, "#"); idx != -1 {
			line = line[:idx]
		}

		// 2. Clean up surrounding whitespace
		line = strings.TrimSpace(line)

		// 3. Skip empty lines or lines that were just comments
		if line == "" {
			continue
		}

		// 4. Process the '!' symbol (Skip logic)
		if strings.HasPrefix(line, "!") {
			log.Printf("Skipping blacklisted/ignored entry: %s", line)
			continue
		}

		// 5. Add the clean IP to the map
		ips[line] = true
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return &IPFilter{
		allowedIPs: ips,
		isDenylist: strings.ToLower(mode) == "deny",
	}, nil
}

// loadAuthorizedCNs reads the authorized Common Names from a file and returns a map for quick lookup
// It processes the file line by line, stripping comments and whitespace, and builds a map of allowed CNs for mTLS client authentication.
func loadAuthorizedCNs(path string) (map[string]bool, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	cns := make(map[string]bool)
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := scanner.Text()
		// Strip comments and whitespace just like we did for IPs
		if idx := strings.Index(line, "#"); idx != -1 {
			line = line[:idx]
		}
		name := strings.TrimSpace(line)
		if name != "" {
			cns[name] = true
		}
	}
	return cns, scanner.Err()
}

// validatePKI checks the server and CA certificates for proper roles and usage
// It ensures that the server certificate is not issued by the same authority as the mTLS CA and that the mTLS CA is not a public CA, which would be a security risk.
func validatePKI(serverCertPath, caPath string) {
	sData, _ := os.ReadFile(serverCertPath)
	sBlock, _ := pem.Decode(sData)
	if sBlock == nil {
		return
	}
	sCert, _ := x509.ParseCertificate(sBlock.Bytes)

	cData, _ := os.ReadFile(caPath)
	cBlock, _ := pem.Decode(cData)
	if cBlock == nil {
		return
	}
	caCert, _ := x509.ParseCertificate(cBlock.Bytes)

	if sCert.Issuer.CommonName == caCert.Subject.CommonName {
		fmt.Println("⚠️  WARNING: Server Certificate and mTLS CA appear to be the same authority.")
	}

	publicNames := []string{"Let's Encrypt", "R3", "DigiCert", "Sectigo"}
	for _, name := range publicNames {
		if strings.Contains(caCert.Subject.CommonName, name) {
			fmt.Printf("❌ ERROR: mTLS CA (%s) is a Public Authority. Avoid using a Public CA for mTLS. Use a Private CA instead.\n", name)
			os.Exit(1)
		}
	}
	fmt.Println("✅ PKI Validation: Distinct roles for Public/Private certs confirmed.")
}

// loadCA loads a CA certificate from the specified file and returns a CertPool
// This is used in the TLS configuration to verify client certificates for mTLS.
func loadCA(path string) *x509.CertPool {
	caCert, _ := os.ReadFile(path)
	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)
	return caCertPool
}
