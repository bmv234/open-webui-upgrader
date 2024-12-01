#!/bin/bash

# Set error handling
set -e

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WEBUI_CONTAINER="open-webui"
LOCAL_BACKUP_BASE="$HOME/open-webui-backups"

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

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check for cifs-utils if needed for SMB
    if ! command -v mount.cifs &> /dev/null; then
        missing_deps+=("cifs-utils")
    fi
    
    # Check for cron
    if ! command -v crontab &> /dev/null; then
        missing_deps+=("cron")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Missing required dependencies: ${missing_deps[*]}${NC}"
        echo "Installing missing dependencies..."
        sudo apt-get update
        sudo apt-get install -y "${missing_deps[@]}"
    fi
}

# Function to create backup
create_backup() {
    local backup_path="$1"
    local backup_name="open-webui_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_dir="$backup_path/$backup_name"
    
    echo -e "${BLUE}Creating backup in: $backup_dir${NC}"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Backup open-webui data
    if docker volume ls | grep -q "open-webui"; then
        echo "Backing up open-webui data..."
        docker run --rm \
            -v open-webui:/data \
            -v "$backup_dir":/backup \
            alpine tar czf /backup/open-webui-data.tar.gz -C /data ./
        
        echo -e "${GREEN}✅ Backup completed successfully!${NC}"
        echo "Backup location: $backup_dir"
    else
        echo -e "${RED}Error: open-webui volume not found${NC}"
        exit 1
    fi
}

# Function to validate SMB path
validate_smb_path() {
    local path="$1"
    if [[ ! "$path" =~ ^//[^/]+/[^/].* ]]; then
        echo -e "${RED}Error: Invalid SMB path format${NC}"
        echo "Path must start with // followed by hostname/IP and share name"
        echo "Example: //192.168.1.100/backups"
        return 1
    fi
    return 0
}

# Function to setup SMB mount
setup_smb_mount() {
    echo -e "${BLUE}Please enter SMB share details:${NC}"
    echo "Format: //hostname_or_ip/share_name"
    echo "Example: //192.168.1.100/backups"
    
    while true; do
        read -p "SMB Share Path: " smb_path
        if validate_smb_path "$smb_path"; then
            break
        fi
    done
    
    read -p "Username: " smb_username
    read -s -p "Password: " smb_password
    echo
    
    # Optional domain input
    read -p "Domain (press Enter to skip): " smb_domain
    
    # Create mount point
    local mount_point="/mnt/open-webui-backup"
    sudo mkdir -p "$mount_point"
    
    # Store credentials securely
    local cred_file="/root/.open-webui-smb-credentials"
    echo "username=$smb_username" | sudo tee "$cred_file" > /dev/null
    echo "password=$smb_password" | sudo tee -a "$cred_file" > /dev/null
    if [ ! -z "$smb_domain" ]; then
        echo "domain=$smb_domain" | sudo tee -a "$cred_file" > /dev/null
    fi
    sudo chmod 600 "$cred_file"
    
    # Add to fstab for persistent mount
    local mount_options="credentials=$cred_file,iocharset=utf8,file_mode=0777,dir_mode=0777"
    
    # Add domain to mount options if provided
    if [ ! -z "$smb_domain" ]; then
        mount_options="$mount_options,domain=$smb_domain"
    fi
    
    local fstab_entry="$smb_path $mount_point cifs $mount_options 0 0"
    if ! grep -q "$mount_point" /etc/fstab; then
        echo "$fstab_entry" | sudo tee -a /etc/fstab > /dev/null
    fi
    
    # Mount the share
    sudo mount -a
    
    echo "$mount_point"
}

# Function to setup backup schedule
setup_schedule() {
    local backup_type="$1"
    local backup_path="$2"
    local schedule=""
    local script_path="$(realpath "$0")"
    
    case "$backup_type" in
        "weekly")
            schedule="0 0 * * 0" # Every Sunday at midnight
            ;;
        "monthly")
            schedule="0 0 1 * *" # First day of each month at midnight
            ;;
    esac
    
    # Create cron job
    (crontab -l 2>/dev/null || true; echo "$schedule $script_path --auto-backup \"$backup_path\"") | crontab -
    
    echo -e "${GREEN}✅ Backup schedule set successfully!${NC}"
}

# Function to run backup wizard
backup_wizard() {
    echo -e "${BLUE}Welcome to Open WebUI Backup Wizard!${NC}"
    
    # Check dependencies first
    check_dependencies
    
    # Backup frequency
    echo -e "\nSelect backup frequency:"
    echo "1) One-time backup"
    echo "2) Weekly backup"
    echo "3) Monthly backup"
    read -p "Enter your choice (1-3): " frequency_choice
    
    # Backup location
    echo -e "\nSelect backup location:"
    echo "1) Local directory"
    echo "2) SMB share"
    read -p "Enter your choice (1-2): " location_choice
    
    # Setup backup path
    backup_path=""
    case $location_choice in
        1)
            backup_path="$LOCAL_BACKUP_BASE"
            mkdir -p "$backup_path"
            ;;
        2)
            backup_path=$(setup_smb_mount)
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
    
    # Handle backup frequency
    case $frequency_choice in
        1)
            create_backup "$backup_path"
            ;;
        2)
            setup_schedule "weekly" "$backup_path"
            create_backup "$backup_path" # Initial backup
            ;;
        3)
            setup_schedule "monthly" "$backup_path"
            create_backup "$backup_path" # Initial backup
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
}

# Main execution
if [ "$1" == "--auto-backup" ]; then
    # Running in automatic mode (from cron)
    backup_path="$2"
    create_backup "$backup_path"
else
    # Interactive wizard mode
    echo "Checking Docker..."
    check_docker
    
    echo "Checking existing container..."
    check_container
    
    backup_wizard
fi
