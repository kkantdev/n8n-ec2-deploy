# Architecture & Technical Design

This document details the architectural principles, module boundaries, network topology, and security model of **n8n EC2 Deploy**.

---

## 1. Design Principles

1. **Separation of Concerns**: The main installation wizard orchestrates the workflow and coordinates dependencies, while database and reverse proxy providers handle their specific logic independently.
2. **Modular Provider Abstraction**: Any database or proxy provider conforms to a standardized interface. Adding a new provider (e.g., Caddy or AWS RDS) requires no modifications to `install.sh`.
3. **Idempotence & Safety**: The installer detects existing installations, backs up configuration files before modification, preserves cryptographic keys (`N8N_ENCRYPTION_KEY`), and prevents accidental loss of persistent data.
4. **Zero-Trust Secrets**: Database passwords and encryption keys are generated cryptographically using OpenSSL, written to `.env` with strict `0600` permissions, and are never printed to terminal stdout, stderr, or log files.
5. **Least Privilege Exposure**: Services are isolated on Docker networks. When a reverse proxy is enabled, n8n does not publish port `5678` to the host. PostgreSQL never publishes port `5432` to the host in any scenario.

---

## 2. Directory Layout & Module Responsibilities

```
n8n-ec2-deploy/
├── install.sh                  # Main interactive installer & pre-flight coordinator
├── uninstall.sh                # Safe uninstallation script with data retention defaults
├── manage.sh                   # Operational management CLI & interactive menu
├── README.md                   # Project overview & quickstart
├── LICENSE                     # MIT License
├── .gitignore                  # Git ignore rules for runtime files and secrets
│
├── config/
│   └── defaults.sh             # Global defaults: image versions, ports, timeouts
│
├── lib/
│   ├── common.sh               # Logging helpers, UI formatters, prompt functions
│   ├── colors.sh               # ANSI color definitions and banners
│   ├── validation.sh           # Regex validators (FQDN, IPv4, email, connection URI, DNS)
│   ├── system-checks.sh        # OS release, CPU architecture, disk space, IMDS detection
│   ├── docker.sh               # Docker Engine and Docker Compose V2 verification & installer
│   ├── database.sh             # Database provider menu and dispatcher
│   ├── secrets.sh              # OpenSSL cryptographic secret generation
│   ├── environment.sh          # .env file generation, parsing, and backup
│   ├── compose-generator.sh    # Dynamic Docker Compose configuration generator
│   ├── deployment.sh           # Directory setup, file permissions, and startup
│   └── health-check.sh         # Resilient retry loops for service health verification
│
├── providers/
│   ├── database/
│   │   ├── ec2-postgres.sh     # EC2 containerized PostgreSQL provider
│   │   └── supabase.sh         # Supabase PostgreSQL validator & connector
│   │
│   └── proxy/
│       ├── provider-interface.sh # Standardized proxy contract loader
│       ├── nginx/
│       │   ├── install.sh      # Nginx container lifecycle & Let's Encrypt bootstrapping
│       │   ├── configure.sh    # Nginx config generator, DNS validator, email prompt
│       │   └── docker-compose.yml # Compose definition for Nginx + Certbot
│       │
│       └── traefik/
│           ├── install.sh      # Traefik lifecycle & acme.json permissions
│           ├── configure.sh    # Traefik dynamic config generator & DNS validator
│           └── docker-compose.yml # Compose definition for Traefik v3
│
├── templates/
│   ├── docker-compose.yml      # Base compose reference
│   ├── .env.example            # Documented environment variables reference
│   ├── nginx/
│   │   └── n8n.conf            # Nginx virtual host template with WebSocket support
│   └── traefik/
│       └── dynamic.yml         # Traefik dynamic router & service template
│
└── docs/
    ├── ARCHITECTURE.md         # This technical specification
    ├── INSTALLATION.md         # Step-by-step EC2 setup guide
    └── TROUBLESHOOTING.md      # Common failure scenarios and recovery procedures
```

---

## 3. Provider Interfaces

### 3.1 Database Provider Interface
Each database provider module in `providers/database/` exposes a configuration function:

- `db_<provider>_configure`: Prompts or auto-generates credentials, validates network connectivity, checks migration permissions, and exports standard environment variables:
  - `DB_POSTGRESDB_HOST`
  - `DB_POSTGRESDB_PORT`
  - `DB_POSTGRESDB_DATABASE`
  - `DB_POSTGRESDB_USER`
  - `DB_POSTGRESDB_PASSWORD`
  - `DB_POSTGRESDB_SCHEMA`
  - `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED`

### 3.2 Reverse Proxy Provider Interface
Each reverse proxy in `providers/proxy/<provider>/` implements the standard lifecycle functions:

- `<provider>_validate_prerequisites`: Confirms ports `80` and `443` are free.
- `<provider>_prompt_config`: Obtains and validates the domain name, checks DNS resolution against the EC2 public IP, and prompts for the Let's Encrypt notification email.
- `<provider>_generate_config`: Generates proxy configuration and docker-compose files inside `${INSTALL_DIR}/proxy/`.
- `<provider>_install`: Bootstraps certificates, sets file permissions (e.g., `chmod 600` for Traefik `acme.json`), and starts services.
- `<provider>_start`: Starts proxy containers.
- `<provider>_stop`: Stops proxy containers.
- `<provider>_status`: Reports proxy container status.
- `<provider>_logs`: Streams proxy container logs.

---

## 4. Docker Network Topology

The installer uses up to two distinct Docker bridge networks:

### Scenario 1: Public IP Access (No Reverse Proxy)
```
[Host Port 5678] ──────► [n8n:5678]
                              │
                    [n8n-internal network]
                              │
                       [postgres:5432]
                     (No host exposure)
```

### Scenario 2: Custom Domain Access (With Reverse Proxy)
```
[Host Port 80/443] ────► [Reverse Proxy (Nginx/Traefik)]
                                    │
                         [n8n-proxy-network]
                                    │
                                [n8n:5678]
                          (No host port published)
                                    │
                         [n8n-internal network]
                                    │
                             [postgres:5432]
                           (No host exposure)
```

**Key Security Properties:**
- When a reverse proxy is deployed, port `5678` is never published to the host. n8n is reached solely through the proxy via Docker's internal DNS.
- PostgreSQL only attaches to `n8n-internal`. It has no connection to `n8n-proxy-network` and publishes no ports to the host.
- Even if the reverse proxy container is compromised, the PostgreSQL database is unreachable directly from the proxy network.

---

## 5. Persistent Storage & Permissions

All stateful data is mounted as persistent bind mounts under `/opt/applications/n8n/`:

| Directory | Ownership | Permissions | Description |
|---|---|---|---|
| `/opt/applications/n8n/.env` | `root:root` | `0600` | Application secrets, database credentials, keys |
| `/opt/applications/n8n/data/n8n` | `1000:1000` | `0750` | n8n SQLite/settings, executions, custom nodes |
| `/opt/applications/n8n/postgres/data` | `999:999` | `0700` | PostgreSQL database cluster files |
| `/opt/applications/n8n/proxy/certbot/conf` | `root:root` | `0755` | Let's Encrypt live certificates and private keys |
| `/opt/applications/n8n/proxy/traefik/acme.json` | `root:root` | `0600` | Traefik ACME certificate store (strictly 600) |

The user `1000:1000` matches the default `node` user running inside the official n8n container, avoiding write permission errors during workflow executions.

