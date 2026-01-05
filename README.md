# Samsesh Chat - Self-Hosted Matrix Server

A complete self-hosted chat platform powered by Matrix Synapse, Element Web, and Coturn for voice/video calls. This setup provides an easy-to-deploy, privacy-focused communication solution.

## Features

- 🚀 **One-Command Setup**: Automated installation with interactive script
- 💬 **Modern UI**: Element Web client with custom Samsesh branding
- 🎥 **Voice & Video**: Built-in Coturn TURN server for reliable calls
- 📞 **Element Call**: Standalone video conferencing with LiveKit backend
- 🎬 **LiveKit Integration**: Professional-grade SFU for scalable video calls
- 🛠️ **Admin Panel**: Web-based administration interface
- 🔒 **Privacy First**: Self-hosted with no data collection
- 📦 **Containerized**: Easy deployment with Docker Compose

## Official Documentation

1. <https://matrix.org/docs/projects/server/synapse>
2. <https://element.io/solutions/on-premise-collaboration>

## Requirements

1. A Linux server (Ubuntu 20.04+ recommended)
2. Docker and Docker Compose installed
3. Public IP address (for external access)
4. Open ports: 8080 (Element), 8008 (Synapse), 8448 (Federation), 8081 (Admin), 8082 (Element Call), 8083 (lk-jwt-service), 3478/5349 (TURN), 7880-7882 (LiveKit)

## Quick Start

### Automated Installation (Recommended)

Run the interactive setup script:

```bash
git clone https://github.com/samsesh/matrix-on-premise.git
cd matrix-on-premise
chmod +x setup.sh
./setup.sh
```

The script will guide you through:
- Server configuration (IP, domain)
- System configuration (timezone)
- Video conferencing choice (Element Call or Jitsi)
- Admin user creation
- Port configuration
- Automatic service deployment

### Environment Variables

The docker-compose setup supports environment variables for easy configuration. Create a `.env` file in the project root or set these variables in your environment:

```bash
# Copy the example file
cp .env.example .env

# Edit with your values
nano .env
```

