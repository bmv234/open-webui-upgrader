#!/bin/bash

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Set error handling
set -e

# Configuration
LOCAL_BACKUP_BASE="$HOME/open-webui-backups"
TEMP_MOUNT="/tmp/open-webui-backup"

# Function to check if docker is installed and running
check_docker() {
    # Check if docker command exists
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker is not installed. Please install Docker first.${NC}"
        exit 1
    fi
    
    # Check if docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not running or you don't have permissions${NC}"
        echo -e "${BLUE}Try starting Docker with: sudo systemctl start docker${NC}"
        exit 1
    fi
    
    # Check docker-compose version
    if ! docker-compose version &> /dev/null; then
        echo -e "${YELLOW}Warning: docker-compose not found. Some features may be limited.${NC}"
    fi
}

# Function to find and confirm container
find_container() {
    # Show current containers
    printf "\n${BLUE}Current containers:${NC}\n"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"
    printf "\n"

    # Find Open WebUI container
    local container_name
    container_name=$(docker ps -a --format '{{.Names}}' | grep -iE 'open-webui' | head -n1)

    if [ -z "$container_name" ]; then
        printf "${RED}Error: No Open WebUI containers found${NC}\n"
        exit 1
    fi

    # Show container details
    printf "${BLUE}Found Open WebUI container:${NC}\n"
    docker ps -a --filter "name=$container_name" --format "Name:   {{.Names}}\nStatus: {{.Status}}\nImage:  {{.Image}}\nPorts:  {{.Ports}}"
    printf "\n\n"

    # Confirm with user
    read -p "Use this container? (yes/no): " confirm
    if [[ ! "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        printf "${RED}Operation cancelled${NC}\n"
        exit 1
    fi

    echo "$container_name"
}

# Function to check for cifs-utils
check_dependencies() {
    if ! command -v mount.cifs &> /dev/null; then
        echo -e "${RED}Installing cifs-utils for SMB support...${NC}"
        sudo apt-get update
        sudo apt-get install -y cifs-utils
    fi
}

# Function to create backup
create_backup() {
    local backup_path="$1"
    local container_name="$2"
    local backup_dir="$backup_path"
    
    # Check Docker volume
    if ! docker volume ls | grep -q "open-webui"; then
        echo -e "${RED}Error: open-webui volume not found${NC}" >&2
        exit 1
    fi

    # Get Docker volume path
    local volume_path=$(docker volume inspect open-webui --format '{{ .Mountpoint }}')
    
    # Create backup file

    # Create backup file
    local backup_name="open-webui-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
    local local_backup="$LOCAL_BACKUP_BASE/$backup_name"
    echo -e "${BLUE}Creating backup...${NC}" >&2
    
    # Create backup
    if ! sudo tar czf "$local_backup" -C "$volume_path" .; then
        echo -e "${RED}Error: Backup creation failed${NC}" >&2
        rm -f "$local_backup"
        exit 1
    fi

    # Verify backup file exists and is not empty
    if [ ! -f "$local_backup" ] || [ ! -s "$local_backup" ]; then
        echo -e "${RED}Error: Backup file is empty or missing${NC}" >&2
        rm -f "$local_backup"
        exit 1
    fi
    
    # Set full permissions
    echo -e "${BLUE}Setting permissions...${NC}" >&2
    sudo chown $USER:$USER "$local_backup"
    chmod 777 "$local_backup"

    # If using SMB, copy to share and remove local
    if [ ! -z "$SMB_SHARE_PATH" ]; then
        echo -e "${BLUE}Copying backup to SMB share...${NC}" >&2
        local smb_backup_dir="$TEMP_MOUNT/open-webui-backups"
        
        # Check/create SMB backup directory
        echo -e "${BLUE}Checking SMB backup directory: $smb_backup_dir${NC}" >&2
        if [ -d "$smb_backup_dir" ]; then
            echo -e "${GREEN}✓ SMB backup directory exists${NC}" >&2
        else
            echo -e "${BLUE}Creating SMB backup directory...${NC}" >&2
            if ! mkdir -p "$smb_backup_dir"; then
                echo -e "${RED}Failed to create SMB backup directory${NC}" >&2
                rm -f "$local_backup"
                exit 1
            fi
            echo -e "${GREEN}✓ SMB backup directory created${NC}" >&2
        fi
        
        # Copy to SMB
        echo -e "${BLUE}Copying to: $smb_backup_dir/$backup_name${NC}" >&2
        if ! cp "$local_backup" "$smb_backup_dir/$backup_name"; then
            echo -e "${RED}Error: Failed to copy backup to SMB share${NC}" >&2
            rm -f "$local_backup"
            exit 1
        fi
        
        # Verify SMB copy and set permissions
        echo -e "${BLUE}Verifying SMB backup...${NC}" >&2
        if [ ! -f "$smb_backup_dir/$backup_name" ]; then
            echo -e "${RED}Error: Backup verification failed on SMB share${NC}" >&2
            rm -f "$local_backup"
            exit 1
        fi
        
        # Set full permissions
        echo -e "${BLUE}Setting SMB backup permissions...${NC}" >&2
        if ! sudo chown $USER:$USER "$smb_backup_dir/$backup_name" && ! chmod 777 "$smb_backup_dir/$backup_name"; then
            echo -e "${RED}Warning: Failed to set backup file permissions${NC}" >&2
        fi
        echo -e "${GREEN}✓ SMB backup verified${NC}" >&2

        # Remove local copy
        echo -e "${BLUE}Removing local backup...${NC}" >&2
        rm -f "$local_backup"
        echo -e "${GREEN}✓ Local backup removed${NC}" >&2
        
        # Get size and date before unmounting
        local size=$(du -h "$smb_backup_dir/$backup_name" | cut -f1)
        local created=$(date -r "$smb_backup_dir/$backup_name" "+%Y-%m-%d %H:%M:%S")
        
        sync
        
        # Cleanup SMB mount
        echo -e "${BLUE}Cleaning up SMB mount...${NC}" >&2
        sudo umount "$TEMP_MOUNT"
        sudo rmdir "$TEMP_MOUNT"
        
        # Set final backup path for display
        backup_file="$SMB_SHARE_PATH/open-webui-backups/$backup_name"
    else
        # Get local backup size and date
        local size=$(du -h "$local_backup" | cut -f1)
        local created=$(date -r "$local_backup" "+%Y-%m-%d %H:%M:%S")
        backup_file="$local_backup"
    fi

    # Show completion message
    {
        echo -e "${GREEN}✅ Backup completed successfully!${NC}"
        if [ ! -z "$SMB_SHARE_PATH" ]; then
            echo -e "${GREEN}Location: $SMB_SHARE_PATH/open-webui-backups${NC}"
        else
            echo -e "${GREEN}Location: $LOCAL_BACKUP_BASE${NC}"
        fi
        echo -e "${GREEN}File: $backup_name${NC}"
        echo -e "${GREEN}Size: $size${NC}"
        echo -e "${GREEN}Created: $created${NC}"
    } >&2
}

# Function to restore from backup
restore_backup() {
    local backup_file="$1"
    local container_name="$2"
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}Error: Backup file not found: $backup_file${NC}"
        exit 1
    fi
    
    echo -e "${RED}WARNING: This will overwrite all existing Open WebUI data!${NC}"
    echo -e "${RED}Any changes made since the backup will be lost.${NC}"
    echo -e "${BLUE}Backup to restore: $backup_file${NC}"
    echo
    read -p "Are you sure you want to proceed with the restore? (yes/no): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo -e "${BLUE}Restore cancelled.${NC}"
        exit 0
    fi
    
    echo
    echo -e "${BLUE}Starting restore process...${NC}"
    
    # Stop the container if it's running
    if docker ps | grep -q "$container_name"; then
        echo -e "${BLUE}Stopping Open WebUI container...${NC}"
        docker stop "$container_name"
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
    if ! sudo tar xzf "$backup_file" -C "$volume_path"; then
        echo -e "${RED}Error: Restore failed${NC}"
        exit 1
    fi
    
    # Fix permissions
    sudo chown -R root:root "$volume_path"
    
    # Restart the container if it was running
    if docker ps -a | grep -q "$container_name"; then
        echo -e "${BLUE}Starting Open WebUI container...${NC}"
        # Wait a moment for the port to be fully released
        sleep 2
        if ! docker start "$container_name"; then
            echo -e "${RED}Failed to start container. Waiting longer for port to be released...${NC}"
            sleep 5
            if ! docker start "$container_name"; then
                echo -e "${RED}Still unable to start container. You may need to:${NC}"
                echo -e "${RED}1. Check if any process is using port 3000: sudo lsof -i :3000${NC}"
                echo -e "${RED}2. Stop the process if needed${NC}"
                echo -e "${RED}3. Then manually start the container: docker start $container_name${NC}"
                exit 1
            fi
        fi
    fi
    
    echo -e "${GREEN}✅ Restore completed successfully!${NC}"
    
    # Cleanup SMB mount if used
    if mountpoint -q "$TEMP_MOUNT"; then
        echo -e "${BLUE}Cleaning up SMB mount...${NC}"
        sudo umount "$TEMP_MOUNT"
        sudo rmdir "$TEMP_MOUNT"
    fi
}

# Function to list available backups
list_backups() {
    local backup_path="$1"
    local container_name="$2"
    local backups=()
    
    echo -e "${BLUE}Available backups:${NC}"
    
    # Find all backup files
    while IFS= read -r file; do
        if [[ "$file" =~ .*\.tar\.gz$ ]]; then
            backups+=("$file")
            echo -e "${BLUE}$((${#backups[@]}))) $(basename "$file")${NC}"
        fi
    done < <(find "$backup_path" -maxdepth 1 -type f -name "open-webui-backup-*.tar.gz" | sort -r)
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}No backups found in $backup_path${NC}"
        exit 1
    fi
    
    # Let user select a backup
    read -p "Select backup to restore (1-${#backups[@]}): " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#backups[@]}" ]; then
        local selected_backup="${backups[$((selection-1))]}"
        restore_backup "$selected_backup" "$container_name"
    else
        echo -e "${RED}Invalid selection${NC}"
        exit 1
    fi
}

