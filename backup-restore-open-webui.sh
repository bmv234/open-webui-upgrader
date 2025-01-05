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
    
    # Backup open-webui data
    if docker volume ls | grep -q "open-webui"; then
        echo -e "${BLUE}Backing up open-webui data...${NC}"
        # Create backup directory with proper permissions
        sudo mkdir -p "$backup_dir"
        
        # Get Docker volume path
        local volume_path=$(docker volume inspect open-webui --format '{{ .Mountpoint }}')
        
        # Create backup using native tar
        echo -e "${BLUE}Creating backup from $volume_path...${NC}"
        sudo tar czf "$backup_dir/open-webui-data.tar.gz" -C "$volume_path" .
        
        # Set proper permissions for the backup
        sudo chown $USER:$USER "$backup_dir/open-webui-data.tar.gz"
        
        echo -e "${GREEN}✅ Backup completed successfully!${NC}"
        echo -e "${GREEN}Backup location: $backup_dir${NC}"
    else
        echo -e "${RED}Error: open-webui volume not found${NC}"
        exit 1
    fi
}

# Function to restore from backup
restore_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}Error: Backup file not found: $backup_file${NC}"
        exit 1
    fi
    
    echo -e "${RED}WARNING: This will overwrite all existing Open WebUI data!${NC}"
    echo -e "${RED}Any changes made since the backup will be lost.${NC}"
    echo -e "${BLUE}Backup to restore: $backup_file${NC}"
    echo
    read -p "Are you sure you want to proceed with the restore? (yes/no): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${BLUE}Restore cancelled.${NC}"
        exit 0
    fi
    
    echo
    echo -e "${BLUE}Starting restore process...${NC}"
    
    # Stop the container if it's running
    if docker ps | grep -q "$WEBUI_CONTAINER"; then
        echo -e "${BLUE}Stopping Open WebUI container...${NC}"
        docker stop "$WEBUI_CONTAINER"
    fi
    
    # Create a new volume if it doesn't exist
    if ! docker volume ls | grep -q "open-webui"; then
        echo -e "${BLUE}Creating new volume...${NC}"
        docker volume create open-webui
    fi
    
    # Restore the backup
    echo -e "${BLUE}Restoring data...${NC}"
    # Get Docker volume path
    local volume_path=$(docker volume inspect open-webui --format '{{ .Mountpoint }}')
    
    # Clear existing data
    sudo rm -rf "$volume_path"/*
    
    # Restore from backup using native tar
    echo -e "${BLUE}Restoring from backup to $volume_path...${NC}"
    sudo tar xzf "$backup_file" -C "$volume_path"
    
    # Fix permissions
    sudo chown -R root:root "$volume_path"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Restore failed${NC}"
        exit 1
    fi
    
    # Restart the container if it was running
    if docker ps -a | grep -q "$WEBUI_CONTAINER"; then
        echo -e "${BLUE}Starting Open WebUI container...${NC}"
        # Wait a moment for the port to be fully released
        sleep 2
        if ! docker start "$WEBUI_CONTAINER"; then
            echo -e "${RED}Failed to start container. Waiting longer for port to be released...${NC}"
            sleep 5
            if ! docker start "$WEBUI_CONTAINER"; then
                echo -e "${RED}Still unable to start container. You may need to:${NC}"
                echo -e "${RED}1. Check if any process is using port 3000: sudo lsof -i :3000${NC}"
                echo -e "${RED}2. Stop the process if needed${NC}"
                echo -e "${RED}3. Then manually start the container: docker start $WEBUI_CONTAINER${NC}"
                exit 1
            fi
        fi
    fi
    
    echo -e "${GREEN}✅ Restore completed successfully!${NC}"
}

# Function to list available backups
list_backups() {
    local backup_path="$1"
    local backups=()
    
    echo -e "${BLUE}Available backups:${NC}"
    
    # Find all backup directories
    while IFS= read -r dir; do
        if [ -f "$dir/open-webui-data.tar.gz" ]; then
            backups+=("$dir")
            echo -e "${BLUE}$((${#backups[@]}))) $(basename "$dir")${NC}"
        fi
    done < <(find "$backup_path" -type d -name "open-webui_backup_*" | sort -r)
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}No backups found in $backup_path${NC}"
        exit 1
    fi
    
    # Let user select a backup
    read -p "Select backup to restore (1-${#backups[@]}): " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#backups[@]}" ]; then
        local selected_backup="${backups[$((selection-1))]}/open-webui-data.tar.gz"
        restore_backup "$selected_backup"
    else
        echo -e "${RED}Invalid selection${NC}"
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
    local mount_point="/mnt/open-webui-backup"
    
    # Get SMB details without printing format info first
    while true; do
        read -p "SMB Share Path (//hostname/share): " smb_path
        if validate_smb_path "$smb_path"; then
            break
        fi
    done
    
    read -p "Username: " smb_username
    read -s -p "Password: " smb_password
    echo
    
    # Optional domain input
    read -p "Domain (press Enter to skip): " smb_domain
    
    # Create mount point if it doesn't exist
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
    
    # Unmount if already mounted
    if mountpoint -q "$mount_point"; then
        sudo umount "$mount_point" || {
            echo -e "${RED}Error: Failed to unmount existing share${NC}"
            exit 1
        }
    fi
    
    # Mount the share
    echo -e "${BLUE}Mounting SMB share...${NC}"
    if ! sudo mount -a; then
        echo -e "${RED}Error: Failed to mount SMB share${NC}"
        echo -e "${RED}Please check your credentials and network connectivity${NC}"
        exit 1
    fi
    
    # Create backup directory structure
    local backup_base="$mount_point/open-webui-backups"
    sudo mkdir -p "$backup_base"
    
    if [ ! -d "$backup_base" ]; then
        echo -e "${RED}Error: Failed to create backup directory in SMB share${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}SMB share mounted at: $backup_base${NC}"
    echo "$backup_base"
}

# Function to setup backup schedule
setup_schedule() {
    local backup_type="$1"
    local backup_path="$2"
    local schedule=""
    local script_path="$(realpath "$0")"
    
    case "$backup_type" in
        "daily")
            schedule="0 0 * * *" # Every day at midnight
            ;;
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
    
    # Operation selection
    echo -e "\nSelect operation:"
    echo "1) Create backup"
    echo "2) Restore from backup"
    read -p "Enter your choice (1-2): " operation_choice
    
    case $operation_choice in
        1)
            # Backup frequency
            echo -e "\nSelect backup frequency:"
            echo "1) One-time backup"
            echo "2) Daily backup"
            echo "3) Weekly backup"
            echo "4) Monthly backup"
            read -p "Enter your choice (1-4): " frequency_choice
            
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
                    setup_schedule "daily" "$backup_path"
                    create_backup "$backup_path" # Initial backup
                    ;;
                3)
                    setup_schedule "weekly" "$backup_path"
                    create_backup "$backup_path" # Initial backup
                    ;;
                4)
                    setup_schedule "monthly" "$backup_path"
                    create_backup "$backup_path" # Initial backup
                    ;;
                *)
                    echo -e "${RED}Invalid choice${NC}"
                    exit 1
                    ;;
            esac
            ;;
        2)
            # Restore location
            echo -e "\nSelect restore location:"
            echo "1) Local directory"
            echo "2) SMB share"
            read -p "Enter your choice (1-2): " location_choice
            
            # Setup restore path
            restore_path=""
            case $location_choice in
                1)
                    restore_path="$LOCAL_BACKUP_BASE"
                    if [ ! -d "$restore_path" ]; then
                        echo -e "${RED}No local backups found${NC}"
                        exit 1
                    fi
                    ;;
                2)
                    restore_path=$(setup_smb_mount)
                    ;;
                *)
                    echo -e "${RED}Invalid choice${NC}"
                    exit 1
                    ;;
            esac
            
            list_backups "$restore_path"
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
    echo -e "${BLUE}Checking Docker...${NC}"
    check_docker
    
    echo -e "${BLUE}Checking existing container...${NC}"
    check_container
    
    backup_wizard
fi
