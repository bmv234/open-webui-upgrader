#!/bin/bash

# Set error handling
set -e

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting Ollama update process...${NC}"

# Function to check if docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not running or you don't have permissions${NC}"
        exit 1
    fi
}

# Function to verify Ollama API is responding
verify_ollama_running() {
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:11434/api/version >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Function to wait for Ollama to be ready
wait_for_ollama() {
    echo -e "${BLUE}Waiting for Ollama to start...${NC}"
    if verify_ollama_running; then
        echo -e "${GREEN}✅ Ollama is responding${NC}"
        return 0
    else
        echo -e "${RED}Error: Ollama failed to respond after update${NC}"
        return 1
    fi
}

# Function to detect Ollama running mode
detect_ollama_mode() {
    # Check if Ollama container exists (running or not)
    if docker ps -a --format '{{.Names}}' | grep -q "^ollama$"; then
        echo "container"
        return
    fi
    
    # Default to local mode if no container found
    echo "local"
    return
}

# Function to update local Ollama installation
update_local_ollama() {
    echo -e "${BLUE}Updating local Ollama installation...${NC}"
    if ! curl -fsSL https://ollama.com/install.sh | sh; then
        echo -e "${RED}Error: Failed to download or run Ollama installer${NC}"
        exit 1
    fi
}

# Function to update containerized Ollama
update_container_ollama() {
    echo -e "${BLUE}Updating Ollama container...${NC}"
    
    # Stop and remove existing container
    docker stop ollama >/dev/null 2>&1 || true
    docker rm ollama >/dev/null 2>&1 || true
    
    # Pull latest image
    echo -e "${BLUE}Pulling latest Ollama image...${NC}"
    if ! docker pull ollama/ollama; then
        echo -e "${RED}Failed to pull latest Ollama image${NC}"
        exit 1
    fi

    # Start container with appropriate GPU support
    echo -e "${BLUE}Starting new container...${NC}"
    if command -v nvidia-smi &> /dev/null; then
        docker run -d --gpus=all -v ollama:/root/.ollama -p 11434:11434 --restart always --name ollama ollama/ollama >/dev/null
    else
        docker run -d -v ollama:/root/.ollama -p 11434:11434 --restart always --name ollama ollama/ollama >/dev/null
    fi
}

# Main update process
main() {
    echo -e "${BLUE}Checking Docker...${NC}"
    check_docker
    
    echo -e "${BLUE}Detecting Ollama installation type...${NC}"
    OLLAMA_MODE=$(detect_ollama_mode)
    
    # Update Ollama based on installation type
    case $OLLAMA_MODE in
        "local")
            echo -e "${BLUE}Found local Ollama installation${NC}"
            update_local_ollama
            if ! wait_for_ollama; then
                exit 1
            fi
            ;;
        "container")
            echo -e "${BLUE}Found containerized Ollama${NC}"
            update_container_ollama
            if ! wait_for_ollama; then
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}Error: Unknown Ollama installation type${NC}"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}✅ Ollama update completed successfully (${OLLAMA_MODE} mode)${NC}"
}

# Execute main function
main