Available environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SYNAPSE_SERVER_NAME` | `localhost` | Your Matrix server name/domain |
| `SYNAPSE_REPORT_STATS` | `yes` | Whether to report usage statistics to matrix.org |
| `TZ` | `UTC` | Timezone for the containers |
| `UID` | `991` | User ID for running Synapse (optional) |
| `GID` | `991` | Group ID for running Synapse (optional) |
| `TURN_SERVER` | `localhost` | TURN server hostname/IP for voice/video calls |
| `TURN_SHARED_SECRET` | *(empty)* | TURN server shared secret for authentication |
| `MATRIX_THEMES` | `light,dark` | Available themes for Element web client |
| `ELEMENT_CALL_PORT` | `8082` | Port for Element Call video conferencing service |
| `LIVEKIT_KEY` | `devkey` | LiveKit API key for MatrixRTC (change in production!) |
| `LIVEKIT_SECRET` | `secret` | LiveKit API secret for MatrixRTC (change in production!) |

**Note:** The docker-compose file now includes:
- **Service dependencies**: Services start in the correct order (coturn → synapse → element/element-call/synapse-admin)
- **Network isolation**: All services communicate through a dedicated `matrix-network`
- **Environment-based configuration**: Easy customization without editing docker-compose.yaml

### Manual Installation

If you prefer manual setup, follow these steps:

1. Clone this repo or copy its contents to a directory and drive it into

    ```bash
    mkdir $HOME/matrix
    cd $HOME/matrix
    ```

1. Create Element config and Copy and paste [example contents](https://develop.element.io/config.json) into your file.

    ```bash
    nano element-config.json
    or
    curl https://develop.element.io/config.json --output element-config.json
    ```

1. Remove `"default_server_name": "matrix.org"` from `element-config.json` as this is deprecated

    ```bash
    sed -i '/"default_server_name": "matrix.org"/d' element-config.json
    ```

1. Add our custom homeserver to the top of ‍‍‍`element-config.json` (Use localhost or your server's IP/domain)

    ```bash
    "default_server_config": {
        "m.homeserver": {
            "base_url": "http://localhost:8008",
            "server_name": "localhost"
        },
        "m.identity_server": {
            "base_url": "https://vector.im"
        }
    },
    ```

1. Generate Synapse config (homeserver.yaml) with this command (Use localhost or your server's domain)

    ```bash
    sudo docker run -it --rm \
        -v "$HOME/matrix/synapse:/data" \
        -e SYNAPSE_SERVER_NAME=localhost \
        -e SYNAPSE_REPORT_STATS=yes \
        matrixdotorg/synapse:latest generate
    ```

1. As it's common that your client are behind NATed network traffic you may need to add TURN service to your setup for reliable VoIP connections.  
Note: This is required only for mobile devices (iOS and Android), The Element Web UI is using WebRTC which enables port punching through NAT network without TURN.  
Update the `coturn/turnserver.conf` file:
    1. Update the password `SOMESECURETEXT`
    1. Add the Server Public IP at the last line
    1. Replace with your domain if you have one (otherwise use localhost)

1. Add Coturn configs to the `homeserver.yml` (Replace with your domain or use localhost)
    Replace the configs from the previous step

    ```bash
    turn_uris:
    - "turn:localhost:3478?transport=udp"
    - "turn:localhost:3478?transport=tcp"
    - "turns:localhost:5349?transport=udp"
    - "turns:localhost:5349?transport=tcp"
    turn_shared_secret: "SOMESECURETEXT"
    turn_user_lifetime: 1h
    turn_allow_guests: true
    ```

1. Configure environment variables (optional but recommended)

    ```bash
    # Copy the example environment file
    cp .env.example .env
    
    # Edit with your server settings
    nano .env
    ```

1. deploy the docker compose

    ```bash
    sudo docker-compose up -d
    ```
    
    The services will start in the correct order:
    - First: coturn (TURN server)
    - Then: synapse (Matrix homeserver)
    - Finally: element (web client), element-call (video conferencing), and synapse-admin (admin panel)

1. Create an Admin User
    1. Access docker shell  
    `sudo docker compose exec -it synapse bash`
    1. run command  
    `register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008`
    1. Follow the on screen prompts
    1. Enter exit to leave the container's shell with  
    `exit`

1. If you need to allow users to register without any verification and the following line to `homeserver.yml` and restart the synapse container

    ```bash
    enable_registration: true
    enable_registration_without_verification: true
    ```

1. Check your configuration:
    1. Element UI: <http://localhost:8080>
    1. Matrix Core Endpoint: <http://localhost:8008/_matrix>
    1. Admin WebUI: <http://localhost:8081>
    1. Element Call: <http://localhost:8082>

## Accessing Your Server

After installation, access your services at:

- **Element Web (Chat Interface)**: `http://localhost:8080` or `http://your-server-ip:8080`
- **Element Call (Video Conferencing)**: `http://localhost:8082` or `http://your-server-ip:8082`
- **Synapse API**: `http://localhost:8008`
- **Synapse Admin Panel**: `http://localhost:8081`
- **lk-jwt-service (MatrixRTC Auth)**: `http://localhost:8083`
- **LiveKit SFU**: `ws://localhost:7880` (WebSocket connection for media)

### Mobile Apps

Download the Element mobile app to connect from anywhere:

1. iOS: <https://apps.apple.com/us/app/element-messenger/id1083446067>  
2. Android: <https://play.google.com/store/apps/details?id=im.vector.app&hl=en&gl=US>  
3. Android (Cafe Bazar): <https://cafebazaar.ir/app/im.vector.app>

When connecting from mobile:
1. Open the Element app
2. Tap "Sign in"
3. Tap "Edit" next to the homeserver
4. Enter your server URL: `http://your-server-ip:8008`
5. Enter your username and password

## LiveKit and MatrixRTC Setup

This setup includes **LiveKit** and the **MatrixRTC Authorization Service** for enhanced video calling capabilities with Element Call. LiveKit provides a scalable SFU (Selective Forwarding Unit) backend that improves call quality and performance.

### What's Included

The docker-compose configuration includes three additional services for MatrixRTC:

1. **LiveKit SFU** (Port 7880): The media routing server for real-time video/audio
2. **lk-jwt-service** (Port 8083): Authorization service that bridges Matrix authentication with LiveKit
3. **Element Call**: Configured to use the LiveKit backend

