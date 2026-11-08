# n8n EC2 Deploy

Production-conscious, beginner-friendly Bash installer to deploy and manage **n8n** on an **AWS EC2 Ubuntu Server** using Docker and Docker Compose.

---

## Features

- **Interactive Terminal Wizard**: Clean, guided installation experience for beginners.
- **Pre-flight System Verification**: Automatically checks Ubuntu compatibility (22.04 LTS / 24.04 LTS), CPU architecture (x86_64 / ARM64), available disk space, ports, and outbound connectivity.
- **Automated Docker Setup**: Detects Docker Engine and Docker Compose V2; offers safe automated installation if missing.
- **Database Flexibility**:
  - **EC2 PostgreSQL (Default)**: Containerized, isolated on an internal Docker bridge network with automated strong passwords and healthchecks.
  - **Supabase PostgreSQL**: Connect to managed cloud PostgreSQL with SSL, URI validation, and pre-deployment connectivity tests.
- **Two Access Modes**:
  - **AWS Public IP + Port 5678**: Direct, fast deployment with automatic EC2 public IPv4 detection via AWS IMDSv2.
  - **Custom Domain + HTTPS**: Production-grade automated Let's Encrypt TLS certificate issuance and renewal.
- **Modular Reverse Proxies**: Choose between **Nginx** (industry standard) or **Traefik** (cloud-native edge router). Both feature full WebSocket support and robust HTTP-to-HTTPS redirection.
- **Operational CLI (`manage.sh`)**: Check status, start, stop, restart, stream logs, update n8n safely, and uninstall.
- **Zero Secret Exposure**: Passwords and encryption keys are generated using OpenSSL, stored strictly in `.env` with `0600` permissions, and never printed to the terminal.
- **Safe & Idempotent**: Existing deployments are detected with backup safeguards; persistent data is never silently deleted.

---

## Quickstart on AWS EC2

### 1. Launch an EC2 Instance
- **AMI:** Ubuntu Server 24.04 LTS or 22.04 LTS (64-bit x86 or ARM Graviton).
- **Instance Type:** `t3.small` or `t4g.small` recommended (2 GB RAM). `t2.micro` or `t3.micro` (1 GB RAM) can be used if swap is enabled.
- **Storage:** 20 GB gp3 root EBS volume.
- **Security Group Inbound Rules:**
  - **SSH (22):** Your IP address.
  - **If using Public IP:** TCP `5678` (Your IP or restricted CIDR).
  - **If using Custom Domain:** TCP `80` (HTTP) and TCP `443` (HTTPS) from `0.0.0.0/0`.

### 2. Connect and Run the Installer

SSH into your Ubuntu server and run:

```bash
# Clone or download this repository
git clone https://github.com/example/n8n-ec2-deploy.git
cd n8n-ec2-deploy

# Make scripts executable and run the installer
chmod +x install.sh manage.sh uninstall.sh
sudo ./install.sh
```

Follow the on-screen prompts to select your database, access method, and domain settings.

---

## Architecture Overview

```
                      Internet
                         │
        ┌────────────────┴────────────────┐
        │                                 │
   Port 80/443                       Port 5678
  (Custom Domain)                   (Public IP)
        │                                 │
┌───────▼────────────────────────┐        │
│ Reverse Proxy (Nginx / Traefik)│        │
│   (Let's Encrypt TLS/SSL)      │        │
└───────┬────────────────────────┘        │
        │ [n8n-proxy-network]             │
        └────────────────┐   ┌────────────┘
                         │   │
                  ┌──────▼───▼─────┐
                  │      n8n       │
                  │   Automation   │
                  └──────┬─────────┘
                         │ [n8n-internal]
        ┌────────────────┴────────────────┐
        │                                 │
┌───────▼───────┐                 ┌───────▼───────┐
│ EC2 PostgreSQL│                 │   Supabase    │
│  (Container)  │                 │ (Cloud / SSL) │
└───────────────┘                 └───────────────┘
```

For in-depth architectural details and provider interfaces, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Managing Your Deployment

Once deployed, n8n is located in `/opt/applications/n8n/`. You can manage it at any time using:

```bash
sudo /opt/applications/n8n/manage.sh
```

Or pass commands non-interactively:

```bash
sudo /opt/applications/n8n/manage.sh status     # Check container states and health
sudo /opt/applications/n8n/manage.sh start      # Start services
sudo /opt/applications/n8n/manage.sh stop       # Stop services safely
sudo /opt/applications/n8n/manage.sh restart    # Restart services
sudo /opt/applications/n8n/manage.sh logs       # View real-time logs
sudo /opt/applications/n8n/manage.sh update     # Update n8n image version
sudo /opt/applications/n8n/manage.sh uninstall  # Safe uninstallation wizard
```

---

## Directory Structure

```
/opt/applications/n8n/
├── docker-compose.yml     # Application compose file
├── .env                   # Environment & secrets (chmod 600)
├── README.md              # Deployment summary
├── manage.sh              # Management utility
├── uninstall.sh           # Safe uninstaller
├── data/
│   └── n8n/               # Persistent workflow & execution data
├── postgres/
│   └── data/              # PostgreSQL data (if local DB chosen)
├── proxy/                 # Reverse proxy configuration (if domain chosen)
│   ├── docker-compose.yml
│   └── config/
└── logs/
```

---

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): Technical architecture, security model, and provider contracts.
- [docs/INSTALLATION.md](docs/INSTALLATION.md): Detailed installation guide, AWS setup, and DNS configuration.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md): Solutions for common Docker, DNS, SSL, database, and AWS Security Group issues.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

