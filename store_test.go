package main

import (
	"path/filepath"
	"strconv"
	"sync"
	"testing"
)

func newTestStore(t *testing.T) *CertStore {
	t.Helper()

	store := &CertStore{
		FilePath: filepath.Join(t.TempDir(), "certificates.csv"),
	}

	if err := store.Initialize(); err != nil {
		t.Fatalf("Initialize failed: %v", err)
	}

	return store
}

func TestCertStoreInitialize(t *testing.T) {
	store := newTestStore(t)

	certs, err := store.List()
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}

	if len(certs) != 0 {
		t.Fatalf("expected empty certificate inventory, got %d", len(certs))
	}
}

func TestCertStoreAddAndList(t *testing.T) {
	store := newTestStore(t)

	expected := Certificate{
		FQDN:        "test.example.com",
		DNSProvider: "cloudflare",
		Email:       "admin@example.com",
	}

	if err := store.Add(expected); err != nil {
		t.Fatalf("Add failed: %v", err)
	}

	certs, err := store.List()
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}

	if len(certs) != 1 {
		t.Fatalf("expected 1 certificate, got %d", len(certs))
	}

	if certs[0] != expected {
		t.Errorf("certificate mismatch: got %+v, want %+v", certs[0], expected)
	}
}

func TestCertStoreRemove(t *testing.T) {
	store := newTestStore(t)

	cert := Certificate{
		FQDN:        "remove.example.com",
		DNSProvider: "cloudflare",
		Email:       "admin@example.com",
	}

	if err := store.Add(cert); err != nil {
		t.Fatalf("Add failed: %v", err)
	}

	if err := store.Remove(cert.FQDN); err != nil {
		t.Fatalf("Remove failed: %v", err)
	}

	certs, err := store.List()
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}

	if len(certs) != 0 {
		t.Fatalf("expected empty inventory after removal, got %d", len(certs))
	}
}

func TestCertStoreRemovePreservesOtherRecords(t *testing.T) {
	store := newTestStore(t)

	certificates := []Certificate{
		{"first.example.com", "cloudflare", "first@example.com"},
		{"second.example.com", "cloudflare", "second@example.com"},
		{"third.example.com", "cloudflare", "third@example.com"},
	}

	for _, cert := range certificates {
		if err := store.Add(cert); err != nil {
			t.Fatalf("Add failed: %v", err)
		}
	}

	if err := store.Remove("second.example.com"); err != nil {
		t.Fatalf("Remove failed: %v", err)
	}

	remaining, err := store.List()
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}

	if len(remaining) != 2 {
		t.Fatalf("expected 2 remaining certificates, got %d", len(remaining))
	}

	if remaining[0].FQDN != "first.example.com" ||
		remaining[1].FQDN != "third.example.com" {
		t.Errorf("unexpected remaining certificates: %+v", remaining)
	}
}

func TestCertStoreConcurrentAdd(t *testing.T) {
	store := newTestStore(t)

	const count = 25

	var wg sync.WaitGroup
	errs := make(chan error, count)

	for i := 0; i < count; i++ {
		wg.Add(1)

		go func(index int) {
			defer wg.Done()

			cert := Certificate{
				FQDN:        "concurrent-" + stringID(index) + ".example.com",
				DNSProvider: "cloudflare",
				Email:       "admin@example.com",
			}

			errs <- store.Add(cert)
		}(i)
	}

	wg.Wait()
	close(errs)

	for err := range errs {
		if err != nil {
			t.Fatalf("concurrent Add failed: %v", err)
		}
	}

	certs, err := store.List()
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}

	if len(certs) != count {
		t.Fatalf("expected %d certificates, got %d", count, len(certs))
	}
}

func stringID(n int) string {
	return strconv.Itoa(n)
}