### Required Synapse Configuration

After running the setup, you need to add MatrixRTC configuration to your Synapse homeserver. Edit `synapse/homeserver.yaml` and add the following:

```yaml
# Enable experimental MSCs required for Element Call
experimental_features:
  msc3266_enabled: true  # Room summary API for federation
  msc4222_enabled: true  # Sync v2 state_after

# Maximum delay for events (required for call signalling)
max_event_delay_duration: 24h

# Rate limiting for messages (adjust for e2ee key sharing)
rc_message:
  per_second: 0.5
  burst_count: 30

# Rate limiting for delayed events (adjust for heartbeats)
rc_delayed_event_mgmt:
  per_second: 1
  burst_count: 20
```

A complete configuration template is available in `synapse-livekit-config.yaml`.

After adding this configuration, restart Synapse:
```bash
docker compose restart synapse
```

### Production Deployment with Reverse Proxy

For production use, it's recommended to set up a reverse proxy (nginx or Caddy) to route LiveKit traffic. Example configurations are provided:

- `nginx-livekit-example.conf` - Nginx reverse proxy configuration
- `caddy-livekit-example.conf` - Caddy reverse proxy configuration

The reverse proxy should route:
- `/livekit/jwt/` → lk-jwt-service (port 8083)
- `/livekit/sfu/` → LiveKit SFU (port 7880)

### Ports Used by LiveKit

- **7880**: LiveKit WebSocket API
- **7881**: LiveKit TCP fallback for WebRTC
- **7882/udp**: LiveKit UDP port for WebRTC media
- **8083**: lk-jwt-service HTTP API

Make sure these ports are accessible from your clients, or configure a reverse proxy.

### Security Considerations

**Important:** Change the default LiveKit credentials in production!

1. Generate secure random values:
   ```bash
   openssl rand -hex 32  # For LIVEKIT_SECRET
   ```

2. Update your `.env` file:
   ```bash
   LIVEKIT_KEY=your-secure-key
   LIVEKIT_SECRET=your-secure-secret
   ```

3. Update the `livekit.yaml` file with the same credentials:
   ```yaml
   keys:
     your-secure-key: your-secure-secret
   ```

4. Restart the services:
   ```bash
   docker compose down
   docker compose up -d
   ```

### Verifying LiveKit Setup

After starting the services, verify LiveKit is working:

1. Check service health:
   ```bash
   docker compose ps
   ```
   All services should show "Up" status.

2. Check LiveKit logs:
   ```bash
   docker compose logs livekit
   docker compose logs lk-jwt-service
   ```

3. Test the JWT service endpoint:
   ```bash
   curl http://localhost:8083/healthz
   ```
   Should return a 200 OK response.

### Troubleshooting LiveKit

- **Services won't start**: Check logs with `docker compose logs livekit lk-jwt-service`
- **Calls don't connect**: Ensure ports 7880-7882 are accessible and LIVEKIT_KEY/SECRET match in all services
- **Element Call not using LiveKit**: Verify `element-call-config.json` has the correct `livekit_service_url`

## Managing Your Server

### View Logs
```bash
docker compose logs -f
docker compose logs -f synapse  # View only Synapse logs
```

### Restart Services
```bash
docker compose restart
```

### Stop Services
```bash
docker compose down
```

### Backup Your Data
```bash
# Backup Synapse data
tar -czf synapse-backup-$(date +%Y%m%d).tar.gz synapse/

# Backup Coturn config
cp coturn/turnserver.conf coturn-backup.conf
```

## Customization

### Custom Branding

The setup includes **SamSesh Chat** branding with dark mode enabled by default. The Element Web interface includes:
- Custom brand name: "SamSesh Chat"
- Footer links to SamSesh website, blog, and donation page
- Dark theme as default (users can switch to light mode)
- Custom logo and theming

To customize branding:
1. Edit `element-config.json` and change the `brand` field, `footer_links`, and `default_theme`
2. Replace logo in `element-theme/logo.png` with your own
3. Restart Element: `docker compose restart element`

### Video Conferencing Options

During setup, you can choose between two video conferencing solutions:

