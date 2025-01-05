#!/bin/bash

# Set error handling
set -e

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting Open WebUI update process...${NC}"

# Configuration
WEBUI_PORT=${OPEN_WEBUI_PORT:-3000}
WEBUI_CONTAINER="open-webui"
WEBUI_IMAGE="ghcr.io/open-webui/open-webui:cuda"

# Function to check if docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not running or you don't have permissions${NC}"
        exit 1
    fi
}

# Function to check if container exists
check_container() {
    if ! docker ps -a --format '{{.Names}}' | grep -q "^$WEBUI_CONTAINER$"; then
        echo -e "${RED}Error: $WEBUI_CONTAINER container not found${NC}"
        exit 1
    fi
}

# Function to check if ollama is running locally
check_ollama() {
    if ! curl -s http://localhost:11434/api/version >/dev/null 2>&1; then
        echo -e "${RED}Error: Ollama is not running on localhost:11434${NC}"
        echo -e "${RED}Please ensure Ollama is running before updating Open WebUI${NC}"
        exit 1
    fi
}

# Function to check GPU support
check_gpu_support() {
    if ! command -v nvidia-smi &> /dev/null; then
        echo -e "${RED}Warning: NVIDIA drivers not found. Continuing without GPU support...${NC}"
        GPU_ARGS=""
    else
        echo -e "${GREEN}GPU support detected, enabling CUDA...${NC}"
        GPU_ARGS="--gpus all"
    fi
}

# Function to backup volume
backup_volume() {
    echo -e "${BLUE}Creating backup of persistent data...${NC}"
    
    # Create backup directory with timestamp
    BACKUP_DIR="open-webui_backup_$(date +%Y%m%d_%H%M%S)"
    
    # Backup open-webui data
    if docker volume ls | grep -q "open-webui"; then
        echo -e "${BLUE}Backing up open-webui data...${NC}"
        # Create backup directory with proper permissions
        sudo mkdir -p "$BACKUP_DIR"
        
        # Get Docker volume path
        local volume_path=$(docker volume inspect open-webui --format '{{ .Mountpoint }}')
        
        # Create backup using native tar
        echo -e "${BLUE}Creating backup from $volume_path...${NC}"
        sudo tar czf "$BACKUP_DIR/open-webui-data.tar.gz" -C "$volume_path" .
        
        # Set proper permissions for the backup
        sudo chown $USER:$USER "$BACKUP_DIR/open-webui-data.tar.gz"
        
        echo -e "${GREEN}✅ Backup created in $BACKUP_DIR${NC}"
    else
        echo -e "${RED}Error: open-webui volume not found${NC}"
        exit 1
    fi
}

# Main update process
main() {
    echo -e "${BLUE}Checking Docker...${NC}"
    check_docker
    
    echo -e "${BLUE}Checking existing container...${NC}"
    check_container
    
    echo -e "${BLUE}Checking Ollama service...${NC}"
    check_ollama
    
    # Check GPU support
    check_gpu_support
    
    # Backup existing data
    backup_volume
    
    echo -e "${BLUE}Stopping container...${NC}"
    docker stop $WEBUI_CONTAINER || true
    docker rm $WEBUI_CONTAINER || true
    
    echo -e "${BLUE}Pulling latest image...${NC}"
    docker pull $WEBUI_IMAGE
    
    echo -e "${BLUE}Starting Open WebUI container...${NC}"
    docker run -d \
        $GPU_ARGS \
        -p $WEBUI_PORT:8080 \
        --network=host \
        --mount type=volume,source=open-webui,target=/app/backend/data \
        --name $WEBUI_CONTAINER \
        -e OLLAMA_BASE_URL=http://localhost:11434 \
        --restart always \
        $WEBUI_IMAGE
    
    echo -e "${BLUE}Waiting for service to start...${NC}"
    sleep 5
    
    # Check if container is running
    if docker ps | grep -q "$WEBUI_CONTAINER"; then
        echo -e "${GREEN}✅ Update completed successfully!${NC}"
        echo -e "${GREEN}✅ Persistent data has been preserved and reattached${NC}"
        echo -e "${GREEN}✅ Backup created in $BACKUP_DIR${NC}"
        if [ ! -z "$GPU_ARGS" ]; then
            echo -e "${GREEN}✅ GPU support enabled${NC}"
        fi
        echo -e "${GREEN}✅ Connected to local Ollama service${NC}"
        echo -e "${BLUE}Open WebUI is running at: http://localhost:$WEBUI_PORT${NC}"
    else
        echo -e "${RED}❌ Error: Container failed to start properly${NC}"
        echo -e "${RED}Please check docker logs for more information:${NC}"
        echo "docker logs $WEBUI_CONTAINER"
        echo -e "${RED}Your data is safely backed up in $BACKUP_DIR${NC}"
        exit 1
    fi
}

# Execute main function
main
