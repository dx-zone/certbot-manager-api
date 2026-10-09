// store.go
package main

import (
	"encoding/csv"
	"os"
	"strings"
	"sync"
	"syscall"
)

// CertStore handles all thread-safe file operations
// It uses a mutex to ensure that only one write operation can occur at a time, while allowing multiple concurrent reads.
type CertStore struct {
	FilePath      string
	ContainerName string
	mu            sync.RWMutex // Protects the CSV file from concurrent writes
}

// Initialize checks if the CSV file exists and has headers, if not it creates it with headers
// This is called at startup to ensure the file is ready for use without destroying existing data.
func (s *CertStore) Initialize() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Check if file exists and has size > 0
	info, err := os.Stat(s.FilePath)
	if err == nil && info.Size() > 0 {
		return nil // File exists and is not empty, do nothing
	}

	// If file is missing or empty, create it with headers
	file, err := os.Create(s.FilePath)
	if err != nil {
		return err
	}
	defer file.Close()

	writer := csv.NewWriter(file)
	defer writer.Flush()

	// Write CSV Headers
	return writer.Write([]string{"fqdn", "dns_provider", "email"})
}

// List returns all certificates from the CSV
// It uses a read lock to allow multiple concurrent reads while preventing writes during the read operation.
func (s *CertStore) List() ([]Certificate, error) {
	s.mu.RLock() // Allow multiple readers
	defer s.mu.RUnlock()

	file, err := os.Open(s.FilePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	reader := csv.NewReader(file)
	reader.FieldsPerRecord = -1 // "Don't Panic" flag to handle rows with varying number of fields
	records, err := reader.ReadAll()
	if err != nil {
		return nil, err
	}

	// Initialize an empty slice to ensure the API returns [] instead of null in JSON when there are no records
	certs := []Certificate{}
	for _, r := range records {
		// GUARD CLAUSE: Skip header, comments, or anything not exactly 3 columns
		if len(r) != 3 || strings.HasPrefix(r[0], "#") || strings.Contains(r[0], "fqdn") {
			continue
		}

		// Map CSV columns to struct fields
		certs = append(certs, Certificate{
			FQDN:        r[0],
			DNSProvider: r[1],
			Email:       r[2],
		})
	}
	return certs, nil
}

// Add appends a new certificate to the CSV file with proper locking (System-level locking using syscall.Flock)
// This ensures that even if multiple instances of the application are running, they won't corrupt the CSV file.
func (s *CertStore) Add(c Certificate) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// 1. Open the file
	file, err := os.OpenFile(s.FilePath, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0644)
	if err != nil {
		return err
	}
	defer file.Close()

	// 2. Apply an Exclusive Lock (LOCK_EX)
	// This will block other processes until we are done.
	if err := syscall.Flock(int(file.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	// 3. Ensure we unlock when we are finished
	defer syscall.Flock(int(file.Fd()), syscall.LOCK_UN)

	writer := csv.NewWriter(file)
	defer writer.Flush()

	return writer.Write([]string{c.FQDN, c.DNSProvider, c.Email})
}

// Remove deletes a certificate from the CSV file by reading all records, filtering out the one to delete, and writing back the remaining records.
// This method also uses a write lock to ensure that no other writes can occur while we are modifying the file.
func (s *CertStore) Remove(fqdn string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// 1. Read all existing records
	file, err := os.Open(s.FilePath)
	if err != nil {
		return err
	}

	reader := csv.NewReader(file)
	reader.FieldsPerRecord = -1 // <--- MUST add this here too!

	records, err := reader.ReadAll()
	file.Close()
	if err != nil {
		return err
	}

	// 2. Filter records
	var remaining [][]string
	for _, r := range records {
		// Always keep the header row so we don't lose it
		if len(r) > 0 && strings.EqualFold(r[0], "fqdn") {
			remaining = append(remaining, r)
			continue
		}

		// Skip malformed rows or comments
		if len(r) != 3 || strings.HasPrefix(r[0], "#") {
			continue
		}

		// Skip the record we actually want to delete
		if r[0] == fqdn {
			continue
		}

		// Keep everything else
		remaining = append(remaining, r)
	}

	// 3. Overwrite the file with the remaining records
	file, err = os.Create(s.FilePath)
	if err != nil {
		return err
	}
	defer file.Close()

	writer := csv.NewWriter(file)
	defer writer.Flush()
	return writer.WriteAll(remaining)
}
