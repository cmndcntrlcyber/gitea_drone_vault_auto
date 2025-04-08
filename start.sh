#!/bin/bash
set -e

# Function definitions
function error() {
    echo -e "\033[31mError: $*\033[0m"
    exit 1
}

function warning() {
    echo -e "\033[33mWarning: $*\033[0m"
}

function info() {
    echo -e "\033[32mInfo: $*\033[0m"
}

function check_requirements() {
    info "Checking requirements..."
    command -v docker >/dev/null 2>&1 || error "Docker is not installed. Please install Docker."
    command -v docker-compose >/dev/null 2>&1 || error "Docker Compose is not installed. Please install Docker Compose."
    
    # Check Docker service is running
    docker info >/dev/null 2>&1 || {
        warning "Docker service is not running. Attempting to start..."
        systemctl start docker.service || error "Failed to start Docker service."
    }
    
    info "All requirements satisfied."
}

function setup_environment() {
    info "Setting up environment..."
    
    # Set base path
    export BASE_PATH=${BASE_PATH:-/root/aliroot/ci_cd}
    
    # Create base directory if it doesn't exist
    if [ ! -d "${BASE_PATH}" ]; then
        info "Creating base directory at ${BASE_PATH}"
        mkdir -p "${BASE_PATH}" || error "Failed to create directory at ${BASE_PATH}"
    fi
    
    # Check for .env file
    if [ ! -f ".env" ] && [ ! -f "${BASE_PATH}/.env" ]; then
        error "No .env file found. Please create a .env file with the required variables."
    fi
    
    # Source .env file
    if [ -f ".env" ]; then
        info "Loading environment from local .env file"
        source .env
    elif [ -f "${BASE_PATH}/.env" ]; then
        info "Loading environment from ${BASE_PATH}/.env file"
        cd "${BASE_PATH}"
        source .env
    fi
    
    # Set required environment variables
    export MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
    
    # Gitea
    export GITEA_SERVER=${GITEA_PROTOCAL}://${GITEA_SERVER_HOST}
    export DRONE_GITEA_CLIENT_ID=${DRONE_GITEA_CLIENT_ID}
    export DRONE_GITEA_CLIENT_SECRET=${DRONE_GITEA_CLIENT_SECRET}
    
    # Drone
    export DRONE_SERVER_HOST=${SYS_DRONE_ADDR}
    export DRONE_SERVER_PROTO=${GITEA_PROTOCAL}
    
    # Database
    DB_TYPE=${DB_TYPE:-sqlite3}
    export DB_TYPE
    
    if [ "${DB_TYPE}" = "mysql" ]; then
        export DRONE_DATABASE_DATASOURCE="root:${MYSQL_ROOT_PASSWORD}@tcp(mysql-server:3306)/drone?parseTime=true"
    else
        export DRONE_DATABASE_DATASOURCE=/data/database.sqlite
    fi
    
    # Drone UI
    export DRONE_UI_PASSWORD=${DRONE_UI_PASSWORD}
    export DRONE_UI_USERNAME=${DRONE_UI_USERNAME}
    
    # Vault
    export VAULT_TOKEN=${VAULT_TOKEN}
    
    # MinIO
    export MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:-minioadmin}
    export MINIO_SECRET_KEY=${MINIO_SECRET_KEY:-minioadmin}
    
    # Drone RPC Secret
    export DRONE_RPC_SECRET=${DRONE_RPC_SECRET:-drone_secret_by_jyao}
    
    # Drone Vault Secret
    export DRONE_VAULT_SECRET=${DRONE_VAULT_SECRET:-provide_drone_vault_token_key_by_jyao}
    
    # Set timezone
    export TZ=${TZ:-Asia/Shanghai}
    
    info "Environment setup complete."
}