1. **Element Call** (Recommended)
   - Self-hosted and fully integrated
   - No third-party dependencies
   - Better privacy and control
   - Accessible at port 8082

2. **Jitsi**
   - Uses meet.element.io by default (or your own Jitsi server)
   - External service
   - Can specify custom Jitsi domain

### Enable Additional Features

Edit `synapse/homeserver.yaml` to enable features like:
- Email notifications
- SMS verification
- LDAP authentication
- PostgreSQL database (recommended for production)

See the [official Synapse documentation](https://matrix-org.github.io/synapse/latest/usage/configuration/config_documentation.html) for all options.

## Troubleshooting

### Services won't start
```bash
# Check service status
docker compose ps

# Check logs for errors
docker compose logs
```

### Can't connect to server
- Ensure firewall allows traffic on required ports
- Check if services are running: `docker compose ps`
- Verify your IP address is correct in setup

### Federation not working
- Ensure port 8448 is open and accessible from the internet
- Check your DNS records point to the correct IP
- Verify SSL certificates if using HTTPS

## Security Recommendations

1. **Use HTTPS**: Set up a reverse proxy (nginx/Caddy) with SSL certificates
2. **Firewall**: Only expose necessary ports
3. **Regular Updates**: Keep Docker images updated with `docker compose pull && docker compose up -d`
4. **Backups**: Regularly backup your data
5. **Strong Passwords**: Use complex passwords for admin accounts
6. **Disable Open Registration**: After creating accounts, disable open registration
7. **Secure Configuration Files**: The setup script automatically secures sensitive files with chmod 600
   - `.setup-config` - Contains Coturn secret and admin username
   - `coturn/turnserver.conf` - Contains Coturn authentication secrets
   - Keep these files secure and never commit them to version control
8. **Clear Terminal History**: After setup, clear your shell history: `history -c`

## Production Deployment

For production use, consider:

1. **PostgreSQL Database**: Replace SQLite with PostgreSQL
2. **Reverse Proxy**: Use nginx or Caddy for SSL termination
3. **Monitoring**: Set up monitoring (Prometheus/Grafana)
4. **Rate Limiting**: Configure rate limits in Synapse
5. **Email Server**: Configure SMTP for notifications
6. **Regular Backups**: Automated backup solution

## Notes

1. This setup uses SQLite which is not production-level. Consider PostgreSQL for production.
2. Open registration is enabled by default. Disable it after creating necessary accounts.
3. Services communicate using container names within the `matrix-network` for better portability and isolation.
4. **Service Dependencies**: The docker-compose configuration ensures services start in the correct order:
   - Coturn starts first (TURN server for voice/video)
   - LiveKit starts (MatrixRTC media server)
   - lk-jwt-service starts after LiveKit (MatrixRTC authorization)
   - Synapse starts after coturn is ready (Matrix homeserver)
   - Element, Element Call, and synapse-admin start after synapse and lk-jwt-service are ready
5. **Environment Variables**: Use the `.env` file to customize your deployment without editing docker-compose.yaml
6. **LiveKit Integration**: Element Call now uses LiveKit as the MatrixRTC backend for improved video call quality and scalability

## Further reading and references

1. <https://github.com/coturn/coturn>
1. <https://matrix-org.github.io/synapse/v1.37/turn-howto.html>
1. <https://github.com/element-hq/lk-jwt-service> - MatrixRTC Authorization Service
1. <https://github.com/element-hq/element-call/blob/livekit/docs/self-hosting.md> - Element Call with LiveKit
1. <https://docs.livekit.io/> - LiveKit Documentation
1. <https://github.com/Miouyouyou/matrix-coturn-docker-setup/blob/master/docker-compose.1.yml>
1. <https://github.com/coturn/coturn/blob/master/docker/docker-compose-all.yml>
1. <https://github.com/spantaleev/matrix-docker-ansible-deploy/tree/master/docs>
1. <https://blog.bartab.fr/install-a-self-hosted-matrix-server-part-3/>
1. <https://github.com/vector-im/element-web/blob/develop/docs/config.md>
1. <https://matrix-org.github.io/synapse/latest/usage/administration/admin_faq.html>
1. <https://cyberhost.uk/element-matrix-setup/>
