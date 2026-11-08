#!/usr/bin/env bash
# ==============================================================================
# Validation Utilities
# ==============================================================================

# Validate FQDN (Fully Qualified Domain Name)
validate_domain() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        return 1
    fi

    # Reject protocol prefixes and paths/ports
    if [[ "$domain" =~ :// || "$domain" =~ / || "$domain" =~ : ]]; then
        return 1
    fi

    # Domain regex matching RFC 1035 / RFC 1123
    local regex="^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"
    if [[ "$domain" =~ $regex ]]; then
        return 0
    else
        return 1
    fi
}

# Validate Email address format
validate_email() {
    local email="$1"
    local regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    if [[ "$email" =~ $regex ]]; then
        return 0
    else
        return 1
    fi
}

# Validate IPv4 address
validate_ipv4() {
    local ip="$1"
    local regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"

    if [[ ! "$ip" =~ $regex ]]; then
        return 1
    fi

    local IFS='.'
    read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if (( octet < 0 || octet > 255 )); then
            return 1
        fi
    done

    return 0
}

# Validate TCP port (1-65535)
validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
        return 0
    fi
    return 1
}

# Parse and validate PostgreSQL Connection URI
# Supports: postgresql://[user[:password]@]host[:port][/database][?params]
# Sets PARSED_DB_* global variables without echoing secrets
parse_postgres_uri() {
    local uri="$1"

    # Reset parsed variables
    PARSED_DB_USER=""
    PARSED_DB_PASSWORD=""
    PARSED_DB_HOST=""
    PARSED_DB_PORT="5432"
    PARSED_DB_DATABASE=""
    PARSED_DB_SSLMODE="require"

    if [[ -z "$uri" ]]; then
        return 1
    fi

    # Check scheme
    local scheme_regex="^(postgres|postgresql)://"
    if [[ ! "$uri" =~ $scheme_regex ]]; then
        return 1
    fi

    # Strip scheme
    local clean_uri="${uri#*://}"

    # Extract query params if present
    local params=""
    if [[ "$clean_uri" == *"?"* ]]; then
        params="${clean_uri#*\?}"
        clean_uri="${clean_uri%%\?*}"
    fi

    # Extract user:password if present
    local auth=""
    local host_port_db="$clean_uri"
    if [[ "$clean_uri" == *"@"* ]]; then
        auth="${clean_uri%%@*}"
        host_port_db="${clean_uri#*@}"
    fi

    if [[ -n "$auth" ]]; then
        if [[ "$auth" == *":"* ]]; then
            PARSED_DB_USER="${auth%%:*}"
            PARSED_DB_PASSWORD="${auth#*:}"
        else
            PARSED_DB_USER="$auth"
        fi
    fi

    # Extract database name if present
    local host_port="$host_port_db"
    if [[ "$host_port_db" == *"/"* ]]; then
        host_port="${host_port_db%%/*}"
        PARSED_DB_DATABASE="${host_port_db#*/}"
    fi

    # Extract host and port
    if [[ "$host_port" == *":"* ]]; then
        PARSED_DB_HOST="${host_port%%:*}"
        PARSED_DB_PORT="${host_port#*:}"
    else
        PARSED_DB_HOST="$host_port"
    fi

    # Parse sslmode parameter if present
    if [[ -n "$params" ]]; then
        local IFS='&'
        read -r -a query_pairs <<< "$params"
        for pair in "${query_pairs[@]}"; do
            local key="${pair%%=*}"
            local val="${pair#*=}"
            if [[ "$key" == "sslmode" ]]; then
                PARSED_DB_SSLMODE="$val"
            fi
        done
    fi

    # Validate essential fields
    if [[ -z "$PARSED_DB_HOST" || -z "$PARSED_DB_USER" ]]; then
        return 1
    fi

    # If no database name was specified, default to postgres
    if [[ -z "$PARSED_DB_DATABASE" ]]; then
        PARSED_DB_DATABASE="postgres"
    fi

    # Validate port number
    if ! validate_port "$PARSED_DB_PORT"; then
        return 1
    fi

    return 0
}

# Resolve domain name to IPv4 and compare against expected EC2 public IP
validate_dns_resolution() {
    local domain="$1"
    local expected_ip="$2"
    local resolved_ips=()

    # Method 1: getent hosts
    if command -v getent >/dev/null 2>&1; then
        while read -r ip _; do
            if validate_ipv4 "$ip"; then
                resolved_ips+=("$ip")
            fi
        done < <(getent ahosts "$domain" 2>/dev/null | awk '{print $1}')
    fi

    # Method 2: dig (dnsutils)
    if [[ ${#resolved_ips[@]} -eq 0 ]] && command -v dig >/dev/null 2>&1; then
        while read -r ip; do
            if validate_ipv4 "$ip"; then
                resolved_ips+=("$ip")
            fi
        done < <(dig +short "$domain" A 2>/dev/null)
    fi

    # Method 3: host
    if [[ ${#resolved_ips[@]} -eq 0 ]] && command -v host >/dev/null 2>&1; then
        while read -r ip; do
            if validate_ipv4 "$ip"; then
                resolved_ips+=("$ip")
            fi
        done < <(host -t A "$domain" 2>/dev/null | awk '/has address/ {print $NF}')
    fi

    # Method 4: DNS-over-HTTPS fallback via curl
    if [[ ${#resolved_ips[@]} -eq 0 ]] && command -v curl >/dev/null 2>&1; then
        local doh_resp
        doh_resp=$(curl -s -m 5 -H "accept: application/dns-json" "https://cloudflare-dns.com/dns-query?name=${domain}&type=A" 2>/dev/null || true)
        if [[ -n "$doh_resp" ]]; then
            # Extract IPs from JSON response
            while read -r ip; do
                if validate_ipv4 "$ip"; then
                    resolved_ips+=("$ip")
                fi
            done < <(echo "$doh_resp" | grep -oE '"data":"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | cut -d'"' -f4)
        fi
    fi

    # Deduplicate resolved IPs
    local unique_ips=()
    for ip in "${resolved_ips[@]}"; do
        local exists=0
        for u in "${unique_ips[@]}"; do
            if [[ "$u" == "$ip" ]]; then
                exists=1
                break
            fi
        done
        if [[ $exists -eq 0 ]]; then
            unique_ips+=("$ip")
        fi
    done

    RESOLVED_DNS_IPS=("${unique_ips[@]}")

    if [[ ${#unique_ips[@]} -eq 0 ]]; then
        return 1 # No DNS A records found
    fi

    # Check if expected IP matches any of the resolved IPs
    for ip in "${unique_ips[@]}"; do
        if [[ "$ip" == "$expected_ip" ]]; then
            return 0
        fi
    done

    return 2 # Resolved to IP, but does not match expected EC2 public IP
}

