# How to Self-Host synapse Matrix + Element + Coturn + Admin Web UI (Docker Compose)

Here we will discuss the easiest way to install a chat platform for personal use cases with Docker Compose on a Linux server. We are not going into detail as I'm assuming the reader is familiar with Linux, Docker, and some basic networking terms. But let me know if you think I should update this doc in advance.
This doc is the minimal and most straightforward approach that I could get to set up a private chat server with reliable VoIP and Video features. On the other hand, "Synapse Matrix" and "Element" are super powerful and customizable; peek at the official documentation.

1. <https://matrix.org/docs/projects/server/synapse>
1. <https://element.io/solutions/on-premise-collaboration>

## Notes before we dive in

1. This setup is powered by SQLITE which is not production level database server consider using PostgreSQL instead.
1. This setup is allowing user registration without any verification, but its easy to config a central authentication with LDAP server.
1. Services communicate using container names instead of IP addresses for better portability.

## Requirements

1. A Linux server with a Public IP
1. Installed docker + docker compose

## Steps

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

1. That's it, all done. you can create users with the admin web ui and download the client App from:

    1. iOS: <https://apps.apple.com/us/app/element-messenger/id1083446067>  
    1. Android: <https://play.google.com/store/apps/details?id=im.vector.app&hl=en&gl=US>  
    1. Android (Cafe Bazar): <https://cafebazaar.ir/app/im.vector.app>  

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
