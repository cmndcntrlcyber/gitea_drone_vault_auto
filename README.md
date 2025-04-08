# Gitea + Drone + Vault Automated Setup

[![Build Status](https://drone.jyao.xyz/api/badges/jyao/gitea_drone_vault_auto/status.svg)](https://drone.jyao.xyz/jyao/gitea_drone_vault_auto)

An optimized, automated deployment solution for Gitea, Drone CI/CD, and HashiCorp Vault with Docker Compose and Docker Swarm support.

## Features

- **Gitea**: Self-hosted Git service
- **Drone CI/CD**: Continuous integration and delivery platform
- **HashiCorp Vault**: Secrets management
- **MinIO**: S3-compatible object storage
- **Docker Registry**: Private container registry
- **Redis**: Caching and session storage
- **MySQL/SQLite**: Database options
- **Nginx**: Reverse proxy
- **Watchtower**: Automatic container updates
- **Portainer**: Optional Docker management UI

## Prerequisites

- Docker Engine (19.03.0+)
- Docker Compose (1.27.0+)
- Docker Swarm (for swarm mode deployment)

## Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/jyao/gitea_drone_vault_auto.git
   cd gitea_drone_vault_auto
   ```

2. Create a `.env` file based on the provided example:
   ```bash
   cp .env.example .env
   ```

3. Edit the `.env` file with your configuration:
   ```bash
   nano .env
   ```

4. Start the services in compose mode:
   ```bash
   ./start.sh -m compose
   ```

   Or in swarm mode:
   ```bash
   ./start.sh -m swarm
   ```

## Environment Variables

Create a `.env` file in the project directory with the following variables:

```
# Required variables
SYS__ADDR=example.com                  # Gitea domain name
GITEA_PROTOCAL=http                    # Protocol (http or https)
GITEA_DOMAIN_PORT=3000                 # Gitea port
SYS_DRONE_ADDR=drone.example.com       # Drone domain name
GITEA_SERVER_HOST=example.com          # Gitea server host
DRONE_GITEA_CLIENT_ID=client_id        # Gitea OAuth application client ID
DRONE_GITEA_CLIENT_SECRET=secret       # Gitea OAuth application client secret
DRONE_UI_USERNAME=admin                # Drone UI username
DRONE_UI_PASSWORD=password             # Drone UI password
VAULT_TOKEN=vault_token                # Vault root token
MYSQL_ROOT_PASSWORD=password           # MySQL root password
DB_TYPE=mysql                          # Database type (mysql or sqlite3)
```

See `.env.example` for all available configuration options.

## Deployment Options

The `start.sh` script supports various deployment options:

```bash
Usage: ./start.sh [options]
Options:
  -m, --mode MODE       Set deployment mode (compose or swarm)
  -t, --test BOOL       Test configuration before deployment (true/false)
  -p, --pull BOOL       Pull latest images before deployment (true/false)
  -f, --force BOOL      Force recreate containers (true/false)
  --ui BOOL             Deploy Portainer UI (true/false)
  -h, --help            Show this help message
```

### Examples

- Start with Docker Compose and force recreate:
  ```bash
  ./start.sh -m compose -f true
  ```

- Start with Docker Swarm and pull latest images:
  ```bash
  ./start.sh -m swarm -p true
  ```

- Start with Portainer UI:
  ```bash
  ./start.sh -m compose --ui true
  ```

## Service Configuration

### Gitea

After deployment, Gitea will be available at `http://${SYS__ADDR}:${GITEA_DOMAIN_PORT}`.

To create an OAuth application for Drone:
1. Log in to Gitea
2. Go to Settings > Applications
3. Create a new OAuth application with:
   - Name: Drone
   - Redirect URI: `http://${SYS_DRONE_ADDR}/login`
4. Copy the generated Client ID and Client Secret to your `.env` file

### Drone

Drone will be available at `http://${SYS_DRONE_ADDR}`.

### Vault

Vault will be available at `http://localhost:8200`.

Initial root token is set by the `VAULT_TOKEN` environment variable.

## Health Checks

All services include health checks to ensure proper operation. You can monitor service health with:

```bash
docker ps
```

## Resource Limits

The deployment includes resource limits for each service to prevent resource exhaustion:

- Gitea: 1 CPU, 1GB RAM
- Drone Server: 1 CPU, 1GB RAM
- Docker Runners: 1 CPU, 1GB RAM
- MySQL: 1 CPU, 1GB RAM
- Other services: Appropriate limits based on their requirements

## Backup and Restore

All persistent data is stored in volumes under the `${BASE_PATH}` directory. To backup your data:

```bash
tar -czvf backup.tar.gz ${BASE_PATH}
```

To restore:

```bash
tar -xzvf backup.tar.gz -C /
```

## SSL Configuration

For production use, it's recommended to configure SSL. You can:

1. Use Nginx as a reverse proxy with SSL termination
2. Generate self-signed certificates:
   ```bash
   openssl req -newkey rsa:4096 -nodes -keyout domain.key -x509 -days 365 -out domain.crt
   ```

## Troubleshooting

### Docker daemon stops during startup

If the Docker daemon stops unexpectedly:

```bash
# Check Docker logs
journalctl -u docker.service

# Manually remove problematic containers
docker rm -f <container-id>

# Restart the deployment
./start.sh -m compose -f true
```

### Vault is sealed

If Vault becomes sealed:

```bash
# Unseal Vault
curl --request PUT --data "@secret_document/payload_vault.json" http://127.0.0.1:8200/v1/sys/unseal
```

## Advanced Configuration

### S3 Storage with MinIO

MinIO provides S3-compatible storage for Drone logs and artifacts:

- MinIO UI: http://localhost:9001
- Default credentials: minioadmin / minioadmin

### Docker Registry

A private Docker registry is available at `localhost:5003`.

### Watchtower

Watchtower automatically updates containers to their latest versions daily.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
