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

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

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

echo ""
print_info "=== Admin User Configuration ==="
echo ""

read -p "Enter admin username: " ADMIN_USERNAME
while [ -z "$ADMIN_USERNAME" ]; do
    print_error "Username cannot be empty."
    read -p "Enter admin username: " ADMIN_USERNAME
done

read -sp "Enter admin password: " ADMIN_PASSWORD
echo ""
while [ -z "$ADMIN_PASSWORD" ]; do
    print_error "Password cannot be empty."
    read -sp "Enter admin password: " ADMIN_PASSWORD
    echo ""
done

echo ""
print_info "=== Port Configuration ==="
echo ""

read -p "Element Web port [default: 8080]: " ELEMENT_PORT
ELEMENT_PORT=${ELEMENT_PORT:-8080}

read -p "Synapse port [default: 8008]: " SYNAPSE_PORT
SYNAPSE_PORT=${SYNAPSE_PORT:-8008}

read -p "Synapse federation port [default: 8448]: " FEDERATION_PORT
FEDERATION_PORT=${FEDERATION_PORT:-8448}

read -p "Synapse Admin port [default: 8081]: " ADMIN_PORT
ADMIN_PORT=${ADMIN_PORT:-8081}

echo ""
print_info "=== Configuration Summary ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Server IP:        $SERVER_IP"
echo "Matrix Domain:    $MATRIX_DOMAIN"
echo "Admin Username:   $ADMIN_USERNAME"
echo "Element Port:     $ELEMENT_PORT"
echo "Synapse Port:     $SYNAPSE_PORT"
echo "Federation Port:  $FEDERATION_PORT"
echo "Admin Panel Port: $ADMIN_PORT"
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
    "brand": "Samsesh Chat",
    "disable_custom_urls": false,
    "disable_guests": true,
    "disable_login_language_selector": false,
    "disable_3pid_login": false,
    "default_theme": "light",
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
    ],
    "jitsi": {
        "preferred_domain": "meet.element.io"
    }
}
EOF
print_success "Element configuration created"

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
  element:
    image: vectorim/element-web:latest
    restart: unless-stopped
    volumes:
      - ./element-config.json:/app/config.json
      - ./element-theme:/app/themes/samsesh
    ports:
      - "$ELEMENT_PORT:80"

  synapse:
    image: matrixdotorg/synapse:latest
    restart: unless-stopped
    volumes:
      - ./synapse:/data
    ports:
      - "$SYNAPSE_PORT:8008"
      - "$FEDERATION_PORT:8448"

  synapse-admin:
    image: awesometechnologies/synapse-admin
    restart: unless-stopped
    ports:
      - "$ADMIN_PORT:80"

  coturn:
    image: instrumentisto/coturn:latest
    restart: unless-stopped
    volumes:
      - ./coturn/turnserver.conf:/etc/coturn/turnserver.conf
    ports:
      - "49160-49200:49160-49200/udp"
      - "3478:3478"
      - "5349:5349"
    network_mode: host
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

# Enable registration
enable_registration: true
enable_registration_without_verification: true

# Enable user directory search
user_directory:
    enabled: true
    search_all_users: true
EOF
    print_success "TURN server configured in homeserver.yaml"
fi

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
    http://localhost:8008 2>/dev/null || {
    # Fallback to interactive method if password-file not supported
    docker compose exec -T synapse bash -c "register_new_matrix_user -c /data/homeserver.yaml -u $ADMIN_USERNAME -p $ADMIN_PASSWORD -a http://localhost:8008" 2>/dev/null || \
    print_warning "Admin user creation failed. You can create it manually later with: docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008"
}

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              Installation Complete!                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
print_success "Your Samsesh Chat server is now running!"
echo ""
echo "Access your services at:"
echo "  • Element Web:     http://localhost:$ELEMENT_PORT"
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
ELEMENT_PORT=$ELEMENT_PORT
SYNAPSE_PORT=$SYNAPSE_PORT
FEDERATION_PORT=$FEDERATION_PORT
ADMIN_PORT=$ADMIN_PORT
COTURN_SECRET=$COTURN_SECRET
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