# Function to validate SMB path
validate_smb_path() {
    local path="$1"
    if [[ ! "$path" =~ ^//[^/]+/[^/].* ]]; then
        echo -e "${RED}Error: Invalid SMB path format${NC}" >&2
        echo "Path must start with // followed by hostname/IP and share name" >&2
        echo "Example: //192.168.1.100/backups" >&2
        return 1
    fi
    return 0
}

# Function to test SMB write access
test_smb_access() {
    local smb_path="$1"
    local username="$2"
    local password="$3"
    local domain="$4"
    
    echo -e "${BLUE}Testing SMB share access...${NC}" >&2
    
    # Create mount point
    if ! sudo mkdir -p "$TEMP_MOUNT"; then
        echo -e "${RED}Error: Failed to create mount point${NC}" >&2
        return 1
    fi

    # Setup mount options with full permissions
    local mount_options="username=$username,password=$password,uid=$(id -u),gid=$(id -g),file_mode=0777,dir_mode=0777"
    [ ! -z "$domain" ] && mount_options="$mount_options,domain=$domain"

    # Mount the share
    if ! sudo mount -t cifs "$smb_path" "$TEMP_MOUNT" -o "$mount_options"; then
        echo -e "${RED}Error: Failed to mount SMB share${NC}" >&2
        sudo rmdir "$TEMP_MOUNT"
        return 1
    fi

    # Test write access with a test file
    echo -e "${BLUE}Testing write access to SMB share...${NC}" >&2
    local test_content="SMB write test - $(date)"
    
    # Try to write test file
    if ! echo "$test_content" > "$TEMP_MOUNT/test.txt"; then
        echo -e "${RED}Error: Cannot write test file to SMB share${NC}" >&2
        sudo umount "$TEMP_MOUNT"
        sudo rmdir "$TEMP_MOUNT"
        return 1
    fi
    
    # Verify test file exists and content matches
    if [ ! -f "$TEMP_MOUNT/test.txt" ]; then
        echo -e "${RED}Error: Test file not found - write verification failed${NC}" >&2
        sudo umount "$TEMP_MOUNT"
        sudo rmdir "$TEMP_MOUNT"
        return 1
    fi
    
    # Read back and verify content
    local read_content=$(cat "$TEMP_MOUNT/test.txt")
    if [ "$read_content" != "$test_content" ]; then
        echo -e "${RED}Error: Test file content verification failed${NC}" >&2
        rm -f "$TEMP_MOUNT/test.txt"
        sudo umount "$TEMP_MOUNT"
        sudo rmdir "$TEMP_MOUNT"
        return 1
    fi
    
    echo -e "${GREEN}✓ SMB write test successful${NC}" >&2
    
    # Clean up test file
    rm -f "$TEMP_MOUNT/test.txt"
    
    # Check/Create backup directory
    local backup_dir="$TEMP_MOUNT/open-webui-backups"
    echo -e "${BLUE}Checking backup directory: $backup_dir${NC}" >&2
    
    if [ -d "$backup_dir" ]; then
        echo -e "${GREEN}✓ Backup directory exists${NC}" >&2
    else
        echo -e "${BLUE}Creating backup directory...${NC}" >&2
        if ! mkdir -p "$backup_dir"; then
            echo -e "${RED}Error: Failed to create backup directory${NC}" >&2
            sudo umount "$TEMP_MOUNT"
            sudo rmdir "$TEMP_MOUNT"
            return 1
        fi
        echo -e "${GREEN}✓ Backup directory created${NC}" >&2
    fi

    # Return success and path (using printf to avoid newline issues)
    echo -e "${GREEN}SMB share access test successful${NC}" >&2
    printf "%s" "$TEMP_MOUNT/open-webui-backups"
    return 0
}

# Function to setup SMB mount
setup_smb_mount() {
    local smb_path="$1"
    # Get credentials
    read -p "SMB Username: " smb_username
    read -s -p "SMB Password: " smb_password
    echo
    read -p "SMB Domain (press Enter to skip): " smb_domain
    echo

    # Test SMB access and get mount path
    if ! test_smb_access "$smb_path" "$smb_username" "$smb_password" "$smb_domain"; then
        echo -e "${RED}SMB share access test failed${NC}" >&2
        exit 1
    fi
    
    # Return the backup directory path (using printf to avoid newline issues)
    printf "%s" "$TEMP_MOUNT/open-webui-backups"
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
    local container_name="$1"
    echo -e "${BLUE}Welcome to Open WebUI Backup Wizard!${NC}"
    
    # Check dependencies first
    check_dependencies
    
    # Operation selection
    while true; do
        echo -e "\nSelect operation:"
        echo "1) Create backup"
        echo "2) Restore from backup"
        read -p "Enter your choice (1-2): " operation_choice
        
        case $operation_choice in
            1)
                # Backup frequency
                while true; do
                    echo -e "\nSelect backup frequency:"
                    echo "1) One-time backup"
                    echo "2) Daily backup"
                    echo "3) Weekly backup"
                    echo "4) Monthly backup"
                    read -p "Enter your choice (1-4): " frequency_choice
                    
                    if [[ "$frequency_choice" =~ ^[1-4]$ ]]; then
                        break
                    fi
                    echo -e "${RED}Invalid choice. Please enter a number between 1 and 4.${NC}"
                done
                
                # Backup location
                while true; do
                    echo -e "\nSelect backup location:"
                    echo "1) Local directory"
                    echo "2) SMB share"
                    read -p "Enter your choice (1-2): " location_choice
                    
                    if [[ "$location_choice" =~ ^[1-2]$ ]]; then
                        break
                    fi
                    echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
                done
            
                # Setup backup path
                backup_path=""
                case $location_choice in
                    1)
                        backup_path="$LOCAL_BACKUP_BASE"
                        if ! [ -d "$backup_path" ]; then
                            echo -e "${BLUE}Creating local backup directory...${NC}"
                            if ! mkdir -p "$backup_path" 2>/dev/null; then
                                echo -e "${BLUE}Attempting with sudo...${NC}"
                                sudo mkdir -p "$backup_path"
                                sudo chown $USER:$USER "$backup_path"
                            fi
                            echo -e "${GREEN}✓ Local backup directory created${NC}"
                        fi
                        ;;
                    2)
                        # Get SMB path and mount it
                        read -p "SMB Share Path (//hostname/share): " SMB_SHARE_PATH
                        if ! validate_smb_path "$SMB_SHARE_PATH"; then
                            echo -e "${RED}Invalid SMB path${NC}"
                            exit 1
                        fi
                        export SMB_SHARE_PATH
                        
                        # Clean up any existing mount
                        if mountpoint -q "$TEMP_MOUNT"; then
                            sudo umount "$TEMP_MOUNT" || true
                        fi
                        sudo rm -rf "$TEMP_MOUNT"
                        
                        backup_path=$(setup_smb_mount "$SMB_SHARE_PATH")
                        ;;
                esac
            
                # Handle backup frequency
                case $frequency_choice in
                    1)
                        create_backup "$backup_path" "$container_name"
                        ;;
                    2)
                        setup_schedule "daily" "$backup_path"
                        create_backup "$backup_path" "$container_name" # Initial backup
                        ;;
                    3)
                        setup_schedule "weekly" "$backup_path"
                        create_backup "$backup_path" "$container_name" # Initial backup
                        ;;
                    4)
                        setup_schedule "monthly" "$backup_path"
                        create_backup "$backup_path" "$container_name" # Initial backup
                        ;;
                esac
                break
                ;;
            2)
                # Restore location
                while true; do
                    echo -e "\nSelect restore location:"
                    echo "1) Local directory"
                    echo "2) SMB share"
                    read -p "Enter your choice (1-2): " location_choice
                    
                    if [[ "$location_choice" =~ ^[1-2]$ ]]; then
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
                                read -p "SMB Share Path (//hostname/share): " SMB_SHARE_PATH
                                if ! validate_smb_path "$SMB_SHARE_PATH"; then
                                    echo -e "${RED}Invalid SMB path${NC}"
                                    exit 1
                                fi
                                export SMB_SHARE_PATH
                                
                                # Clean up any existing mount
                                if mountpoint -q "$TEMP_MOUNT"; then
                                    sudo umount "$TEMP_MOUNT" || true
                                fi
                                sudo rm -rf "$TEMP_MOUNT"
                                
                                restore_path=$(setup_smb_mount "$SMB_SHARE_PATH")
                                ;;
                        esac
                        break
                    fi
                    echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
                done
                
                list_backups "$restore_path" "$container_name"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
                ;;
        esac
    done
}

