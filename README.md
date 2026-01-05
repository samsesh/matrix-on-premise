# Samsesh Chat - Self-Hosted Matrix Server

A complete self-hosted chat platform powered by Matrix Synapse, Element Web, and Coturn for voice/video calls. This setup provides an easy-to-deploy, privacy-focused communication solution.

## Features

- 🚀 **One-Command Setup**: Automated installation with interactive script
- 💬 **Modern UI**: Element Web client with custom Samsesh branding
- 🎥 **Voice & Video**: Built-in Coturn TURN server for reliable calls
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
4. Open ports: 8080 (Element), 8008 (Synapse), 8448 (Federation), 8081 (Admin), 3478/5349 (TURN)

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
- Admin user creation
- Port configuration
- Automatic service deployment

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

1. deploy the docker compose

    ```bash
    sudo docker-compose up -d
    ```

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

## Accessing Your Server

After installation, access your services at:

- **Element Web (Chat Interface)**: `http://localhost:8080` or `http://your-server-ip:8080`
- **Synapse API**: `http://localhost:8008`
- **Synapse Admin Panel**: `http://localhost:8081`

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

The setup includes Samsesh Chat branding by default. To customize:

1. Edit `element-config.json` and change the `brand` field
2. Replace logo in `element-theme/logo.png` with your own
3. Restart Element: `docker compose restart element`

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
3. **Regular Updates**: Keep Docker images updated
4. **Backups**: Regularly backup your data
5. **Strong Passwords**: Use complex passwords for admin accounts
6. **Disable Open Registration**: After creating accounts, disable open registration

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
3. Services communicate using container names for better portability.

## Further reading and references

1. <https://github.com/coturn/coturn>
1. <https://matrix-org.github.io/synapse/v1.37/turn-howto.html>
1. <https://github.com/Miouyouyou/matrix-coturn-docker-setup/blob/master/docker-compose.1.yml>
1. <https://github.com/coturn/coturn/blob/master/docker/docker-compose-all.yml>
1. <https://github.com/spantaleev/matrix-docker-ansible-deploy/tree/master/docs>
1. <https://blog.bartab.fr/install-a-self-hosted-matrix-server-part-3/>
1. <https://github.com/vector-im/element-web/blob/develop/docs/config.md>
1. <https://matrix-org.github.io/synapse/latest/usage/administration/admin_faq.html>
1. <https://cyberhost.uk/element-matrix-setup/>
