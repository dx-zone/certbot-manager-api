# ==============================================================================
# Certbot Manager API - Build Automation
# ==============================================================================

APP_NAME      := cert-manager-api
MODULE        := github.com/dx-zone/certbot-manager-api
GO            := go
GARBLE        := garble

DIST_DIR      := dist
GOOS_TARGET   ?= linux
GOARCH_TARGET ?= amd64

VERSION       ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS       := -s -w

.DEFAULT_GOAL := help

.PHONY: help fmt fmt-check vet test test-race check build build-linux \
        build-garble clean deps version

help:
	@echo ""
	@echo "Certbot Manager API - Development Commands"
	@echo "=========================================="
	@echo "  make help          Show available commands"
	@echo "  make fmt           Format Go source code"
	@echo "  make fmt-check     Check Go formatting without modifying files"
	@echo "  make vet           Run Go static analysis"
	@echo "  make test          Run Go tests"
	@echo "  make test-race     Run Go tests with race detection"
	@echo "  make check         Run formatting, vetting and tests"
	@echo "  make build         Build native binary"
	@echo "  make build-linux   Build Linux AMD64 binary"
	@echo "  make build-garble  Build obfuscated Linux binary"
	@echo "  make clean         Remove generated binaries"
	@echo "  make deps          Download Go dependencies"
	@echo "  make version       Display build and tool versions"
	@echo ""

fmt:
	$(GO) fmt ./...

fmt-check:
	@files="$$(gofmt -l $$(git ls-files --cached --others --exclude-standard '*.go'))"; \
	if [ -n "$$files" ]; then \
		echo "Go files require formatting:"; \
		echo "$$files"; \
		exit 1; \
	fi
	@echo "Go formatting OK"

vet:
	$(GO) vet ./...

test:
	$(GO) test ./...

test-race:
	$(GO) test -race ./...

check: fmt-check vet test

build:
	@mkdir -p $(DIST_DIR)
	CGO_ENABLED=0 $(GO) build -trimpath \
		-ldflags="$(LDFLAGS)" \
		-o $(DIST_DIR)/$(APP_NAME) .
	@echo "Built $(DIST_DIR)/$(APP_NAME)"

build-linux:
	@mkdir -p $(DIST_DIR)
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		$(GO) build -trimpath \
		-ldflags="$(LDFLAGS)" \
		-o $(DIST_DIR)/$(APP_NAME)-linux-amd64 .
	@echo "Built Linux AMD64 binary"

build-garble:
	@command -v $(GARBLE) >/dev/null 2>&1 || { \
		echo "Error: garble is not installed or not in PATH"; \
		exit 1; \
	}
	@mkdir -p $(DIST_DIR)
	CGO_ENABLED=0 GOOS=$(GOOS_TARGET) GOARCH=$(GOARCH_TARGET) \
		$(GARBLE) -literals build -trimpath \
		-ldflags="$(LDFLAGS)" \
		-o $(DIST_DIR)/$(APP_NAME)-$(GOOS_TARGET)-$(GOARCH_TARGET)-garble .
	@echo "Built obfuscated binary"

clean:
	rm -rf $(DIST_DIR)
	@echo "Build artifacts removed"

deps:
	$(GO) mod download
	$(GO) mod verify

version:
	@echo "Application : $(APP_NAME)"
	@echo "Module      : $(MODULE)"
	@echo "Version     : $(VERSION)"
	@$(GO) version
	@$(GARBLE) version 2>/dev/null || echo "Garble      : not installed"