# Main execution
if [ "$1" == "--auto-backup" ]; then
    # Running in automatic mode (from cron)
    backup_path="$2"
    container_name=$(find_container)
    create_backup "$backup_path" "$container_name"
else
    # Interactive wizard mode
    printf "${BLUE}Checking Docker...${NC}\n"
    check_docker
    
    printf "\n${BLUE}Detecting Open WebUI containers...${NC}\n\n"
    printf "Current containers:\n"
    docker ps -a
    printf "\n"
    
    # Get matching containers
    matching_containers=$(docker ps -a --format '{{.Names}}' | grep -iE 'open-webui' || true)
    
    if [ -z "$matching_containers" ]; then
        printf "${RED}Error: No Open WebUI containers found${NC}\n"
        exit 1
    fi
    
    # Show container details
    printf "${BLUE}Found Open WebUI container:${NC}\n"
    container_name=$(echo "$matching_containers" | head -n1)
    printf "Name:   %s\n" "$container_name"
    printf "Status: %s\n" "$(docker ps -a --filter "name=$container_name" --format '{{.Status}}')"
    printf "Image:  %s\n" "$(docker ps -a --filter "name=$container_name" --format '{{.Image}}')"
    printf "Ports:  %s\n" "$(docker ps -a --filter "name=$container_name" --format '{{.Ports}}')"
    printf "\n"
    
    read -p "Use this container? (yes/no): " confirm
    if [[ ! "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        printf "${RED}Operation cancelled${NC}\n"
        exit 1
    fi
    
    printf "${GREEN}Using container: $container_name${NC}\n\n"
    
    # Now start the wizard with the confirmed container
    backup_wizard "$container_name"
fi
