#!/bin/bash

# Matrix On-Premise Setup Script
# This script automates the initial setup of Matrix Synapse with Element Web, Synapse Admin, and Coturn

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate domain format
validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    # Check basic format
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    # Validate each octet is 0-255
    local IFS='.'
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        if ((octet > 255)); then
            return 1
        fi
    done
    return 0
}

# Function to validate port number
validate_port() {
    local port=$1
    if [[ ! $port =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
        return 1
    fi
    return 0
}

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Constants
LIVEKIT_JWT_PORT=8083
LIVEKIT_SFU_PORT=7880

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Matrix On-Premise Setup - Samsesh Chat                  ║"
echo "║   Automated Installation Script                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
print_info "Checking prerequisites..."

if ! command_exists docker; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command_exists docker compose; then
    print_error "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

print_success "All prerequisites met!"
echo ""

# Get server information
print_info "=== Server Configuration ==="
echo ""

read -p "Enter your server's public IP address: " SERVER_IP
while ! validate_ip "$SERVER_IP"; do
    print_error "Invalid IP address format."
    read -p "Enter your server's public IP address: " SERVER_IP
done

read -p "Enter your Matrix server domain (e.g., matrix.example.com) [default: localhost]: " MATRIX_DOMAIN
MATRIX_DOMAIN=${MATRIX_DOMAIN:-localhost}

if [ "$MATRIX_DOMAIN" != "localhost" ]; then
    while ! validate_domain "$MATRIX_DOMAIN"; do
        print_error "Invalid domain format."
        read -p "Enter your Matrix server domain: " MATRIX_DOMAIN
    done
fi

# Generate secure passwords
print_info "Generating secure passwords..."
COTURN_SECRET=$(generate_password)
print_success "Coturn secret generated"

# Generate LiveKit credentials
LIVEKIT_KEY=$(openssl rand -hex 32)
LIVEKIT_SECRET=$(openssl rand -hex 32)
print_success "LiveKit credentials generated"

echo ""
print_info "=== Admin User Configuration ==="
echo ""

read -p "Enter admin username: " ADMIN_USERNAME
while [ -z "$ADMIN_USERNAME" ]; do
    print_error "Username cannot be empty."
    read -p "Enter admin username: " ADMIN_USERNAME
done

read -sp "Enter admin password (min 8 characters): " ADMIN_PASSWORD
echo ""
while [ -z "$ADMIN_PASSWORD" ] || [ ${#ADMIN_PASSWORD} -lt 8 ]; do
    if [ -z "$ADMIN_PASSWORD" ]; then
        print_error "Password cannot be empty."
    else
        print_error "Password must be at least 8 characters long."
    fi
    read -sp "Enter admin password (min 8 characters): " ADMIN_PASSWORD
    echo ""
done

echo ""
print_info "=== Security Configuration ==="
echo ""

read -p "Enable open user registration? (yes/no) [default: no]: " ENABLE_REGISTRATION
ENABLE_REGISTRATION=${ENABLE_REGISTRATION:-no}

echo ""
print_info "=== System Configuration ==="
echo ""

read -p "Enter timezone [default: UTC]: " TIMEZONE
TIMEZONE=${TIMEZONE:-UTC}

# Validate timezone
if [ "$TIMEZONE" != "UTC" ]; then
    # Check if timezone exists in system
    if [ ! -f "/usr/share/zoneinfo/$TIMEZONE" ] && [ ! -d "/usr/share/zoneinfo/$TIMEZONE" ]; then
        print_warning "Timezone '$TIMEZONE' not found in system. Using UTC instead."
        print_info "Examples: America/New_York, Europe/London, Asia/Tokyo"
        TIMEZONE="UTC"
    fi
fi

echo ""
print_info "=== Video Conferencing Configuration ==="
echo ""
echo "Choose your video conferencing service:"
echo "  1) Element Call (Recommended - Self-hosted, fully integrated)"
echo "  2) Jitsi (Uses meet.element.io by default)"
echo ""
read -p "Select option (1 or 2) [default: 1]: " VIDEO_CONF_CHOICE
VIDEO_CONF_CHOICE=${VIDEO_CONF_CHOICE:-1}

while [[ ! "$VIDEO_CONF_CHOICE" =~ ^[12]$ ]]; do
    print_error "Invalid choice. Please enter 1 or 2."
    read -p "Select option (1 or 2) [default: 1]: " VIDEO_CONF_CHOICE
    VIDEO_CONF_CHOICE=${VIDEO_CONF_CHOICE:-1}
done

if [ "$VIDEO_CONF_CHOICE" = "2" ]; then
    read -p "Enter Jitsi domain [default: meet.element.io]: " JITSI_DOMAIN
    JITSI_DOMAIN=${JITSI_DOMAIN:-meet.element.io}
    USE_ELEMENT_CALL="no"
    print_info "Will use Jitsi at: $JITSI_DOMAIN"
else
    USE_ELEMENT_CALL="yes"
    print_info "Will use Element Call for video conferencing"
    
    echo ""
    print_info "=== LiveKit Domain Configuration ==="
    echo ""
    echo "LiveKit services can be accessed via domain names or IP addresses."
    echo "If you have domain names configured, enter them below."
    echo "For local deployments, you can use localhost or your server's IP."
    echo ""
    
    read -p "Enter LiveKit JWT service domain (e.g., livekit-jwt.example.com) [default: localhost]: " LIVEKIT_JWT_DOMAIN
    LIVEKIT_JWT_DOMAIN=${LIVEKIT_JWT_DOMAIN:-localhost}
    
    if [ "$LIVEKIT_JWT_DOMAIN" != "localhost" ] && [ "$LIVEKIT_JWT_DOMAIN" != "$SERVER_IP" ]; then
        while ! validate_domain "$LIVEKIT_JWT_DOMAIN"; do
            print_error "Invalid domain format."
            read -p "Enter LiveKit JWT service domain [default: localhost]: " LIVEKIT_JWT_DOMAIN
            LIVEKIT_JWT_DOMAIN=${LIVEKIT_JWT_DOMAIN:-localhost}
            if [ "$LIVEKIT_JWT_DOMAIN" = "localhost" ] || [ "$LIVEKIT_JWT_DOMAIN" = "$SERVER_IP" ]; then
                break
            fi
        done
    fi
    
    read -p "Enter LiveKit SFU domain (e.g., livekit.example.com) [default: localhost]: " LIVEKIT_DOMAIN
    LIVEKIT_DOMAIN=${LIVEKIT_DOMAIN:-localhost}
    
    if [ "$LIVEKIT_DOMAIN" != "localhost" ] && [ "$LIVEKIT_DOMAIN" != "$SERVER_IP" ]; then
        while ! validate_domain "$LIVEKIT_DOMAIN"; do
            print_error "Invalid domain format."
            read -p "Enter LiveKit SFU domain [default: localhost]: " LIVEKIT_DOMAIN
            LIVEKIT_DOMAIN=${LIVEKIT_DOMAIN:-localhost}
            if [ "$LIVEKIT_DOMAIN" = "localhost" ] || [ "$LIVEKIT_DOMAIN" = "$SERVER_IP" ]; then
                break
            fi
        done
    fi
    
    print_success "LiveKit JWT service will be accessible at: $LIVEKIT_JWT_DOMAIN"
    print_success "LiveKit SFU will be accessible at: $LIVEKIT_DOMAIN"
fi

echo ""
print_info "=== Port Configuration ==="
echo ""

read -p "Element Web port [default: 8080]: " ELEMENT_PORT
ELEMENT_PORT=${ELEMENT_PORT:-8080}
while ! validate_port "$ELEMENT_PORT"; do
    print_error "Invalid port number (must be 1-65535)."
    read -p "Element Web port [default: 8080]: " ELEMENT_PORT
    ELEMENT_PORT=${ELEMENT_PORT:-8080}
done

read -p "Synapse port [default: 8008]: " SYNAPSE_PORT
SYNAPSE_PORT=${SYNAPSE_PORT:-8008}
while ! validate_port "$SYNAPSE_PORT"; do
    print_error "Invalid port number (must be 1-65535)."
    read -p "Synapse port [default: 8008]: " SYNAPSE_PORT
    SYNAPSE_PORT=${SYNAPSE_PORT:-8008}
done

read -p "Synapse federation port [default: 8448]: " FEDERATION_PORT
FEDERATION_PORT=${FEDERATION_PORT:-8448}
while ! validate_port "$FEDERATION_PORT"; do
    print_error "Invalid port number (must be 1-65535)."
    read -p "Synapse federation port [default: 8448]: " FEDERATION_PORT
    FEDERATION_PORT=${FEDERATION_PORT:-8448}
done

read -p "Synapse Admin port [default: 8081]: " ADMIN_PORT
ADMIN_PORT=${ADMIN_PORT:-8081}
while ! validate_port "$ADMIN_PORT"; do
    print_error "Invalid port number (must be 1-65535)."
    read -p "Synapse Admin port [default: 8081]: " ADMIN_PORT
    ADMIN_PORT=${ADMIN_PORT:-8081}
done

if [ "$USE_ELEMENT_CALL" = "yes" ]; then
    read -p "Element Call port [default: 8082]: " ELEMENT_CALL_PORT
    ELEMENT_CALL_PORT=${ELEMENT_CALL_PORT:-8082}
    while ! validate_port "$ELEMENT_CALL_PORT"; do
        print_error "Invalid port number (must be 1-65535)."
        read -p "Element Call port [default: 8082]: " ELEMENT_CALL_PORT
        ELEMENT_CALL_PORT=${ELEMENT_CALL_PORT:-8082}
    done
    
    echo ""
    print_info "LiveKit WebRTC requires a UDP port range for media traffic."
    read -p "WebRTC port range start [default: 50000]: " WEBRTC_PORT_START
    WEBRTC_PORT_START=${WEBRTC_PORT_START:-50000}
    while ! validate_port "$WEBRTC_PORT_START"; do
        print_error "Invalid port number (must be 1-65535)."
        read -p "WebRTC port range start [default: 50000]: " WEBRTC_PORT_START
        WEBRTC_PORT_START=${WEBRTC_PORT_START:-50000}
    done
    
    read -p "WebRTC port range end [default: 60000]: " WEBRTC_PORT_END
    WEBRTC_PORT_END=${WEBRTC_PORT_END:-60000}
    while ! validate_port "$WEBRTC_PORT_END" || [ "$WEBRTC_PORT_END" -le "$WEBRTC_PORT_START" ]; do
        if ! validate_port "$WEBRTC_PORT_END"; then
            print_error "Invalid port number (must be 1-65535)."
        else
            print_error "End port must be greater than start port ($WEBRTC_PORT_START)."
        fi
        read -p "WebRTC port range end [default: 60000]: " WEBRTC_PORT_END
        WEBRTC_PORT_END=${WEBRTC_PORT_END:-60000}
    done
    
    print_success "WebRTC will use UDP ports $WEBRTC_PORT_START-$WEBRTC_PORT_END"
fi

echo ""
print_info "=== Configuration Summary ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Server IP:        $SERVER_IP"
echo "Matrix Domain:    $MATRIX_DOMAIN"
echo "Admin Username:   $ADMIN_USERNAME"
echo "Timezone:         $TIMEZONE"
if [ "$USE_ELEMENT_CALL" = "yes" ]; then
    echo "Video Conf:       Element Call"
else
    echo "Video Conf:       Jitsi ($JITSI_DOMAIN)"
fi
echo "Element Port:     $ELEMENT_PORT"
echo "Synapse Port:     $SYNAPSE_PORT"
echo "Federation Port:  $FEDERATION_PORT"
echo "Admin Panel Port: $ADMIN_PORT"
if [ "$USE_ELEMENT_CALL" = "yes" ]; then
    echo "Element Call Port: $ELEMENT_CALL_PORT"
    echo "LiveKit JWT Domain: $LIVEKIT_JWT_DOMAIN"
    echo "LiveKit SFU Domain: $LIVEKIT_DOMAIN"
fi
echo "Coturn Secret:    [generated - will be saved securely]"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Proceed with installation? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ] && [ "$CONFIRM" != "y" ]; then
    print_warning "Installation cancelled."
    exit 0
fi

echo ""
print_info "Starting installation process..."
echo ""

# Step 1: Configure Coturn
print_info "Step 1/6: Configuring Coturn..."
if [ -f "coturn/turnserver.conf" ]; then
    print_warning "Existing Coturn configuration found."
    read -p "Backup existing config? (yes/no) [yes]: " BACKUP_COTURN
    BACKUP_COTURN=${BACKUP_COTURN:-yes}
    if [ "$BACKUP_COTURN" = "yes" ] || [ "$BACKUP_COTURN" = "y" ]; then
        cp coturn/turnserver.conf "coturn/turnserver.conf.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Backup created"
    fi
fi
cat > coturn/turnserver.conf << EOF
use-auth-secret
static-auth-secret=$COTURN_SECRET
realm=$MATRIX_DOMAIN
listening-port=3478
tls-listening-port=5349
min-port=49160
max-port=49200
verbose
allow-loopback-peers
cli-password=$COTURN_SECRET
external-ip=$SERVER_IP
EOF
chmod 600 coturn/turnserver.conf
print_success "Coturn configuration created (permissions set to 600)"

# Step 2: Download Samsesh logo
print_info "Step 2/6: Downloading Samsesh Chat logo..."
mkdir -p element-theme
LOGO_URL="https://raw.githubusercontent.com/samsesh/samsesh/main/Logo/samseshlogo.png"
if command_exists curl; then
    if curl -sL "$LOGO_URL" -o element-theme/logo.png; then
        print_success "Logo downloaded successfully"
    else
        print_warning "Failed to download logo. You can add it manually later to element-theme/logo.png"
    fi
elif command_exists wget; then
    if wget -q "$LOGO_URL" -O element-theme/logo.png; then
        print_success "Logo downloaded successfully"
    else
        print_warning "Failed to download logo. You can add it manually later to element-theme/logo.png"
    fi
else
    print_warning "Neither curl nor wget found. Skipping logo download."
fi

# Step 3: Create Element configuration
print_info "Step 3/6: Creating Element Web configuration..."

if [ "$MATRIX_DOMAIN" = "localhost" ]; then
    BASE_URL="http://localhost:$SYNAPSE_PORT"
else
    BASE_URL="https://$MATRIX_DOMAIN"
fi

cat > element-config.json << EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "$BASE_URL",
            "server_name": "$MATRIX_DOMAIN"
        },
        "m.identity_server": {
            "base_url": "https://vector.im"
        }
    },
    "brand": "SamSesh Chat",
    "disable_custom_urls": false,
    "disable_guests": true,
    "disable_login_language_selector": false,
    "disable_3pid_login": false,
    "default_theme": "dark",
    "room_directory": {
        "servers": [
            "$MATRIX_DOMAIN"
        ]
    },
    "enable_presence_by_default": true,
    "features": {
        "feature_pinning": "labs",
        "feature_custom_status": "labs",
        "feature_custom_tags": "labs",
        "feature_state_counters": "labs"
    },
    "default_country_code": "US",
    "show_labs_settings": true,
    "integrations_ui_url": "https://scalar.vector.im/",
    "integrations_rest_url": "https://scalar.vector.im/api",
    "integrations_widgets_urls": [
        "https://scalar.vector.im/_matrix/integrations/v1",
        "https://scalar.vector.im/api",
        "https://scalar-staging.vector.im/_matrix/integrations/v1",
        "https://scalar-staging.vector.im/api",
        "https://scalar-staging.riot.im/scalar/api"
    ]
EOF

# Add Jitsi configuration based on choice
if [ "$USE_ELEMENT_CALL" = "yes" ]; then
    cat >> element-config.json << EOF
    ,
    "jitsi": {
        "preferred_domain": "meet.element.io"
    }
EOF
else
    cat >> element-config.json << EOF
    ,
    "jitsi": {
        "preferred_domain": "$JITSI_DOMAIN"
    }
EOF
fi

cat >> element-config.json << EOF
    ,
    "permalink_prefix": "https://samsesh.com",
    "help_url": "https://blog.samsesh.com",
    "bug_report_endpoint_url": "https://github.com/samsesh/matrix-on-premise/issues/new",
    "footer_links": [
        {
            "text": "Website",
            "url": "https://samsesh.com"
        },
        {
            "text": "Blog",
            "url": "https://blog.samsesh.com"
        },
        {
            "text": "Donate",
            "url": "https://samsesh.com/donate"
        }
    ]
}
EOF
print_success "Element configuration created"