function prepare_directories() {
    info "Preparing directories and configuration files..."
    
    # Create required directories
    mkdir -p "${BASE_PATH}/vault/config"
    mkdir -p "${BASE_PATH}/gitea/gitea"
    mkdir -p "${BASE_PATH}/nginx"
    mkdir -p "${BASE_PATH}/redis"
    mkdir -p "${BASE_PATH}/registry"
    
    if [ "${DB_TYPE}" = "mysql" ]; then
        mkdir -p "${BASE_PATH}/mysql_/custom"
        mkdir -p "${BASE_PATH}/mysql_/datadir"
    fi
    
    # Copy configuration files
    cp -r vault_conf/* "${BASE_PATH}/vault/config"
    cp -r gitea_custom_config/* "${BASE_PATH}/gitea/gitea"
    
    # Replace placeholders in app.ini
    gitea_domain=${SYS__ADDR}
    sed -i "s/#gitea_domain#/${gitea_domain}/g" "${BASE_PATH}/gitea/gitea/conf/app.ini"
    sed -i "s/#gitea_domain_port#/${GITEA_DOMAIN_PORT}/g" "${BASE_PATH}/gitea/gitea/conf/app.ini"
    sed -i "s/#gitea_protocal#/${GITEA_PROTOCAL}/g" "${BASE_PATH}/gitea/gitea/conf/app.ini"
    sed -i "s/#mysql_root_password#/${MYSQL_ROOT_PASSWORD}/g" "${BASE_PATH}/gitea/gitea/conf/app.ini"
    sed -i "s/#db_type#/${DB_TYPE}/g" "${BASE_PATH}/gitea/gitea/conf/app.ini"
    sed -i "s?#gitea_root_url#?${GITEA_SERVER}?g" "${BASE_PATH}/gitea/gitea/conf/app.ini"
    
    # Replace IP in all files
    find "${BASE_PATH}/gitea" -type f -exec sed -i "s/need_to_replace_ip/${gitea_domain}/g" {} \;
    
    # Remove indexers directory to force rebuild
    rm -fr "${BASE_PATH}/gitea/gitea/indexers"
    
    info "Directory and configuration preparation complete."
}

function clean_docker() {
    info "Cleaning up Docker resources..."
    
    # Prune networks and system
    docker network prune -f
    docker system prune -f
    
    info "Docker cleanup complete."
}

function start_services() {
    info "Starting services in ${MODE} mode..."
    
    # Determine compose file arguments
    ARGS_COMPOSE=""
    if [ "${DB_TYPE}" = "mysql" ]; then
        ARGS_COMPOSE="-f docker-compose-mysql.yml -f docker-compose.yml"
    else
        ARGS_COMPOSE="-f docker-compose.yml"
    fi
    
    # Pull images if requested
    if [ "${PULL}" = "true" ]; then
        info "Pulling latest Docker images..."
        docker-compose ${ARGS_COMPOSE} pull --include-deps
    fi
    
    # Start services based on mode
    if [ "${MODE}" = "swarm" ]; then
        info "Starting in swarm mode..."
        
        if [ "${FORCE}" = "true" ]; then
            info "Removing existing stack..."
            docker stack rm gitea_all
            sleep 5
        fi
        
        info "Deploying stack..."
        docker-compose ${ARGS_COMPOSE} config | docker stack deploy -c - --prune --with-registry-auth gitea_all
        
        info "Swarm status:"
        docker node ls
        docker stack services gitea_all
    elif [ "${MODE}" = "compose" ]; then
        if [ "${FORCE}" = "true" ]; then
            info "Starting with force recreate..."
            docker-compose ${ARGS_COMPOSE} up --force-recreate --remove-orphans -d
        else
            info "Starting services..."
            docker-compose ${ARGS_COMPOSE} up -d
        fi
        
        info "Scaling runners..."
        docker-compose scale ssh-runner=2 docker-runner=2
        
        info "Service logs:"
        docker-compose logs -t --tail="100"
    else
        error "Invalid mode: ${MODE}. Must be 'swarm' or 'compose'."
    fi
    
    info "Services started successfully."
}

function show_status() {
    info "Current Docker status:"
    
    docker ps
    docker images
    
    info "Status check complete."
}

function initialize_vault() {
    info "Initializing Vault..."
    
    # Wait for Vault to be ready
    sleep 5
    
    # Unseal Vault
    if [ -f "secret_document/payload_vault.json" ]; then
        curl --request PUT --data "@secret_document/payload_vault.json" http://127.0.0.1:8200/v1/sys/unseal
        info "Vault unsealed successfully."
    else
        warning "Vault unseal payload not found. Vault may need to be unsealed manually."
    fi
}

function setup_portainer() {
    if [ "${PORTAINER}" = "true" ]; then
        info "Setting up Portainer..."
        
        curl -L https://downloads.portainer.io/portainer-agent-stack.yml | docker stack deploy -c - --prune --with-registry-auth portainer
        sleep 5
        
        # Initialize admin user
        curl --request POST http://127.0.0.1:9000/api/users/admin/init --data '{"Username":"admin","Password":"admin@admin"}'
        
        info "Portainer setup complete. Access at http://localhost:9000"
    fi
}

# Parse command line arguments
MODE=""
TEST="true"
PULL="false"
FORCE="true"
PORTAINER="false"

while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
    -m | --mode)
        MODE="$2"
        shift
        ;;
    -t | --test)
        TEST="$2"
        shift
        ;;
    -p | --pull)
        PULL="$2"
        shift
        ;;
    -f | --force)
        FORCE="$2"
        shift
        ;;
    --ui)
        PORTAINER="$2"
        shift
        ;;
    -h | --help)
        echo "Usage: ./start.sh [options]"
        echo "Options:"
        echo "  -m, --mode MODE       Set deployment mode (compose or swarm)"
        echo "  -t, --test BOOL       Test configuration before deployment (true/false)"
        echo "  -p, --pull BOOL       Pull latest images before deployment (true/false)"
        echo "  -f, --force BOOL      Force recreate containers (true/false)"
        echo "  --ui BOOL             Deploy Portainer UI (true/false)"
        echo "  -h, --help            Show this help message"
        exit 0
        ;;
    *)
        warning "Unknown option: $1"
        shift
        ;;
    esac
    shift
done

# Validate mode
if [ -z "${MODE}" ]; then
    error "Mode not specified. Use -m compose or -m swarm to specify the deployment mode."
fi

if [ "${MODE}" != "compose" ] && [ "${MODE}" != "swarm" ]; then
    error "Invalid mode: ${MODE}. Must be 'compose' or 'swarm'."
fi

# Main execution
check_requirements
setup_environment
prepare_directories
clean_docker

# Print configuration for testing
if [ "${TEST}" = "true" ]; then
    info "Testing configuration..."
    echo "#######################start##########################"
    docker-compose config
    echo "########################end#########################"
fi

start_services
show_status
initialize_vault
setup_portainer

info "Deployment complete! Your Gitea + Drone + Vault setup is now running."
