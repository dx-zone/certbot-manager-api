package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadACLAllowlist(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "ips.txt")

	content := "# Authorized clients\n192.168.1.10\n10.0.0.5 # monitoring\n"

	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}

	filter, err := loadACL(path, "allow")
	if err != nil {
		t.Fatalf("loadACL failed: %v", err)
	}

	if filter.isDenylist {
		t.Fatal("expected allowlist mode")
	}

	if !filter.allowedIPs["192.168.1.10"] {
		t.Error("expected 192.168.1.10 in allowlist")
	}

	if !filter.allowedIPs["10.0.0.5"] {
		t.Error("expected 10.0.0.5 in allowlist")
	}

	if filter.allowedIPs["192.168.1.20"] {
		t.Error("unexpected IP in allowlist")
	}
}

func TestLoadACLDenylist(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "ips.txt")

	if err := os.WriteFile(path, []byte("192.168.1.99\n"), 0600); err != nil {
		t.Fatal(err)
	}

	filter, err := loadACL(path, "deny")
	if err != nil {
		t.Fatalf("loadACL failed: %v", err)
	}

	if !filter.isDenylist {
		t.Fatal("expected denylist mode")
	}

	if !filter.allowedIPs["192.168.1.99"] {
		t.Error("expected IP in denylist")
	}
}

func TestLoadAuthorizedCNs(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "clients.txt")

	content := "# Authorized mTLS clients\nclient-identity\nmonitoring-agent # monitoring\n"

	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}

	clients, err := loadAuthorizedCNs(path)
	if err != nil {
		t.Fatalf("loadAuthorizedCNs failed: %v", err)
	}

	if !clients["client-identity"] {
		t.Error("expected client-identity to be authorized")
	}

	if !clients["monitoring-agent"] {
		t.Error("expected monitoring-agent to be authorized")
	}

	if clients["unauthorized-client"] {
		t.Error("unexpected client authorization")
	}
}

func TestLoadACLMissingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing-ips.txt")

	_, err := loadACL(path, "allow")
	if err == nil {
		t.Fatal("expected an error for missing ACL file")
	}
}