# Create Element Call configuration (only if Element Call is chosen)
if [ "$USE_ELEMENT_CALL" = "yes" ]; then
    print_info "Creating Element Call configuration..."
    
    # Define LiveKit JWT service port
    LIVEKIT_JWT_PORT=8083
    
    # Determine the lk-jwt-service URL based on user-provided domain
    if [ "$LIVEKIT_JWT_DOMAIN" = "localhost" ]; then
        LIVEKIT_JWT_URL="http://$SERVER_IP:$LIVEKIT_JWT_PORT"
    else
        # Check if user wants to use HTTPS for production domains
        if [[ "$LIVEKIT_JWT_DOMAIN" != "$SERVER_IP" ]]; then
            LIVEKIT_JWT_URL="https://$LIVEKIT_JWT_DOMAIN"
        else
            LIVEKIT_JWT_URL="http://$LIVEKIT_JWT_DOMAIN:$LIVEKIT_JWT_PORT"
        fi
    fi
    
    cat > element-call-config.json << EOF
{
  "default_server_config": {
    "m.homeserver": {
      "base_url": "$BASE_URL",
      "server_name": "$MATRIX_DOMAIN"
    }
  },
  "org.matrix.msc4143.rtc_foci": [
    {
      "type": "livekit",
      "livekit_service_url": "$LIVEKIT_JWT_URL"
    }
  ]
}
EOF
    print_success "Element Call configuration created with LiveKit support at $LIVEKIT_JWT_URL"
    
    # Update livekit.yaml with generated credentials using a more robust method
    print_info "Configuring LiveKit with secure credentials and port range..."
    # Create a temporary file with the updated keys section and port range
    awk -v key="$LIVEKIT_KEY" -v secret="$LIVEKIT_SECRET" -v port_start="$WEBRTC_PORT_START" -v port_end="$WEBRTC_PORT_END" '
        /^keys:/ { print; getline; printf "  %s: %s\n", key, secret; next }
        /^[[:space:]]*port_range_start:/ { printf "  port_range_start: %s\n", port_start; next }
        /^[[:space:]]*port_range_end:/ { printf "  port_range_end: %s\n", port_end; next }
        { print }
    ' livekit.yaml > livekit.yaml.tmp && mv livekit.yaml.tmp livekit.yaml
    print_success "LiveKit configuration updated with ports $WEBRTC_PORT_START-$WEBRTC_PORT_END"
