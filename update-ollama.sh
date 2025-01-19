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
    echo -e "${RED}Please ensure Ollama is running before updating${NC}"
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
            ;;
        "container")
            echo -e "${BLUE}Found containerized Ollama${NC}"
            update_container_ollama
            ;;
    esac
    
    echo -e "${GREEN}✅ Ollama update completed successfully (${OLLAMA_MODE} mode)${NC}"
}

# Execute main function
main