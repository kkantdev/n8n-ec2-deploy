# AWS EC2 Installation Guide

This guide walks you through deploying **n8n** on an **AWS EC2 Ubuntu Server** from scratch.

---

## 1. AWS EC2 Instance Provisioning

### Recommended Specifications
- **Operating System:** Ubuntu Server 24.04 LTS or 22.04 LTS (64-bit x86 or ARM64 Graviton).
- **Instance Type:**
  - Recommended: `t3.small` or `t4g.small` (2 vCPU, 2 GB RAM).
  - Minimum: `t3.micro` or `t2.micro` (1 GB RAM) — *requires configuring swap memory*.
- **Storage:** At least 20 GB gp3 root volume.

---

## 2. AWS Security Group Configuration

Configure your EC2 Security Group inbound rules based on your planned access method:

### Mode A: Public IP + Port 5678
| Type | Protocol | Port Range | Source | Purpose |
|---|---|---|---|---|
| SSH | TCP | 22 | Your IP / CIDR | Remote management |
| Custom TCP | TCP | 5678 | Your IP or `0.0.0.0/0` | n8n Web UI & Webhooks |

### Mode B: Custom Domain + HTTPS (Nginx or Traefik)
| Type | Protocol | Port Range | Source | Purpose |
|---|---|---|---|---|
| SSH | TCP | 22 | Your IP / CIDR | Remote management |
| HTTP | TCP | 80 | `0.0.0.0/0` | Let's Encrypt ACME & HTTP redirect |
| HTTPS | TCP | 443 | `0.0.0.0/0` | Secure n8n Web UI & Webhooks |

> [!IMPORTANT]
> Port 80 is required by Let's Encrypt for HTTP-01 challenge certificate issuance and renewal, even if all your traffic is served over HTTPS.

---

## 3. DNS Configuration (For Custom Domain Mode)

If you plan to use a custom domain (e.g., `automation.yourdomain.com`):

1. Find your EC2 instance's **Public IPv4 address** in the AWS EC2 Management Console.
2. In your DNS provider (Route 53, Cloudflare, Namecheap, etc.), create an **A Record**:
   - **Type:** `A`
   - **Name:** `automation` (or your chosen subdomain)
   - **Value / Target:** Your EC2 Public IPv4 address
   - **TTL:** 300 seconds (or Auto)
3. Allow 1-2 minutes for DNS propagation before running the installer.

---

## 4. Running the Installer

1. **SSH into your EC2 server:**
   ```bash
   ssh -i /path/to/your-key.pem ubuntu@<EC2_PUBLIC_IP>
   ```

2. **Clone the repository:**
   ```bash
   git clone https://github.com/example/n8n-ec2-deploy.git
   cd n8n-ec2-deploy
   ```

3. **Make scripts executable:**
   ```bash
   chmod +x install.sh manage.sh uninstall.sh
   ```

4. **Launch the interactive wizard:**
   ```bash
   sudo ./install.sh
   ```

---

## 5. Installation Wizard Walkthrough

### Step 1: Pre-flight Verification
The installer automatically checks:
- OS distribution (Ubuntu 22.04/24.04).
- CPU architecture.
- Available disk space (>= 3 GB).
- RAM (warnings displayed if < 1 GB).
- Outbound internet access.
- EC2 public IP address discovery via AWS IMDSv2.
- Docker & Docker Compose V2 (installs them automatically if missing).

### Step 2: Database Selection
- **Option 1: PostgreSQL on this EC2 server (Recommended)**:
  Completely automated. The installer generates a strong 32-character password, creates an isolated container, mounts persistent storage, and configures internal networking.
- **Option 2: Existing Supabase PostgreSQL**:
  Enter your Supabase connection string (`postgresql://postgres.[ref]:[pass]@[host]:5432/postgres?sslmode=require`). The installer parses the URI, tests live connectivity using an ephemeral container, verifies schema privileges, and handles SSL.

### Step 3: Access Method Selection
- **Option 1: AWS Public IP + Port 5678**:
  Configures n8n to listen directly on `http://<EC2_PUBLIC_IP>:5678`.
- **Option 2: Custom Domain + HTTPS**:
  - Enter your domain name. The installer tests your DNS A record against your EC2 public IP.
  - Enter your email address for Let's Encrypt certificate renewal alerts.
  - Select your reverse proxy: **Nginx** or **Traefik**.

### Step 4: Automated Deployment & Verification
The installer:
1. Generates `.env` with strict `0600` permissions.
2. Generates the tailored `docker-compose.yml`.
3. Creates persistent data directories with appropriate file ownership (`1000:1000` for n8n, `700` for postgres).
4. Pulls official container images.
5. Launches containers and waits for database health and n8n migration completion.
6. Verifies the public endpoint.

---

## 6. Accessing n8n

When the wizard finishes, you will see the success screen:

```
================================================================
                   DEPLOYMENT SUCCESSFUL!                       
================================================================

  n8n Access URL:        https://automation.example.com
  Deployment Directory:  /opt/applications/n8n/
  Management Command:    sudo /opt/applications/n8n/manage.sh
================================================================
```

Open the URL in your web browser to set up your initial n8n owner account (email and password).

