# 🛠️ Cert Manager API — Test Toolkit

This directory provides a **self-contained testing and development toolkit** for the Cert Manager API. It allows you to:

- Run the API locally or against a prod-like environment
- Validate mTLS certificates and configuration
- Execute API smoke tests
- Launch Swagger UI for quick API exploration

# 📁 Structure

```bash
test/
├── lib.sh              # Shared helper functions (logging, validation, utils)
├── .env.api            # Test environment configuration (paths, host, certs)
├── run-server.sh       # Build + run the API
├── test-api.sh         # mTLS-aware API test runner
├── swagger-ui-up.sh    # Launch Swagger UI container
└── mtls-audit.sh       # Inspect and validate mTLS PKI material
```

# 🚀 Quick Start

```bash
# 1. Validate PKI setup
./test/mtls-audit.sh

# 2. Run API locally
./test/run-server.sh

# 3. Execute tests
./test/test-api.sh all

# 4. Launch Swagger UI (optional)
./test/swagger-ui-up.sh --http
```

# 🧠 Core Concepts

## 🔐 TLS vs mTLS (Important)

This project uses **two separate certificate systems**:

| Purpose          | Files                                   | Used by               |
| ---------------- | --------------------------------------- | --------------------- |
| Server TLS       | `fullchain.pem`, `privkey.pem`          | API server identity   |
| mTLS Client Auth | `client-identity.crt`, `.key`, `ca.crt` | Client authentication |

### Flow

```bash
Client → (presents client cert) → API
API → (verifies using ca.crt) → accepts/rejects
```

# ⚙️ Configuration (`.env.api`)

All scripts load configuration from:

```bash
test/.env.api
```

Example:

```bash
API_HOST="repo.mydatacenter.io"
API_PORT="8000"

BASE_DIR="/opt/certbot"

CLIENT_NAME="client-identity"

TLS_CERT_FILE="/opt/certbot/.../fullchain.pem"
TLS_KEY_FILE="/opt/certbot/.../privkey.pem"

CLIENT_CERT_FILE="/opt/certbot/.../client-identity.crt"
CLIENT_KEY_FILE="/opt/certbot/.../client-identity.key"
CLIENT_CA_FILE="/opt/certbot/.../client-ca.crt"
```

# 🧪 Scripts

## ▶️ `run-server.sh`

Builds and runs the API.

```bash
./test/run-server.sh
./test/run-server.sh --mode local
./test/run-server.sh --dry-run
```

### Features

- Builds Go binary
- Uses TLS + mTLS config
- Supports:
  - `local` mode (repo files)
  - `prodlike` mode (`/opt/certbot`)
- Validates required files before running

## 🧪 `test-api.sh`

Runs API tests using mTLS authentication.

```bash
./test/test-api.sh health
./test/test-api.sh all
./test/test-api.sh --verbose all
```

### Available tests

| Test             | Endpoint             | Expected |
| ---------------- | -------------------- | -------- |
| `health`         | `/healthcheck`       | 200      |
| `list`           | `/certs`             | 200      |
| `add`            | `/certs`             | 200      |
| `delete`         | `/certs`             | 200      |
| `reload`         | `/reload`            | 200      |
| `invalid-path`   | `/does-not-exist`    | 404      |
| `invalid-method` | `PATCH /healthcheck` | 405      |

## 📘 `swagger-ui-up.sh`

Launch Swagger UI container.

```bash
./test/swagger-ui-up.sh --http
./test/swagger-ui-up.sh --mode prodlike -f repo.mydatacenter.io
```

### Notes

- Default: HTTP mode (simplest for dev)
- TLS mode available if certs are mounted
- Serves `api/openapi.json`

## 🔎 `mtls-audit.sh`

Validates and explains your PKI setup.

```bash
./test/mtls-audit.sh
./test/mtls-audit.sh --write-clients-txt
```

### Checks

- Certificate subject / issuer
- CN extraction
- Key ↔ cert match
- CA chain verification
- EKU validation
- Suggested `clients.txt` entry

## 🧩 `lib.sh`

Shared helper library.

Provides:

- Logging (`info`, `warn`, `error`, `success`)
- Validation helpers (`require_file`, `require_command`)
- Path utilities
- Output formatting

All scripts source this file.

# 🧭 Modes

| Mode       | Description                          |
| ---------- | ------------------------------------ |
| `local`    | Uses repo-local files where possible |
| `prodlike` | Uses `/opt/certbot` paths            |

# 🔄 Typical Workflow

```bash
# Validate certificates
./test/mtls-audit.sh

# Start API
./test/run-server.sh

# Run tests
./test/test-api.sh all

# View API docs
./test/swagger-ui-up.sh --http
```

# ⚠️ Common Pitfalls

## ❌ Mixing TLS and mTLS

- `fullchain.pem` ≠ `ca.crt`
- Server cert ≠ client cert

## ❌ CN mismatch

Ensure:

```bash
openssl x509 -in client-identity.crt -noout -subject
```

Matches:

```bash
clients.txt
```

## ❌ Wrong CA used in curl

- `--cacert` → trust server
- `--cert/--key` → identify client

# 🔧 Troubleshooting

## Verify client cert

```bash
openssl verify -CAfile ca.crt client-identity.crt
```

## Check key match

```bash
openssl x509 -noout -modulus -in client-identity.crt | openssl md5
openssl rsa  -noout -modulus -in client-identity.key | openssl md5
```

## Inspect cert

```bash
openssl x509 -in client-identity.crt -text -noout
```

# 📌 Design Philosophy

This toolkit follows:

- **Config-driven execution** (`.env.api`)
- **Mode-aware scripts** (`local` vs `prodlike`)
- **Clear TLS separation**
- **Fail-fast validation**
- **Readable output**

# 🚀 Next Improvements (Optional)

- `.env.api.example` template
- Multiple environment configs (`.env.api.local`, `.env.api.prod`)
- CI integration for `test-api.sh all`
- Automated PKI rotation hooks

# 💬 Final Note

This setup is intentionally designed to mirror real-world systems:

- Public TLS via Let’s Encrypt
- Internal mTLS for service authentication
- Config-driven runtime behavior

If something breaks, run:

```bash
./test/mtls-audit.sh
```

That will usually tell you exactly why.