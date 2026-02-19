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
echo "  1) Element Call (Recommended - Self-hosted, fully integrated with LiveKit)"
echo "  2) Jitsi (External server)"
echo "  3) Jitsi (Self-hosted - will install Jitsi Meet)"
echo ""
read -p "Select option (1, 2, or 3) [default: 1]: " VIDEO_CONF_CHOICE
VIDEO_CONF_CHOICE=${VIDEO_CONF_CHOICE:-1}

while [[ ! "$VIDEO_CONF_CHOICE" =~ ^[123]$ ]]; do
    print_error "Invalid choice. Please enter 1, 2, or 3."
    read -p "Select option (1, 2, or 3) [default: 1]: " VIDEO_CONF_CHOICE
    VIDEO_CONF_CHOICE=${VIDEO_CONF_CHOICE:-1}
done

if [ "$VIDEO_CONF_CHOICE" = "2" ]; then
    read -p "Enter Jitsi domain [default: meet.element.io]: " JITSI_DOMAIN
    JITSI_DOMAIN=${JITSI_DOMAIN:-meet.element.io}
    USE_ELEMENT_CALL="no"
    USE_JITSI_SELF_HOSTED="no"
    print_info "Will use external Jitsi at: $JITSI_DOMAIN"
elif [ "$VIDEO_CONF_CHOICE" = "3" ]; then
    USE_ELEMENT_CALL="no"
    USE_JITSI_SELF_HOSTED="yes"
    
    echo ""
    print_info "=== Self-Hosted Jitsi Configuration ==="
    echo ""
    
    read -p "Enter Jitsi domain (e.g., meet.example.com) [default: meet.jitsi]: " JITSI_DOMAIN
    JITSI_DOMAIN=${JITSI_DOMAIN:-meet.jitsi}
    
    if [ "$JITSI_DOMAIN" != "meet.jitsi" ] && [ "$JITSI_DOMAIN" != "localhost" ]; then
        while ! validate_domain "$JITSI_DOMAIN"; do
            print_error "Invalid domain format."
            read -p "Enter Jitsi domain [default: meet.jitsi]: " JITSI_DOMAIN
            JITSI_DOMAIN=${JITSI_DOMAIN:-meet.jitsi}
            if [ "$JITSI_DOMAIN" = "meet.jitsi" ] || [ "$JITSI_DOMAIN" = "localhost" ]; then
                break
            fi
        done
    fi
    
    # Generate Jitsi passwords
    print_info "Generating secure Jitsi passwords..."
    JICOFO_COMPONENT_SECRET=$(generate_password)
    JICOFO_AUTH_PASSWORD=$(generate_password)
    JVB_AUTH_PASSWORD=$(generate_password)
    JIGASI_XMPP_PASSWORD=$(generate_password)
    JIBRI_RECORDER_PASSWORD=$(generate_password)
    JIBRI_XMPP_PASSWORD=$(generate_password)
    print_success "Jitsi credentials generated"
    
    print_success "Will use self-hosted Jitsi at: $JITSI_DOMAIN"
    print_info "Jitsi will use Coturn for TURN/STUN services"
else
    USE_ELEMENT_CALL="yes"
    USE_JITSI_SELF_HOSTED="no"
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
print_info "=== Push Notification Configuration ==="
echo ""
echo "Enable Sygnal push notification gateway for mobile apps?"
echo "Note: You'll need to configure push apps in sygnal.yaml after setup"
echo ""
read -p "Enable Sygnal push gateway? (yes/no) [default: no]: " ENABLE_SYGNAL
ENABLE_SYGNAL=${ENABLE_SYGNAL:-no}

