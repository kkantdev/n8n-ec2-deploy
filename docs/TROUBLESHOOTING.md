# Troubleshooting Guide

This guide covers common issues encountered when deploying and managing n8n on AWS EC2, along with practical diagnostic commands and fixes.

---

## Quick Diagnostics

Check your deployment status and container logs:

```bash
# View overall system status
sudo /opt/applications/n8n/manage.sh status

# View live n8n logs
sudo /opt/applications/n8n/manage.sh logs

# Inspect running containers directly
docker ps -a
```

---

## 1. Port Conflicts

### Symptom
The installer warns that port `5678`, `80`, or `443` is already in use, or Docker fails with `bind: address already in use`.

### Diagnosis
Identify the conflicting process listening on the port:
```bash
sudo ss -tulnp | grep -E ':(80|443|5678)'
```

### Common Causes & Fixes
- **Apache2 or Nginx already installed on host OS:**
  ```bash
  sudo systemctl stop apache2 nginx 2>/dev/null || true
  sudo systemctl disable apache2 nginx 2>/dev/null || true
  ```
- **Old container holding the port:**
  ```bash
  docker ps -q --filter "publish=80" | xargs -r docker stop
  docker ps -q --filter "publish=443" | xargs -r docker stop
  docker ps -q --filter "publish=5678" | xargs -r docker stop
  ```

---

## 2. AWS Security Group & Network Connectivity

### Symptom
n8n is running healthy inside Docker, but you cannot connect via your browser (`ERR_CONNECTION_TIMED_OUT` or `Connection refused`).

### Fixes
1. **Verify AWS Security Group Inbound Rules:**
   - In the AWS EC2 Management Console, locate your instance -> **Security** -> **Security groups**.
   - For Public IP access: Ensure **Inbound TCP 5678** is allowed.
   - For Custom Domain: Ensure **Inbound TCP 80** and **TCP 443** are allowed from `0.0.0.0/0`.
2. **Verify Public IP / Elastic IP:**
   - AWS EC2 dynamic public IPs change if the instance is stopped and restarted.
   - To prevent IP changes, attach an **Elastic IP** in AWS.
3. **Verify VPC Route Table:**
   - Ensure your EC2 subnet has an Internet Gateway (`igw-...`) attached in its route table (`0.0.0.0/0 -> igw`).

---

## 3. Out-of-Memory (OOM) Errors on Small EC2 Instances

### Symptom
n8n crashes during startup with `Exit code 137` (Killed by Linux OOM killer), especially on `t2.micro` or `t3.micro` (1 GB RAM).

### Diagnosis
Check kernel logs for OOM killer events:
```bash
dmesg -T | grep -i -E "oom|killed process"
```

### Fix: Add a 2 GB Swap File
Run the following commands to add virtual memory:
```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent across reboots
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## 4. Local PostgreSQL Issues

### Symptom
PostgreSQL container status is `unhealthy` or constantly restarting.

### Diagnosis
Inspect PostgreSQL container logs:
```bash
docker logs --tail=100 n8n-postgres
```

### Common Causes & Fixes
- **File permission error on data directory:**
  PostgreSQL requires strict ownership (`999:999` or `root` inside alpine) and `0700` permissions.
  ```bash
  sudo chmod 700 /opt/applications/n8n/postgres/data
  ```
- **Corrupted transaction log or unclean shutdown:**
  Check disk space (`df -h /opt`). If the disk is full, expand your EBS volume.

---

## 5. Supabase PostgreSQL Connection Issues

### Symptom
The installer fails to verify Supabase connectivity, or n8n fails during startup schema migrations.

### Common Causes & Fixes
- **Transaction Pooler vs Session Pooler:**
  Supabase provides two pooler ports on `pooler.supabase.com`:
  - Port `6543` (Transaction mode): Incompatible with n8n migrations (fails with prepared statement errors).
  - Port `5432` (Session mode): **Required for n8n migrations**. Ensure you connect using port `5432`.
- **IPv4 vs IPv6:**
  Supabase direct connections (`db.[project-ref].supabase.co`) use IPv6 only by default unless the Supabase IPv4 add-on is purchased. If your EC2 instance is IPv4-only, use the Supabase **Connection Pooler** address (`aws-0-[region].pooler.supabase.com:5432`), which supports IPv4 out-of-the-box.
- **SSL Verification:**
  Supabase mandates SSL. Ensure `?sslmode=require` is present in your URI and `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=true` in `.env`.

---

## 6. Let's Encrypt & Certbot SSL Failures

### Symptom
Certbot fails with `Fetching http://yourdomain.com/.well-known/acme-challenge/...: Timeout during connect`.

### Diagnosis & Fixes
1. **Check DNS Propagation:**
   Confirm that your domain resolves to your EC2 public IP from the outside world:
   ```bash
   dig +short yourdomain.com A
   # or
   curl -s "https://cloudflare-dns.com/dns-query?name=yourdomain.com&type=A" -H "accept: application/dns-json"
   ```
2. **Verify Inbound Port 80 in AWS:**
   Let's Encrypt requires port 80 to be publicly accessible worldwide to complete the ACME HTTP-01 challenge.
3. **Re-run Certificate Issuance:**
   If DNS has propagated now, re-trigger Certbot:
   ```bash
   cd /opt/applications/n8n/proxy
   docker compose run --rm certbot certonly \
       --webroot -w /var/www/certbot \
       -d yourdomain.com \
       --email your-email@example.com \
       --agree-tos --no-eff-email --force-renewal

   # Reload Nginx
   docker compose exec nginx nginx -s reload
   ```

---

## 7. Traefik Reverse Proxy Issues

### Symptom
Traefik returns `404 page not found` or does not issue certificates.

### Diagnosis & Fixes
1. **Check Traefik container logs:**
   ```bash
   docker logs --tail=100 n8n-proxy-traefik
   ```
2. **Verify `acme.json` permissions:**
   Traefik strictly requires `acme.json` to have `0600` permissions. If permissions are wrong, Traefik ignores the certificate resolver:
   ```bash
   sudo chmod 600 /opt/applications/n8n/proxy/letsencrypt/acme.json
   sudo docker compose -f /opt/applications/n8n/proxy/docker-compose.yml restart
   ```
3. **Verify Host Rule in dynamic config:**
   Inspect `/opt/applications/n8n/proxy/dynamic/n8n.yml` to verify that `Host(\`yourdomain.com\`)` matches the exact domain you are requesting in your browser.

---

## 8. WebSocket Disconnections in n8n UI

### Symptom
The n8n editor shows "Connection lost" or execution canvas live updates fail.

### Fix
n8n requires full WebSocket support. Both Nginx and Traefik configurations generated by this installer include WebSocket proxy headers:
- `Upgrade: $http_upgrade`
- `Connection: "upgrade"`
- Long proxy timeouts (`3600s`).
Ensure you have not inserted an intermediary proxy (such as Cloudflare with WebSockets disabled) that drops WebSocket frames.

