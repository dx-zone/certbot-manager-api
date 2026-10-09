// main.go - Entry point for the Cert Manager API
// This file sets up the HTTPS server, parses command-line flags, validates required files, and initializes the certificate store.
package main

import (
	"crypto/tls"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
)

// validateFiles checks if required files exist and are readable.
// If any are missing, it lists them all, shows Usage, and exits.
func validateFiles(files ...string) {
	var missingFiles []string

	for _, f := range files {
		if _, err := os.Stat(f); os.IsNotExist(err) {
			missingFiles = append(missingFiles, f)
		} else if err != nil {
			// Handle permissions or other OS errors immediately
			fmt.Printf("%s Error accessing %s: %v\n", Color("❌").Red(), f, err)
			os.Exit(1)
		}
	}

	// If we found any missing files, report them all and exit
	if len(missingFiles) > 0 {
		fmt.Fprintf(os.Stderr, "\n%s %s\n",
			Color("❌ Startup failed: required files are missing.").Bold().White(),
			Color("\nPlease make sure the following files exist and are accessible:").White(),
		)

		for _, f := range missingFiles {
			fmt.Fprintf(os.Stderr, "  %s %s\n", Color("•").Red(), f)
		}

		flag.Usage()
		os.Exit(1)
	}
}

// Main function
func main() {
	// Define Flags for Configuration
	listenAddr := flag.String("listen", ":443", "Address for the HTTPS server to listen on")
	tlsCert := flag.String("tls-cert", "server.crt", "Path to the server TLS certificate")
	tlsKey := flag.String("tls-key", "server.key", "Path to the server TLS private key")
	ipListFile := flag.String("ip-list", "ips.txt", "Path to a file containing IPs or CIDR ranges")
	ipPolicy := flag.String("ip-policy", "allow", "How to treat entries in -ip-list: allow or deny")
	clientCAFile := flag.String("mtls-client-ca", "ca.crt", "Path to the CA certificate used to verify client certificates for mTLS authentication")
	cnFile := flag.String("mtls-allowed-cns", "clients.txt", "Path to a file containing allowed client certificate Common Names for mTLS authentication")
	certCSVFile := flag.String("cert-csv", "certificates.csv", "Path to the CSV file listing certificates to manage")
	certManager := flag.String("cert-manager", "certbot", "Name of the Docker container managing certificates")

	// Prettify the Help Usage
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "\n%s\n", Color("CERT MANAGER API").Bold().Green())
		fmt.Fprintf(os.Stderr, "%s Secure HTTPS API for Certbot automation with mTLS and IP-based access control.\n\n", Color("Description:").Faint())

		fmt.Fprintf(os.Stderr, "%s\n", Color("USAGE:").Bold().Yellow())
		fmt.Fprintf(os.Stderr, "  %v [options]\n\n", os.Args[0])

		fmt.Fprintf(os.Stderr, "%s\n", Color("NETWORKING:").Bold().Cyan())
		printFlag("-listen", "Address for the HTTPS server to listen on", *listenAddr)

		fmt.Fprintf(os.Stderr, "\n%s\n", Color("SECURITY (TLS):").Bold().Cyan())
		printFlag("-tls-cert", "Path to the server TLS certificate", *tlsCert)
		printFlag("-tls-key", "Path to the server TLS private key", *tlsKey)

		fmt.Fprintf(os.Stderr, "\n%s\n", Color("AUTHENTICATION (mTLS):").Bold().Cyan())
		printFlag("-mtls-client-ca", "CA certificate used to verify client certificates for mTLS authentication", *clientCAFile)
		printFlag("-mtls-allowed-cns", "File with allowed client certificate Common Names for mTLS authentication", *cnFile)

		fmt.Fprintf(os.Stderr, "\n%s\n", Color("ACCESS CONTROL:").Bold().Cyan())
		printFlag("-ip-list", "File with IPs or CIDR ranges to allow or block", *ipListFile)
		printFlag("-ip-policy", "How to treat entries in -ip-list: allow or deny", *ipPolicy)

		fmt.Fprintf(os.Stderr, "\n%s\n", Color("CERTIFICATE INPUT:").Bold().Cyan())
		printFlag("-cert-csv", "CSV file listing certificates to manage (fqdn,dns_provider,email)", *certCSVFile)

		fmt.Fprintf(os.Stderr, "\n%s\n", Color("CERTIFICATE MANAGER:").Bold().Cyan())
		printFlag("-cert-manager", "Name of the Docker container managing certificates", *certManager)

		fmt.Fprintf(os.Stderr, "\n%s\n", Color("EXAMPLES:").Bold().Yellow())
		fmt.Fprintf(os.Stderr, "  %v -listen :8443 -ip-policy deny\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  %v -mtls-client-ca ./pki/ca.crt -mtls-allowed-cns ./pki/allowed_users.txt\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  %v -cert-csv ./config/certificates.csv\n\n", os.Args[0])
	}

	flag.Parse()

	// Validate Files Exist
	files := []string{*tlsCert, *tlsKey, *ipListFile, *clientCAFile, *cnFile, *certCSVFile}

	//
	validateFiles(files...)

	//
	for _, f := range files {
		if _, err := os.Stat(f); os.IsNotExist(err) {
			fmt.Printf("❌ Required file not found: %s\n", f)
			//flag.Usage()
			//os.Exit(1)
		} else if err != nil {
			log.Fatalf("❌ Error checking file %s: %v", f, err)
		}
	}

	// Security Check (Public vs Private PKI)
	validatePKI(*tlsCert, *clientCAFile)

	// Load ACL
	filter, err := loadACL(*ipListFile, *ipPolicy)
	if err != nil {
		log.Fatalf("Failed to load ACL: %v", err)
	}

	// Load Allowed CNs for mTLS
	allowedCNs, err := loadAuthorizedCNs(*cnFile)
	if err != nil {
		log.Fatalf("Failed to load authorized mTLS clients: %v", err)
	}

	// Initialize the certificate store with the flag value
	store := &CertStore{
		FilePath:      *certCSVFile,
		ContainerName: *certManager, // <-- Pass the flag here
	}

	// Ensure file is ready without destroying existing data
	if err := store.Initialize(); err != nil {
		log.Fatalf("Could not initialize CSV: %v", err)
	}

	// Setup Routes and Middleware Chain
	// Create a new HTTP server mux
	mux := http.NewServeMux()

	/* ENDPOINTS AND HANDLERS
	// Note: CORS is applied at the handler level to ensure it works with mTLS and IP filtering
	*/

	// Health check endpoint
	mux.HandleFunc("GET /healthcheck", enableCORS(HealthCheck))

	// GET all certs using the method on CertStore
	mux.HandleFunc("GET /certs", enableCORS(store.GetCerts))

	// POST new cert request using the method on CertStore
	mux.HandleFunc("POST /certs", enableCORS(store.NewCert))

	// DELETE cert using the method on CertStore
	mux.HandleFunc("DELETE /certs", enableCORS(store.DeleteCert))

	// POST reload certbot (no store method needed, just a handler)
	mux.HandleFunc("POST /reload", enableCORS(store.ReloadCertbot))

	// Middleware Chain: IP Filter -> mTLS Check -> Logger
	// Order: Logger -> IP Filter -> mTLS Check -> CORS/Handlers
	secureHandler := requestLogger(ipMiddleware(filter, mtlsMiddleware(allowedCNs, mux)))

	// Start the Server with TLS Config.
	//
	// GetCertificate reloads the server certificate and private key from disk
	// for each new TLS handshake. This allows Certbot-renewed certificates to
	// become active without restarting the API service.
	tlsConfig := &tls.Config{
		ClientCAs:  loadCA(*clientCAFile),
		ClientAuth: tls.RequireAndVerifyClientCert,

		// GetCertificate is called for each new TLS handshake to dynamically
		// load the latest server certificate and private key from disk.
		GetCertificate: func(_ *tls.ClientHelloInfo) (*tls.Certificate, error) {
			cert, err := tls.LoadX509KeyPair(*tlsCert, *tlsKey)
			if err != nil {
				return nil, fmt.Errorf("reload TLS certificate: %w", err)
			}

			return &cert, nil
		},
	}

	fmt.Println(
		Color("Cert Manager API").Green(),
		"listening on",
		*listenAddr,
	)

	server := &http.Server{
		Addr:      *listenAddr,
		Handler:   secureHandler,
		TLSConfig: tlsConfig,
	}

	// Certificate/key loading is handled dynamically by tls.Config.GetCertificate.
	// Empty certificate paths prevent ListenAndServeTLS from loading a static
	// certificate at startup.
	log.Fatal(server.ListenAndServeTLS("", ""))

}