if [ "$ENABLE_SYGNAL" = "yes" ] || [ "$ENABLE_SYGNAL" = "y" ]; then
    ENABLE_SYGNAL="yes"
    if [ "$MATRIX_DOMAIN" = "localhost" ]; then
        PUSH_GATEWAY_URL="http://$SERVER_IP:5000"
    else
        read -p "Enter push gateway URL [default: http://$SERVER_IP:5000]: " PUSH_GATEWAY_URL
        PUSH_GATEWAY_URL=${PUSH_GATEWAY_URL:-http://$SERVER_IP:5000}
    fi
    print_success "Sygnal push gateway will be enabled at: $PUSH_GATEWAY_URL"
else
    ENABLE_SYGNAL="no"
    PUSH_GATEWAY_URL=""
    print_info "Push gateway disabled"
fi

echo ""
print_info "=== Server Notices Configuration ==="
echo ""
echo "Enable server notices for system messages and announcements?"
echo ""
read -p "Enable server notices? (yes/no) [default: yes]: " ENABLE_SERVER_NOTICES
ENABLE_SERVER_NOTICES=${ENABLE_SERVER_NOTICES:-yes}

if [ "$ENABLE_SERVER_NOTICES" = "yes" ] || [ "$ENABLE_SERVER_NOTICES" = "y" ]; then
    ENABLE_SERVER_NOTICES="yes"
    read -p "Server notices username [default: server]: " SERVER_NOTICES_USER
    SERVER_NOTICES_USER=${SERVER_NOTICES_USER:-server}
    read -p "Server notices display name [default: Server]: " SERVER_NOTICES_DISPLAY_NAME
    SERVER_NOTICES_DISPLAY_NAME=${SERVER_NOTICES_DISPLAY_NAME:-Server}
    print_success "Server notices will be enabled with user: $SERVER_NOTICES_USER"
else
    ENABLE_SERVER_NOTICES="no"
    print_info "Server notices disabled"
fi

echo ""
print_info "=== LDAP Authentication Configuration ==="
echo ""
echo "Enable LDAP authentication to allow users to log in with LDAP/Active Directory credentials?"
echo ""
read -p "Enable LDAP authentication? (yes/no) [default: no]: " ENABLE_LDAP
ENABLE_LDAP=${ENABLE_LDAP:-no}

if [ "$ENABLE_LDAP" = "yes" ] || [ "$ENABLE_LDAP" = "y" ]; then
    ENABLE_LDAP="yes"
    echo ""
    echo "LDAP server options:"
    echo "  1) Self-hosted OpenLDAP (will install OpenLDAP container)"
    echo "  2) External LDAP server / Active Directory"
    echo ""
    read -p "Select option (1 or 2) [default: 1]: " LDAP_SERVER_CHOICE
    LDAP_SERVER_CHOICE=${LDAP_SERVER_CHOICE:-1}
    while [[ ! "$LDAP_SERVER_CHOICE" =~ ^[12]$ ]]; do
        print_error "Invalid choice. Please enter 1 or 2."
        read -p "Select option (1 or 2) [default: 1]: " LDAP_SERVER_CHOICE
        LDAP_SERVER_CHOICE=${LDAP_SERVER_CHOICE:-1}
    done

    if [ "$LDAP_SERVER_CHOICE" = "1" ]; then
        USE_SELF_HOSTED_LDAP="yes"
        LDAP_URI="ldap://openldap:1389"
        read -p "Enter LDAP base DN [default: dc=example,dc=com]: " LDAP_BASE
        LDAP_BASE=${LDAP_BASE:-dc=example,dc=com}
        read -p "Enter LDAP admin username [default: admin]: " LDAP_ADMIN_USERNAME
        LDAP_ADMIN_USERNAME=${LDAP_ADMIN_USERNAME:-admin}
        read -sp "Enter LDAP admin password: " LDAP_ADMIN_PASSWORD
        echo ""
        while [ -z "$LDAP_ADMIN_PASSWORD" ]; do
            print_error "LDAP admin password cannot be empty."
            read -sp "Enter LDAP admin password: " LDAP_ADMIN_PASSWORD
            echo ""
        done
        LDAP_BIND_DN="cn=${LDAP_ADMIN_USERNAME},${LDAP_BASE}"
        LDAP_BIND_PASSWORD="$LDAP_ADMIN_PASSWORD"
        LDAP_PORT=389
        print_success "Self-hosted OpenLDAP will be deployed at ldap://openldap:1389"
    else
        USE_SELF_HOSTED_LDAP="no"
        read -p "Enter LDAP server URI (e.g., ldap://ldap.example.com:389): " LDAP_URI
        while [ -z "$LDAP_URI" ]; do
            print_error "LDAP URI cannot be empty."
            read -p "Enter LDAP server URI: " LDAP_URI
        done
        read -p "Enter LDAP base DN (e.g., dc=example,dc=com): " LDAP_BASE
        while [ -z "$LDAP_BASE" ]; do
            print_error "LDAP base DN cannot be empty."
            read -p "Enter LDAP base DN: " LDAP_BASE
        done
        read -p "Enter LDAP bind DN (e.g., cn=admin,dc=example,dc=com): " LDAP_BIND_DN
        while [ -z "$LDAP_BIND_DN" ]; do
            print_error "LDAP bind DN cannot be empty."
            read -p "Enter LDAP bind DN: " LDAP_BIND_DN
        done
        read -sp "Enter LDAP bind password: " LDAP_BIND_PASSWORD
        echo ""
        while [ -z "$LDAP_BIND_PASSWORD" ]; do
            print_error "LDAP bind password cannot be empty."
            read -sp "Enter LDAP bind password: " LDAP_BIND_PASSWORD
            echo ""
        done
        LDAP_ADMIN_USERNAME=""
        LDAP_ADMIN_PASSWORD=""
        print_success "Will use external LDAP server at: $LDAP_URI"
    fi

    read -p "Enter LDAP user filter [default: (objectClass=inetOrgPerson)]: " LDAP_FILTER
    LDAP_FILTER=${LDAP_FILTER:-(objectClass=inetOrgPerson)}
    read -p "Enter LDAP UID attribute [default: uid]: " LDAP_UID_ATTR
    LDAP_UID_ATTR=${LDAP_UID_ATTR:-uid}
    read -p "Enter LDAP mail attribute [default: mail]: " LDAP_MAIL_ATTR
    LDAP_MAIL_ATTR=${LDAP_MAIL_ATTR:-mail}
    read -p "Enter LDAP display name attribute [default: givenName]: " LDAP_NAME_ATTR
    LDAP_NAME_ATTR=${LDAP_NAME_ATTR:-givenName}
    read -p "Enable STARTTLS for LDAP? (yes/no) [default: no]: " LDAP_START_TLS_CHOICE
    LDAP_START_TLS_CHOICE=${LDAP_START_TLS_CHOICE:-no}
    if [ "$LDAP_START_TLS_CHOICE" = "yes" ] || [ "$LDAP_START_TLS_CHOICE" = "y" ]; then
        LDAP_START_TLS="true"
    else
        LDAP_START_TLS="false"
    fi
    print_success "LDAP authentication configured"
else
    ENABLE_LDAP="no"
    USE_SELF_HOSTED_LDAP="no"
    print_info "LDAP authentication disabled"
fi

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
if [ "$ENABLE_LDAP" = "yes" ]; then
    echo "LDAP Auth:        enabled ($LDAP_URI)"
fi
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
relay-ip=$SERVER_IP
listening-ip=0.0.0.0
no-rfc5780
no-stun-backward-compatibility
total-quota=100
stale-nonce=600
bps-capacity=0
no-multicast-peers
mobility
keep-address-family
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
    # Create a temporary file with the updated keys section, port range, and Docker-optimized settings
    awk -v key="$LIVEKIT_KEY" -v secret="$LIVEKIT_SECRET" -v port_start="$WEBRTC_PORT_START" -v port_end="$WEBRTC_PORT_END" '
        /^keys:/ { print; getline; printf "  %s: %s\n", key, secret; next }
        /^[[:space:]]*port_range_start:/ { printf "  port_range_start: %s\n", port_start; next }
        /^[[:space:]]*port_range_end:/ { printf "  port_range_end: %s\n", port_end; next }
        /^[[:space:]]*use_external_ip:/ { printf "  use_external_ip: false\n"; next }
        /^[[:space:]]*use_ice_lite:/ { printf "  use_ice_lite: true\n"; next }
        { print }
    ' livekit.yaml > livekit.yaml.tmp && mv livekit.yaml.tmp livekit.yaml
    print_success "LiveKit configuration updated with ports $WEBRTC_PORT_START-$WEBRTC_PORT_END and Docker-optimized settings"
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
    build:
      context: .
      dockerfile: Dockerfile.synapse
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
EOF
# When self-hosted LDAP is used, synapse must wait for openldap to be ready
# so that LDAP users can authenticate on first login (member provisioning)
if [ "$USE_SELF_HOSTED_LDAP" = "yes" ]; then
    cat >> docker-compose.yaml << EOF
      openldap:
        condition: service_healthy
EOF
fi
cat >> docker-compose.yaml << EOF
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

# Add OpenLDAP service if self-hosted LDAP is selected
if [ "$USE_SELF_HOSTED_LDAP" = "yes" ]; then
    cat >> docker-compose.yaml << EOF

  openldap:
    image: bitnami/openldap:latest
    restart: unless-stopped
    environment:
      - LDAP_ADMIN_USERNAME=\${LDAP_ADMIN_USERNAME:-admin}
      - LDAP_ADMIN_PASSWORD=\${LDAP_ADMIN_PASSWORD:-adminpassword}
      - LDAP_ROOT=\${LDAP_BASE:-dc=example,dc=com}
      - LDAP_LOGLEVEL=\${LDAP_LOGLEVEL:-0}
    volumes:
      - openldap_data:/bitnami/openldap
    ports:
      - "\${LDAP_PORT:-389}:1389"
    healthcheck:
      test: ["CMD-SHELL", "nc -z localhost 1389 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    networks:
      - matrix-network
EOF
    print_success "OpenLDAP service configured"
fi


# Add Element Call and LiveKit services if selected
if [ "$USE_ELEMENT_CALL" = "yes" ]; then
    cat >> docker-compose.yaml << EOF

  lk-jwt-service:
    image: ghcr.io/element-hq/lk-jwt-service:latest
    restart: unless-stopped
    ports:
      - "$LIVEKIT_JWT_PORT:8080"
    environment:
      # For Docker-internal communication (default for local deployments)
      - LIVEKIT_URL=ws://livekit:7880
      # For production with SSL/TLS and reverse proxy, change to:
      # - LIVEKIT_URL=wss://matrixrtc.yourdomain.com
      - LIVEKIT_KEY=\${LIVEKIT_KEY:-devkey}
      - LIVEKIT_SECRET=\${LIVEKIT_SECRET:-secret}
      # Restrict call creation to users from specific homeservers (comma-separated)
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
      livekit:
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
    networks:
      - matrix-network
EOF
fi

# Add Jitsi Meet services if selected
if [ "$USE_JITSI_SELF_HOSTED" = "yes" ]; then
    cat >> docker-compose.yaml << EOF

  jitsi-web:
    image: jitsi/web:stable
    restart: unless-stopped
    ports:
      - "\${JITSI_HTTP_PORT:-8443}:80"
      - "\${JITSI_HTTPS_PORT:-8444}:443"
    volumes:
      - ./jitsi/web:/config:Z
      - ./jitsi/web/letsencrypt:/etc/letsencrypt:Z
      - ./jitsi/transcripts:/usr/share/jitsi-meet/transcripts:Z
    environment:
      - ENABLE_AUTH=\${JITSI_ENABLE_AUTH:-0}
      - ENABLE_GUESTS=\${JITSI_ENABLE_GUESTS:-1}
      - ENABLE_LETSENCRYPT=\${JITSI_ENABLE_LETSENCRYPT:-0}
      - ENABLE_HTTP_REDIRECT=\${JITSI_ENABLE_HTTP_REDIRECT:-1}
      - ENABLE_TRANSCRIPTIONS=\${JITSI_ENABLE_TRANSCRIPTIONS:-0}
      - DISABLE_HTTPS=\${JITSI_DISABLE_HTTPS:-1}
      - JICOFO_COMPONENT_SECRET=\${JICOFO_COMPONENT_SECRET}
      - JICOFO_AUTH_USER=focus
      - JICOFO_AUTH_PASSWORD=\${JICOFO_AUTH_PASSWORD}
      - JVB_AUTH_USER=jvb
      - JVB_AUTH_PASSWORD=\${JVB_AUTH_PASSWORD}
      - JIGASI_XMPP_USER=jigasi
      - JIGASI_XMPP_PASSWORD=\${JIGASI_XMPP_PASSWORD}
      - JIBRI_RECORDER_USER=recorder
      - JIBRI_RECORDER_PASSWORD=\${JIBRI_RECORDER_PASSWORD}
      - JIBRI_XMPP_USER=jibri
      - JIBRI_XMPP_PASSWORD=\${JIBRI_XMPP_PASSWORD}
      - ENABLE_RECORDING=\${JITSI_ENABLE_RECORDING:-0}
      - TZ=\${TZ:-UTC}
      - PUBLIC_URL=\${JITSI_PUBLIC_URL:-https://meet.jitsi}
      - XMPP_DOMAIN=meet.jitsi
      - XMPP_AUTH_DOMAIN=auth.meet.jitsi
      - XMPP_BOSH_URL_BASE=http://jitsi-prosody:5280
      - XMPP_MUC_DOMAIN=muc.meet.jitsi
      - XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi
      - XMPP_GUEST_DOMAIN=guest.meet.jitsi
      - XMPP_RECORDER_DOMAIN=recorder.meet.jitsi
    depends_on:
      - jitsi-prosody
      - jitsi-jicofo
      - jitsi-jvb
    networks:
      - matrix-network

  jitsi-prosody:
    image: jitsi/prosody:stable
    restart: unless-stopped
    expose:
      - '5222'
      - '5347'
      - '5280'
    volumes:
      - ./jitsi/prosody/config:/config:Z
      - ./jitsi/prosody/prosody-plugins-custom:/prosody-plugins-custom:Z
    environment:
      - AUTH_TYPE=\${JITSI_AUTH_TYPE:-internal}
      - ENABLE_AUTH=\${JITSI_ENABLE_AUTH:-0}
      - ENABLE_GUESTS=\${JITSI_ENABLE_GUESTS:-1}
      - XMPP_DOMAIN=meet.jitsi
      - XMPP_AUTH_DOMAIN=auth.meet.jitsi
      - XMPP_GUEST_DOMAIN=guest.meet.jitsi
      - XMPP_MUC_DOMAIN=muc.meet.jitsi
      - XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi
      - XMPP_RECORDER_DOMAIN=recorder.meet.jitsi
      - JICOFO_COMPONENT_SECRET=\${JICOFO_COMPONENT_SECRET}
      - JICOFO_AUTH_USER=focus
      - JICOFO_AUTH_PASSWORD=\${JICOFO_AUTH_PASSWORD}
      - JVB_AUTH_USER=jvb
      - JVB_AUTH_PASSWORD=\${JVB_AUTH_PASSWORD}
      - JIGASI_XMPP_USER=jigasi
      - JIGASI_XMPP_PASSWORD=\${JIGASI_XMPP_PASSWORD}
      - JIBRI_XMPP_USER=jibri
      - JIBRI_XMPP_PASSWORD=\${JIBRI_XMPP_PASSWORD}
      - JIBRI_RECORDER_USER=recorder
      - JIBRI_RECORDER_PASSWORD=\${JIBRI_RECORDER_PASSWORD}
      - LOG_LEVEL=info
      - TZ=\${TZ:-UTC}
    networks:
      - matrix-network

  jitsi-jicofo:
    image: jitsi/jicofo:stable
    restart: unless-stopped
    volumes:
      - ./jitsi/jicofo:/config:Z
    environment:
      - AUTH_TYPE=\${JITSI_AUTH_TYPE:-internal}
      - ENABLE_AUTH=\${JITSI_ENABLE_AUTH:-0}
      - XMPP_DOMAIN=meet.jitsi
      - XMPP_AUTH_DOMAIN=auth.meet.jitsi
      - XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi
      - XMPP_SERVER=jitsi-prosody
      - JICOFO_COMPONENT_SECRET=\${JICOFO_COMPONENT_SECRET}
      - JICOFO_AUTH_USER=focus
      - JICOFO_AUTH_PASSWORD=\${JICOFO_AUTH_PASSWORD}
      - JVB_BREWERY_MUC=jvbbrewery
      - JIGASI_BREWERY_MUC=jigasibrewery
      - JIBRI_BREWERY_MUC=jibribrewery
      - JIBRI_PENDING_TIMEOUT=90
      - TZ=\${TZ:-UTC}
    depends_on:
      - jitsi-prosody
    networks:
      - matrix-network

  jitsi-jvb:
    image: jitsi/jvb:stable
    restart: unless-stopped
    ports:
      - "\${JVB_PORT:-10000}:10000/udp"
      - "\${JVB_TCP_PORT:-4443}:4443"
    volumes:
      - ./jitsi/jvb:/config:Z
    environment:
      - DOCKER_HOST_ADDRESS=\${JITSI_DOCKER_HOST_ADDRESS}
      - XMPP_AUTH_DOMAIN=auth.meet.jitsi
      - XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi
      - XMPP_SERVER=jitsi-prosody
      - JVB_AUTH_USER=jvb
      - JVB_AUTH_PASSWORD=\${JVB_AUTH_PASSWORD}
      - JVB_BREWERY_MUC=jvbbrewery
      - JVB_PORT=\${JVB_PORT:-10000}
      - JVB_TCP_HARVESTER_DISABLED=true
      - JVB_TCP_PORT=\${JVB_TCP_PORT:-4443}
      - JVB_STUN_SERVERS=stun.l.google.com:19302,stun1.l.google.com:19302,stun2.l.google.com:19302
      - JVB_ENABLE_APIS=rest,colibri
      - TZ=\${TZ:-UTC}
    depends_on:
      - jitsi-prosody
    networks:
      - matrix-network
EOF
    print_success "Jitsi Meet services configured"
fi

# Add Sygnal push gateway if enabled
if [ "$ENABLE_SYGNAL" = "yes" ]; then
    cat >> docker-compose.yaml << EOF

  sygnal:
    image: matrixdotorg/sygnal:latest
    container_name: sygnal
    restart: unless-stopped
    ports:
      - "\${SYGNAL_PORT:-127.0.0.1:5000}:5000"
    volumes:
      - ./sygnal.yaml:/etc/sygnal/sygnal.yaml:ro
      - ./sygnal.yaml:/sygnal.yaml:ro
    command:
      - python
      - -m
      - sygnal.sygnal
      - -c
      - /etc/sygnal/sygnal.yaml
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    networks:
      - matrix-network
EOF
    print_success "Sygnal push gateway configured"
fi

cat >> docker-compose.yaml << EOF

networks:
  matrix-network:
    name: matrix-network
    driver: bridge
EOF

# Add named volumes if OpenLDAP is enabled
if [ "$USE_SELF_HOSTED_LDAP" = "yes" ]; then
    cat >> docker-compose.yaml << EOF

volumes:
  openldap_data:
EOF
fi
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

    # Add server notices configuration if enabled
    if [ "$ENABLE_SERVER_NOTICES" = "yes" ]; then
        cat >> synapse/homeserver.yaml << EOF
# Server Notices configuration
server_notices:
    system_mxid_localpart: $SERVER_NOTICES_USER
    system_mxid_display_name: "$SERVER_NOTICES_DISPLAY_NAME"
    room_name: "Server Notices"
    auto_join: true

EOF
        print_success "Server notices configured"
    fi
    
    # Add push gateway configuration if enabled
    if [ "$ENABLE_SYGNAL" = "yes" ]; then
        cat >> synapse/homeserver.yaml << EOF
# Push notification gateway configuration
push:
    enabled: true
    # URL of your push gateway (Sygnal)
    include_content: true
    group_unread_count_by_room: true
    
# Custom push gateway
# Note: Configure this after setup if using external gateway
# push_gateway_url: "$PUSH_GATEWAY_URL"

EOF
        print_success "Push gateway configuration added"
    fi

    # Add LDAP auth provider configuration if enabled
    if [ "$ENABLE_LDAP" = "yes" ]; then
        cat >> synapse/homeserver.yaml << EOF
# LDAP authentication provider (matrix-synapse-ldap3)
# LDAP users are provisioned as regular members, identical to locally registered users.
modules:
  - module: ldap_auth_provider.LdapAuthProviderModule
    config:
      enabled: true
      mode: simple_bind
      uri: "$LDAP_URI"
      start_tls: $LDAP_START_TLS
      base: "$LDAP_BASE"
      attributes:
        uid: "$LDAP_UID_ATTR"
        mail: "$LDAP_MAIL_ATTR"
        name: "$LDAP_NAME_ATTR"
      bind_dn: "$LDAP_BIND_DN"
      bind_password: "$LDAP_BIND_PASSWORD"
      filter: "$LDAP_FILTER"
      # Allow LDAP users to log in even if their Matrix account already exists,
      # making them full members just like any other chat user.
      allow_existing_users: true
      # Assign new LDAP users to this homeserver's domain so their Matrix IDs
      # match the pattern @username:$MATRIX_DOMAIN, same as all other members.
      default_domain: "$MATRIX_DOMAIN"

EOF
        print_success "LDAP authentication configured in homeserver.yaml"
    fi
    
    print_success "TURN server and MatrixRTC configured in homeserver.yaml"
    
    # Update listeners to include federation port
    print_info "Updating listener configuration for federation..."
    
    # Create a backup of homeserver.yaml
    cp synapse/homeserver.yaml synapse/homeserver.yaml.backup
    
    # Use sed to update the listeners section
    # Find and replace the listeners section to add the federation listener
    awk '
    /^listeners:/ {
        print "listeners:"
        print "  # Client API listener"
        print "  - port: 8008"
        print "    tls: false"
        print "    type: http"
        print "    x_forwarded: true"
        print "    bind_addresses: [\"0.0.0.0\"]"
        print "    resources:"
        print "      - names: [client, federation]"
        print "        compress: false"
        print ""
        print "  # Federation API listener"
        print "  - port: 8448"
        print "    type: http"
        print "    tls: false"
        print "    x_forwarded: true"
        print "    bind_addresses: [\"0.0.0.0\"]"
        print "    resources:"
        print "      - names: [federation]"
        
        # Skip the original listeners section
        in_listeners = 1
        next
    }
    in_listeners && /^[^ ]/ {
        in_listeners = 0
    }
    !in_listeners {
        print
    }
    ' synapse/homeserver.yaml.backup > synapse/homeserver.yaml
    
    print_success "Federation listener configured on port 8448"
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

EOF

if [ "$USE_ELEMENT_CALL" = "yes" ]; then
    cat >> .env << EOF
# LiveKit Configuration (for MatrixRTC backend)
LIVEKIT_KEY=$LIVEKIT_KEY
LIVEKIT_SECRET=$LIVEKIT_SECRET
LIVEKIT_DOMAIN=$LIVEKIT_DOMAIN
LIVEKIT_JWT_DOMAIN=$LIVEKIT_JWT_DOMAIN
WEBRTC_PORT_START=$WEBRTC_PORT_START
WEBRTC_PORT_END=$WEBRTC_PORT_END

EOF
fi

if [ "$USE_JITSI_SELF_HOSTED" = "yes" ]; then
    cat >> .env << EOF
# Jitsi Meet Configuration
JITSI_HTTP_PORT=8443
JITSI_HTTPS_PORT=8444
JITSI_ENABLE_AUTH=0
JITSI_ENABLE_GUESTS=1
JITSI_ENABLE_LETSENCRYPT=0
JITSI_ENABLE_HTTP_REDIRECT=1
JITSI_ENABLE_TRANSCRIPTIONS=0
JITSI_DISABLE_HTTPS=1
JITSI_ENABLE_RECORDING=0
JITSI_AUTH_TYPE=internal
JITSI_PUBLIC_URL=https://$JITSI_DOMAIN
JITSI_DOCKER_HOST_ADDRESS=$SERVER_IP
JICOFO_COMPONENT_SECRET=$JICOFO_COMPONENT_SECRET
JICOFO_AUTH_PASSWORD=$JICOFO_AUTH_PASSWORD
JVB_AUTH_PASSWORD=$JVB_AUTH_PASSWORD
JIGASI_XMPP_PASSWORD=$JIGASI_XMPP_PASSWORD
JIBRI_RECORDER_PASSWORD=$JIBRI_RECORDER_PASSWORD
JIBRI_XMPP_PASSWORD=$JIBRI_XMPP_PASSWORD
JVB_PORT=10000
JVB_TCP_PORT=4443

EOF
fi

if [ "$ENABLE_SYGNAL" = "yes" ]; then
    cat >> .env << EOF
# Sygnal Push Notification Gateway
SYGNAL_PORT=127.0.0.1:5000
PUSH_GATEWAY_URL=$PUSH_GATEWAY_URL
PUSH_GATEWAY_ENABLED=true

EOF
fi

if [ "$ENABLE_LDAP" = "yes" ]; then
    cat >> .env << EOF
# LDAP Authentication
LDAP_ENABLED=true
LDAP_URI=$LDAP_URI
LDAP_BASE=$LDAP_BASE
LDAP_BIND_DN=$LDAP_BIND_DN
LDAP_BIND_PASSWORD=$LDAP_BIND_PASSWORD
LDAP_FILTER=$LDAP_FILTER
LDAP_UID_ATTR=$LDAP_UID_ATTR
LDAP_MAIL_ATTR=$LDAP_MAIL_ATTR
LDAP_NAME_ATTR=$LDAP_NAME_ATTR
LDAP_START_TLS=$LDAP_START_TLS
EOF
    if [ "$USE_SELF_HOSTED_LDAP" = "yes" ]; then
        cat >> .env << EOF
LDAP_ADMIN_USERNAME=$LDAP_ADMIN_USERNAME
LDAP_ADMIN_PASSWORD=$LDAP_ADMIN_PASSWORD
LDAP_PORT=$LDAP_PORT
LDAP_LOGLEVEL=0
EOF
    fi
    cat >> .env << EOF

EOF
fi

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
elif [ "$USE_JITSI_SELF_HOSTED" = "yes" ]; then
    echo "  • Jitsi Meet:      http://localhost:8443"
    echo "  • Jitsi (HTTPS):   https://localhost:8444 (if configured)"
fi
echo "  • Synapse API:     http://localhost:$SYNAPSE_PORT"
echo "  • Synapse Federation: http://localhost:$FEDERATION_PORT"
echo "  • Admin Panel:     http://localhost:$ADMIN_PORT"
if [ "$ENABLE_SYGNAL" = "yes" ]; then
    echo "  • Sygnal Push:     http://localhost:5000"
fi
if [ "$ENABLE_LDAP" = "yes" ] && [ "$USE_SELF_HOSTED_LDAP" = "yes" ]; then
    echo "  • OpenLDAP:        ldap://localhost:$LDAP_PORT"
fi
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
elif [ "$USE_JITSI_SELF_HOSTED" = "yes" ]; then
    cat >> .setup-config << EOF
JITSI_DOMAIN=$JITSI_DOMAIN
JITSI_SELF_HOSTED=yes
EOF
else
    cat >> .setup-config << EOF
JITSI_DOMAIN=$JITSI_DOMAIN
JITSI_EXTERNAL=yes
EOF
fi

if [ "$ENABLE_SYGNAL" = "yes" ]; then
    cat >> .setup-config << EOF
SYGNAL_ENABLED=yes
PUSH_GATEWAY_URL=$PUSH_GATEWAY_URL
EOF
fi

if [ "$ENABLE_SERVER_NOTICES" = "yes" ]; then
    cat >> .setup-config << EOF
SERVER_NOTICES_ENABLED=yes
SERVER_NOTICES_USER=$SERVER_NOTICES_USER
EOF
fi

if [ "$ENABLE_LDAP" = "yes" ]; then
    cat >> .setup-config << EOF
LDAP_ENABLED=yes
LDAP_URI=$LDAP_URI
LDAP_BASE=$LDAP_BASE
LDAP_SELF_HOSTED=$USE_SELF_HOSTED_LDAP
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
