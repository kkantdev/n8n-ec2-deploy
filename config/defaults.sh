#!/usr/bin/env bash
# ==============================================================================
# n8n EC2 Deploy - Default Configuration
# ==============================================================================

# Application branding
export APP_NAME="n8n EC2 Deploy"
export APP_VERSION="1.0.0"

# Target deployment directory
export INSTALL_DIR="${INSTALL_DIR:-/opt/applications/n8n}"

# Pinned Docker image versions (Avoid using unpinned 'latest' in production)
export N8N_IMAGE_NAME="${N8N_IMAGE_NAME:-n8nio/n8n}"
export N8N_IMAGE_TAG="${N8N_IMAGE_TAG:-1.76.0}"

export POSTGRES_IMAGE_NAME="${POSTGRES_IMAGE_NAME:-postgres}"
export POSTGRES_IMAGE_TAG="${POSTGRES_IMAGE_TAG:-16-alpine}"

export NGINX_IMAGE_NAME="${NGINX_IMAGE_NAME:-nginx}"
export NGINX_IMAGE_TAG="${NGINX_IMAGE_TAG:-1.27-alpine}"

export CERTBOT_IMAGE_NAME="${CERTBOT_IMAGE_NAME:-certbot/certbot}"
export CERTBOT_IMAGE_TAG="${CERTBOT_IMAGE_TAG:-v3.1.0}"

export TRAEFIK_IMAGE_NAME="${TRAEFIK_IMAGE_NAME:-traefik}"
export TRAEFIK_IMAGE_TAG="${TRAEFIK_IMAGE_TAG:-v3.2}"

# Docker network definitions
export DOCKER_INTERNAL_NETWORK="${DOCKER_INTERNAL_NETWORK:-n8n-internal}"
export DOCKER_PROXY_NETWORK="${DOCKER_PROXY_NETWORK:-n8n-proxy-network}"

# Port settings
export N8N_INTERNAL_PORT="5678"
export N8N_HOST_PORT="${N8N_HOST_PORT:-5678}"
export HTTP_PORT="${HTTP_PORT:-80}"
export HTTPS_PORT="${HTTPS_PORT:-443}"

# System requirements
export MIN_DISK_SPACE_MB=3072 # 3GB free space recommended
export MIN_RAM_MB=1024        # 1GB minimum RAM recommended for n8n + postgres

# Health check & timeouts
export HEALTH_CHECK_TIMEOUT=180
export HEALTH_CHECK_INTERVAL=5

# n8n runtime defaults
export DEFAULT_TIMEZONE="UTC"
export DEFAULT_EXECUTIONS_DATA_PRUNE="true"
export DEFAULT_EXECUTIONS_DATA_MAX_AGE="336" # 14 days in hours