fi

# Step 4: Update docker-compose.yml with custom ports
print_info "Step 4/6: Updating docker-compose.yml..."
if [ -f "docker-compose.yaml" ]; then
    print_warning "Existing docker-compose.yaml found."
    read -p "Backup existing config? (yes/no) [yes]: " BACKUP_COMPOSE
    BACKUP_COMPOSE=${BACKUP_COMPOSE:-yes}
    if [ "$BACKUP_COMPOSE" = "yes" ] || [ "$BACKUP_COMPOSE" = "y" ]; then
        cp docker-compose.yaml "docker-compose.yaml.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Backup created"
    fi
fi
cat > docker-compose.yaml << EOF
version: '3'
services:
  coturn:
    image: instrumentisto/coturn:latest
    restart: unless-stopped
    volumes:
      - ./coturn/turnserver.conf:/etc/coturn/turnserver.conf
    ports:
      - "49160-49200:49160-49200/udp"
      - "3478:3478"
      - "3478:3478/udp"
      - "5349:5349"
      - "5349:5349/udp"
    healthcheck:
      test: ["CMD", "nc", "-zu", "127.0.0.1", "3478"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    networks:
      - matrix-network

  synapse:
    image: matrixdotorg/synapse:latest
    restart: unless-stopped
    volumes:
      - ./synapse:/data
    ports:
      - "$SYNAPSE_PORT:8008"
      - "$FEDERATION_PORT:8448"
    environment:
      - TZ=\${TZ:-UTC}
      - UID=\${UID:-991}
      - GID=\${GID:-991}
      - SYNAPSE_SERVER_NAME=\${SYNAPSE_SERVER_NAME:-localhost}
      - SYNAPSE_REPORT_STATS=\${SYNAPSE_REPORT_STATS:-yes}
      - SYNAPSE_VOIP_TURN_URIS=["turn:\${TURN_SERVER:-localhost}:3478?transport=udp","turn:\${TURN_SERVER:-localhost}:3478?transport=tcp","turns:\${TURN_SERVER:-localhost}:5349?transport=udp","turns:\${TURN_SERVER:-localhost}:5349?transport=tcp"]
      - SYNAPSE_VOIP_TURN_SHARED_SECRET=\${TURN_SHARED_SECRET:-}
    healthcheck:
      test: ["CMD", "curl", "-fSs", "http://localhost:8008/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    depends_on:
      coturn:
        condition: service_started
    networks:
      - matrix-network

  element:
    image: vectorim/element-web:latest
    restart: unless-stopped
    volumes:
      - ./element-config.json:/app/config.json
      - ./element-theme:/app/themes/samsesh
    ports:
      - "$ELEMENT_PORT:80"
    environment:
      - MATRIX_THEMES=\${MATRIX_THEMES:-light,dark}
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:80/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    depends_on:
      synapse:
        condition: service_started
    networks:
      - matrix-network

  synapse-admin:
    image: awesometechnologies/synapse-admin
    restart: unless-stopped
    ports:
      - "$ADMIN_PORT:80"
    environment:
      - REACT_APP_SERVER=http://synapse:8008
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:80/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    depends_on:
      synapse:
        condition: service_started
    networks:
      - matrix-network
EOF

# Add Element Call and LiveKit services if selected
if [ "$USE_ELEMENT_CALL" = "yes" ]; then
    cat >> docker-compose.yaml << EOF

  lk-jwt-service:
    image: ghcr.io/element-hq/lk-jwt-service:latest
    restart: unless-stopped
    ports:
      - "$LIVEKIT_JWT_PORT:8080"
    environment:
      - LIVEKIT_URL=ws://livekit:7880
      - LIVEKIT_KEY=\${LIVEKIT_KEY:-devkey}
      - LIVEKIT_SECRET=\${LIVEKIT_SECRET:-secret}
      - LIVEKIT_FULL_ACCESS_HOMESERVERS=\${SYNAPSE_SERVER_NAME:-localhost}
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    depends_on:
      synapse:
        condition: service_started
    networks:
      - matrix-network

  element-call:
    image: ghcr.io/element-hq/element-call:latest
    restart: unless-stopped
    ports:
      - "$ELEMENT_CALL_PORT:8080"
    volumes:
      - ./element-call-config.json:/app/config.json
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    depends_on:
      synapse:
        condition: service_started
      lk-jwt-service:
        condition: service_started
    networks:
      - matrix-network

  livekit:
    image: livekit/livekit-server:latest
    restart: unless-stopped
    command: --config /etc/livekit.yaml
    volumes:
      - ./livekit.yaml:/etc/livekit.yaml
    ports:
      - "$LIVEKIT_SFU_PORT:7880"
      - "7881:7881"
      - "7882:7882/udp"
      # WebRTC port range for media traffic
      - "$WEBRTC_PORT_START-$WEBRTC_PORT_END:$WEBRTC_PORT_START-$WEBRTC_PORT_END/udp"
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:7880/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    depends_on:
      synapse:
        condition: service_started
      element:
        condition: service_started
      synapse-admin:
        condition: service_started
    networks:
      - matrix-network
EOF
fi

cat >> docker-compose.yaml << EOF

networks:
  matrix-network:
    name: matrix-network
    driver: bridge
EOF
print_success "docker-compose.yml updated"

# Step 5: Generate Synapse configuration
print_info "Step 5/6: Generating Synapse configuration..."
if [ -d "synapse" ] && [ "$(ls -A synapse)" ]; then
    print_warning "Synapse data directory already exists. Skipping generation."
else
    docker run -i --rm \
        -v "$(pwd)/synapse:/data" \
        -e SYNAPSE_SERVER_NAME="$MATRIX_DOMAIN" \
        -e SYNAPSE_REPORT_STATS=yes \
        matrixdotorg/synapse:latest generate
    print_success "Synapse configuration generated"
    
    # Update homeserver.yaml with Coturn configuration
    print_info "Configuring TURN server in homeserver.yaml..."
    
    if [ "$MATRIX_DOMAIN" = "localhost" ]; then
        TURN_URI="turn:$SERVER_IP"
    else
        TURN_URI="turn:$MATRIX_DOMAIN"
    fi
    
    cat >> synapse/homeserver.yaml << EOF

# TURN server configuration
turn_uris:
  - "$TURN_URI:3478?transport=udp"
  - "$TURN_URI:3478?transport=tcp"
  - "$TURN_URI:5349?transport=udp"
  - "$TURN_URI:5349?transport=tcp"
turn_shared_secret: "$COTURN_SECRET"
turn_user_lifetime: 1h
turn_allow_guests: true

EOF

    # Add registration settings based on user choice
    if [ "$ENABLE_REGISTRATION" = "yes" ] || [ "$ENABLE_REGISTRATION" = "y" ]; then
        cat >> synapse/homeserver.yaml << EOF
# Enable registration
enable_registration: true
enable_registration_without_verification: true

EOF
        print_warning "Open registration enabled - users can register without verification"
    else
        cat >> synapse/homeserver.yaml << EOF
# Disable open registration (recommended for security)
enable_registration: false

EOF
        print_success "Open registration disabled - only admins can create accounts"
    fi
    
    cat >> synapse/homeserver.yaml << EOF
# Enable user directory search
user_directory:
    enabled: true
    search_all_users: true

# MatrixRTC configuration for Element Call with LiveKit
experimental_features:
    # MSC3266: Room summary API. Used for knocking over federation
    msc3266_enabled: true
    # MSC4222 needed for syncv2 state_after. This allows clients to
    # correctly track the state of the room.
    msc4222_enabled: true

# The maximum allowed duration by which sent events can be delayed, as
# per MSC4140. Required for proper call participation signalling.
max_event_delay_duration: 24h

# Rate limiting for message events
# This needs to match at least e2ee key sharing frequency plus a bit of headroom
# Note: key sharing events are bursty
rc_message:
    per_second: 0.5
    burst_count: 30

# Rate limiting for delayed event management
# This needs to match at least the heart-beat frequency plus a bit of headroom
# Currently the heart-beat is every 5 seconds which translates into a rate of 0.2s
rc_delayed_event_mgmt:
    per_second: 1
    burst_count: 20
EOF
    print_success "TURN server and MatrixRTC configured in homeserver.yaml"
fi

# Create .env file with configuration
print_info "Creating .env file with configuration..."
cat > .env << EOF
# Synapse Configuration
SYNAPSE_SERVER_NAME=$MATRIX_DOMAIN
SYNAPSE_REPORT_STATS=yes

# System Configuration
TZ=$TIMEZONE

# User and Group IDs (optional, defaults to 991)
UID=991
GID=991

# TURN Server Configuration
TURN_SERVER=$MATRIX_DOMAIN
TURN_SHARED_SECRET=$COTURN_SECRET

# Element Web Configuration
MATRIX_THEMES=light,dark

# Element Call Configuration
ELEMENT_CALL_PORT=$ELEMENT_CALL_PORT

# LiveKit Configuration (for MatrixRTC backend)
LIVEKIT_KEY=$LIVEKIT_KEY
LIVEKIT_SECRET=$LIVEKIT_SECRET
LIVEKIT_DOMAIN=$LIVEKIT_DOMAIN
LIVEKIT_JWT_DOMAIN=$LIVEKIT_JWT_DOMAIN
WEBRTC_PORT_START=$WEBRTC_PORT_START
WEBRTC_PORT_END=$WEBRTC_PORT_END
EOF
print_success ".env file created with secure credentials"

# Step 6: Start services
print_info "Step 6/6: Starting Docker services..."
docker compose up -d
print_success "Docker services started"

# Wait for services to be ready
print_info "Waiting for services to initialize (30 seconds)..."
sleep 30

# Create admin user
print_info "Creating admin user..."
echo "Creating admin user: $ADMIN_USERNAME"
# Use stdin to pass password securely instead of command-line argument
echo "$ADMIN_PASSWORD" | docker compose exec -T synapse register_new_matrix_user \
    -c /data/homeserver.yaml \
    -u "$ADMIN_USERNAME" \
    --password-file /dev/stdin \
    -a \
    http://localhost:8008 2>/dev/null || \
    print_warning "Admin user creation failed. You can create it manually later with: docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              Installation Complete!                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
print_success "Your Samsesh Chat server is now running!"
echo ""
echo "Access your services at:"
echo "  • Element Web:     http://localhost:$ELEMENT_PORT"
if [ "$USE_ELEMENT_CALL" = "yes" ]; then
    echo "  • Element Call:    http://localhost:$ELEMENT_CALL_PORT (with LiveKit backend)"
    echo "  • LiveKit SFU:     ws://localhost:$LIVEKIT_SFU_PORT"
    echo "  • lk-jwt-service:  http://localhost:$LIVEKIT_JWT_PORT"
fi
echo "  • Synapse API:     http://localhost:$SYNAPSE_PORT"
echo "  • Admin Panel:     http://localhost:$ADMIN_PORT"
echo ""
echo "Admin Credentials:"
echo "  • Username: $ADMIN_USERNAME"
echo "  • Password: [hidden for security - you entered it during setup]"
echo ""
print_info "Sensitive configuration saved to .setup-config (secured with chmod 600)"
print_warning "Clear your terminal history to remove password traces: history -c"
echo ""

# Save configuration to file
cat > .setup-config << EOF
SERVER_IP=$SERVER_IP
MATRIX_DOMAIN=$MATRIX_DOMAIN
TIMEZONE=$TIMEZONE
VIDEO_CONF=$USE_ELEMENT_CALL
ELEMENT_PORT=$ELEMENT_PORT
EOF

if [ "$USE_ELEMENT_CALL" = "yes" ]; then
    cat >> .setup-config << EOF
ELEMENT_CALL_PORT=$ELEMENT_CALL_PORT
LIVEKIT_DOMAIN=$LIVEKIT_DOMAIN
LIVEKIT_JWT_DOMAIN=$LIVEKIT_JWT_DOMAIN
WEBRTC_PORT_START=$WEBRTC_PORT_START
WEBRTC_PORT_END=$WEBRTC_PORT_END
EOF
else
    cat >> .setup-config << EOF
JITSI_DOMAIN=$JITSI_DOMAIN
EOF
fi

cat >> .setup-config << EOF
SYNAPSE_PORT=$SYNAPSE_PORT
FEDERATION_PORT=$FEDERATION_PORT
ADMIN_PORT=$ADMIN_PORT
COTURN_SECRET=$COTURN_SECRET
LIVEKIT_KEY=$LIVEKIT_KEY
LIVEKIT_SECRET=$LIVEKIT_SECRET
ADMIN_USERNAME=$ADMIN_USERNAME
SETUP_DATE=$(date)
EOF

# Secure the configuration file
chmod 600 .setup-config

print_success "Configuration saved to .setup-config (permissions set to 600)"
echo ""
print_info "To view logs: docker compose logs -f"
print_info "To stop services: docker compose down"
print_info "To restart services: docker compose restart"
echo ""
