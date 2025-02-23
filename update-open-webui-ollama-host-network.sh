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
WEBUI_IMAGE="ghcr.io/open-webui/open-webui:cuda"
# WEBUI_CONTAINER will be set by check_container function

# Function to check if docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not running or you don't have permissions${NC}"
        exit 1
    fi
}

# Function to check if container exists and get its name
check_container() {
    # Find any container with "open-webui" in its name
    WEBUI_CONTAINER=$(docker ps -a --format '{{.Names}}' | grep -i "open-webui" | head -n1)
    
    if [ -z "$WEBUI_CONTAINER" ]; then
        echo -e "${RED}Error: No Open WebUI container found${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Found container: $WEBUI_CONTAINER${NC}"
}

# Function to verify Ollama is running
verify_ollama_running() {
    local attempt=1
    local max_attempts=5
    
    while [ $attempt -le $max_attempts ]; do
        echo -e "${BLUE}Checking if Ollama is running (attempt $attempt of $max_attempts)...${NC}"
        
        if curl -s http://localhost:11434/api/version >/dev/null 2>&1; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            echo -e "${YELLOW}Ollama not responding, waiting 10 seconds before next attempt...${NC}"
            sleep 10
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Function to detect Ollama running mode
detect_ollama_mode() {
    # First check if Ollama is running as a container
    if docker ps --format '{{.Names}}' | grep -q "^ollama$"; then
        if verify_ollama_running; then
            echo "container"
            return
        fi
    fi
    
    # Then check if it's running locally
    if verify_ollama_running; then
        echo "local"
        return
    fi
    
    echo -e "${RED}Error: Ollama is not running either locally or in a container${NC}"
    echo -e "${RED}Please ensure Ollama is running before updating Open WebUI${NC}"
    exit 1
}

# Function to update local Ollama installation
update_local_ollama() {
    echo -e "${BLUE}Updating local Ollama installation...${NC}"
    curl -fsSL https://ollama.com/install.sh | sh
    
    echo -e "${BLUE}Verifying Ollama installation...${NC}"
    if ! verify_ollama_running; then
        echo -e "${RED}Error: Ollama update failed or service not running after 5 attempts${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Ollama updated successfully${NC}"
}

# Function to update containerized Ollama
update_container_ollama() {
    echo -e "${BLUE}Updating Ollama container...${NC}"
    
    # Stop the container
    echo -e "${BLUE}Stopping Ollama container...${NC}"
    docker stop ollama
    
    # Remove the container but keep the volume
    echo -e "${BLUE}Removing old container...${NC}"
    docker rm ollama
    
    # Pull latest image
    echo -e "${BLUE}Pulling latest Ollama image...${NC}"
    if command -v nvidia-smi &> /dev/null; then
        docker pull ollama/ollama
        # Start with GPU support
        docker run -d --gpus=all -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama
    else
        docker pull ollama/ollama
        # Start without GPU support
        docker run -d -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama
    fi
    
    # Verify container is running
    echo -e "${BLUE}Verifying Ollama container...${NC}"
    local attempt=1
    local max_attempts=5
    
    while [ $attempt -le $max_attempts ]; do
        echo -e "${BLUE}Checking container status (attempt $attempt of $max_attempts)...${NC}"
        
        if docker ps | grep -q "ollama" && verify_ollama_running; then
            echo -e "${GREEN}✅ Ollama container updated successfully${NC}"
            return
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            echo -e "${YELLOW}Container not ready, waiting 10 seconds before next attempt...${NC}"
            sleep 10
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}Error: Ollama container failed to start properly after 5 attempts${NC}"
    exit 1
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
    
    echo -e "${BLUE}Detecting Ollama installation type...${NC}"
    OLLAMA_MODE=$(detect_ollama_mode)
    
    # Update Ollama based on installation type
    case $OLLAMA_MODE in
        "local")
            echo -e "${BLUE}Found local Ollama installation${NC}"
            update_local_ollama
            ;;
        "container")
            echo -e "${BLUE}Found containerized Ollama${NC}"
            update_container_ollama
            ;;
    esac
    
    # Check GPU support
    check_gpu_support
    
    # Backup existing data
    backup_volume
    
    echo -e "${BLUE}Stopping Open WebUI container...${NC}"
    docker stop $WEBUI_CONTAINER || true
    docker rm $WEBUI_CONTAINER || true
    
    echo -e "${BLUE}Pulling latest Open WebUI image...${NC}"
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
        echo -e "${GREEN}✅ Ollama updated successfully (${OLLAMA_MODE} mode)${NC}"
        if [ ! -z "$GPU_ARGS" ]; then
            echo -e "${GREEN}✅ GPU support enabled${NC}"
        fi
        echo -e "${GREEN}✅ Connected to local Ollama service${NC}"
        echo -e "${BLUE}Open WebUI is running at: http://localhost:$WEBUI_PORT${NC}"

        # Clean up backup after successful update
        echo -e "${BLUE}Cleaning up temporary backup...${NC}"
        sudo rm -rf "$BACKUP_DIR"
        echo -e "${GREEN}✓ Temporary backup removed${NC}"
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
