#!/usr/bin/env python3
"""
Test Docker Compose generation logic across all 6 deployment scenarios:
- Scenario A: EC2 PostgreSQL + Public IP + Port 5678
- Scenario B: EC2 PostgreSQL + Custom Domain + Nginx
- Scenario C: EC2 PostgreSQL + Custom Domain + Traefik
- Scenario D: Supabase PostgreSQL + Public IP + Port 5678
- Scenario E: Supabase PostgreSQL + Custom Domain + Nginx
- Scenario F: Supabase PostgreSQL + Custom Domain + Traefik
"""

import unittest
import os
import tempfile

def simulate_compose_generator(db_provider: str, access_method: str, proxy_provider: str) -> str:
    lines = [
        "services:",
        "  n8n:",
        "    image: n8nio/n8n:1.76.0",
        "    container_name: n8n",
        "    restart: unless-stopped",
        "    env_file:",
        "      - .env",
    ]

    if access_method == "public-ip":
        lines.extend([
            "    ports:",
            '      - "5678:5678"',
        ])

    lines.extend([
        "    volumes:",
        "      - ./data/n8n:/home/node/.n8n",
        "    networks:",
    ])

    if db_provider == "ec2-postgres":
        lines.append("      - n8n-internal")
    if access_method == "custom-domain":
        lines.append("      - n8n-proxy-network")
    if db_provider == "supabase" and access_method == "public-ip":
        lines.append("      - n8n-internal")

    if db_provider == "ec2-postgres":
        lines.extend([
            "    depends_on:",
            "      postgres:",
            "        condition: service_healthy",
        ])

    lines.extend([
        "    healthcheck:",
        '      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:5678/healthz || exit 1"]',
        "      interval: 10s",
        "      timeout: 5s",
        "      retries: 5",
        "      start_period: 30s",
    ])

    if db_provider == "ec2-postgres":
        lines.extend([
            "",
            "  postgres:",
            "    image: postgres:16-alpine",
            "    container_name: n8n-postgres",
            "    restart: unless-stopped",
            "    env_file:",
            "      - .env",
            "    environment:",
            "      POSTGRES_DB: ${DB_POSTGRESDB_DATABASE:-n8n}",
            "      POSTGRES_USER: ${DB_POSTGRESDB_USER:-n8n}",
            "      POSTGRES_PASSWORD: ${DB_POSTGRESDB_PASSWORD}",
            "      PGDATA: /var/lib/postgresql/data/pgdata",
            "    volumes:",
            "      - ./postgres/data:/var/lib/postgresql/data",
            "    networks:",
            "      - n8n-internal",
            "    healthcheck:",
            '      test: ["CMD-SHELL", "pg_isready -h localhost -U ${DB_POSTGRESDB_USER:-n8n} -d ${DB_POSTGRESDB_DATABASE:-n8n}"]',
            "      interval: 5s",
            "      timeout: 5s",
            "      retries: 10",
            "      start_period: 10s",
        ])

    lines.extend([
        "",
        "networks:",
    ])

    if db_provider == "ec2-postgres" or (db_provider == "supabase" and access_method == "public-ip"):
        lines.extend([
            "  n8n-internal:",
            "    driver: bridge",
        ])

    if access_method == "custom-domain":
        lines.extend([
            "  n8n-proxy-network:",
            "    external: true",
        ])

    return "\n".join(lines) + "\n"


class TestComposeGeneration(unittest.TestCase):
    def test_scenario_a_ec2_postgres_public_ip(self):
        compose = simulate_compose_generator("ec2-postgres", "public-ip", "none")
        self.assertIn("image: n8nio/n8n:1.76.0", compose)
        self.assertIn('"5678:5678"', compose) # Host port exposed
        self.assertIn("postgres:", compose)   # Local DB included
        self.assertIn("condition: service_healthy", compose)
        self.assertIn("n8n-internal:", compose)
        self.assertNotIn("n8n-proxy-network:", compose) # No proxy network

    def test_scenario_b_ec2_postgres_domain_nginx(self):
        compose = simulate_compose_generator("ec2-postgres", "custom-domain", "nginx")
        self.assertIn("image: n8nio/n8n:1.76.0", compose)
        self.assertNotIn('"5678:5678"', compose) # Port 5678 NOT exposed to host!
        self.assertIn("postgres:", compose)
        self.assertIn("n8n-proxy-network:", compose)
        self.assertIn("n8n-internal:", compose)

    def test_scenario_c_ec2_postgres_domain_traefik(self):
        compose = simulate_compose_generator("ec2-postgres", "custom-domain", "traefik")
        self.assertNotIn('"5678:5678"', compose)
        self.assertIn("postgres:", compose)
        self.assertIn("n8n-proxy-network:", compose)

    def test_scenario_d_supabase_public_ip(self):
        compose = simulate_compose_generator("supabase", "public-ip", "none")
        self.assertIn('"5678:5678"', compose)
        self.assertNotIn("postgres:", compose) # No local postgres container!
        self.assertNotIn("depends_on:", compose)

    def test_scenario_e_supabase_domain_nginx(self):
        compose = simulate_compose_generator("supabase", "custom-domain", "nginx")
        self.assertNotIn('"5678:5678"', compose)
        self.assertNotIn("postgres:", compose)
        self.assertIn("n8n-proxy-network:", compose)

    def test_scenario_f_supabase_domain_traefik(self):
        compose = simulate_compose_generator("supabase", "custom-domain", "traefik")
        self.assertNotIn('"5678:5678"', compose)
        self.assertNotIn("postgres:", compose)
        self.assertIn("n8n-proxy-network:", compose)

if __name__ == "__main__":
    unittest.main()
