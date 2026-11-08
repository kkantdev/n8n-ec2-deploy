#!/usr/bin/env bash
# ==============================================================================
# Docker Compose Generator
# Generates tailor-made docker-compose.yml based on user selections
# ==============================================================================

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../config/defaults.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

generate_docker_compose() {
    local target_dir="${1:-$INSTALL_DIR}"
    local output_file="${target_dir}/docker-compose.yml"

    local db_provider="${SELECTED_DB_PROVIDER:-ec2-postgres}"
    local access_method="${SELECTED_ACCESS_METHOD:-public-ip}"
    local proxy_provider="${SELECTED_PROXY_PROVIDER:-none}"

    log_step "Generating tailor-made Docker Compose configuration..."
    mkdir -p "$target_dir"

    # Temporary file for assembling compose configuration
    local tmp_file
    tmp_file="$(mktemp)"

    cat <<EOF > "$tmp_file"
# ==============================================================================
# n8n EC2 Deploy - Docker Compose Configuration
# Mode: Database=${db_provider} | Access=${access_method} | Proxy=${proxy_provider}
# Generated on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# ==============================================================================

services:
  n8n:
    image: ${N8N_IMAGE_NAME}:${N8N_IMAGE_TAG}
    container_name: n8n
    restart: unless-stopped
    env_file:
      - .env
EOF

    # Configure Ports based on access method
    if [[ "$access_method" == "public-ip" ]]; then
        cat <<EOF >> "$tmp_file"
    ports:
      - "${N8N_HOST_PORT:-5678}:5678"
EOF
    fi

    # Persistent Volume Mount
    cat <<EOF >> "$tmp_file"
    volumes:
      - ./data/n8n:/home/node/.n8n
EOF

    # Configure Networks for n8n service
    cat <<EOF >> "$tmp_file"
    networks:
EOF

    if [[ "$db_provider" == "ec2-postgres" ]]; then
        cat <<EOF >> "$tmp_file"
      - ${DOCKER_INTERNAL_NETWORK}
EOF
    fi

    if [[ "$access_method" == "custom-domain" ]]; then
        cat <<EOF >> "$tmp_file"
      - ${DOCKER_PROXY_NETWORK}
EOF
    fi

    # If Supabase and Public IP, use internal network for container bridge
    if [[ "$db_provider" == "supabase" && "$access_method" == "public-ip" ]]; then
        cat <<EOF >> "$tmp_file"
      - ${DOCKER_INTERNAL_NETWORK}
EOF
    fi

    # Configure Service Dependencies
    if [[ "$db_provider" == "ec2-postgres" ]]; then
        cat <<EOF >> "$tmp_file"
    depends_on:
      postgres:
        condition: service_healthy
EOF
    fi

    # Add Healthcheck for n8n
    cat <<EOF >> "$tmp_file"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:5678/healthz || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
EOF

    # Add PostgreSQL service if EC2 local postgres selected
    if [[ "$db_provider" == "ec2-postgres" ]]; then
        cat <<EOF >> "$tmp_file"

  postgres:
    image: ${POSTGRES_IMAGE_NAME}:${POSTGRES_IMAGE_TAG}
    container_name: n8n-postgres
    restart: unless-stopped
    env_file:
      - .env
    environment:
      POSTGRES_DB: \${DB_POSTGRESDB_DATABASE:-n8n}
      POSTGRES_USER: \${DB_POSTGRESDB_USER:-n8n}
      POSTGRES_PASSWORD: \${DB_POSTGRESDB_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ./postgres/data:/var/lib/postgresql/data
    networks:
      - ${DOCKER_INTERNAL_NETWORK}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h localhost -U \${DB_POSTGRESDB_USER:-n8n} -d \${DB_POSTGRESDB_DATABASE:-n8n}"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 10s
EOF
    fi

    # Network Definitions
    cat <<EOF >> "$tmp_file"

networks:
EOF

    if [[ "$db_provider" == "ec2-postgres" || ("$db_provider" == "supabase" && "$access_method" == "public-ip") ]]; then
        cat <<EOF >> "$tmp_file"
  ${DOCKER_INTERNAL_NETWORK}:
    driver: bridge
EOF
    fi

    if [[ "$access_method" == "custom-domain" ]]; then
        cat <<EOF >> "$tmp_file"
  ${DOCKER_PROXY_NETWORK}:
    external: true
EOF
    fi

    # Move generated configuration to target location
    mv "$tmp_file" "$output_file"
    chmod 644 "$output_file"

    log_success "Docker Compose file generated: ${output_file}"
    return 0
}

