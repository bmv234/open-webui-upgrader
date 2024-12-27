# Open WebUI Management Scripts

This repository contains scripts for managing Open WebUI installations, including updates and backups.

## Scripts Overview

### 1. Standard Update Script (`update-open-webui.sh`)
Updates Open WebUI when Ollama is running in a container or when using standard Docker networking.

- Updates to latest Open WebUI version
- Preserves user data
- Handles GPU support automatically
- Creates automatic backups before updating
- Uses Docker's internal networking (host.docker.internal)
- Suitable for container-to-container communication

Usage:
```bash
./update-open-webui.sh
```

### 2. Host Network Update Script (`update-open-webui-ollama-host-network.sh`)
Updates Open WebUI when Ollama is running directly on the host machine.

- Same features as standard update script
- Uses host network mode
- Connects directly to Ollama on localhost
- Suitable when Ollama runs on the host machine

Usage:
```bash
./update-open-webui-ollama-host-network.sh
```

### 3. Backup & Restore Script (`backup-restore-open-webui.sh`)
Provides flexible backup and restore options for Open WebUI data.

Features:
- Wizard-style interface
- Backup operations:
  - Create new backups
  - Restore from existing backups
- Multiple backup frequencies:
  - One-time backup
  - Weekly backups (Sundays at midnight)
  - Monthly backups (1st of each month)
- Storage location options:
  - Local directory
  - SMB network share
- Secure credential handling
- Automatic dependency installation

Usage:
```bash
./backup-restore-open-webui.sh
```

## Requirements

- Docker
- Linux-based system (Ubuntu/Debian recommended)
- For SMB backups:
  - cifs-utils (automatically installed if needed)
  - Network access to SMB share
- For scheduled backups:
  - cron (automatically installed if needed)

## Backup Configuration

### Local Backups
- Stored in: `$HOME/open-webui-backups`
- Organized by timestamp
- Automatic directory creation

### SMB Share Backups
- Supports both workgroup and domain environments
- Required information:
  - Share path (format: //hostname_or_ip/share_name)
  - Username
  - Password
  - Domain (optional)
- Credentials stored securely
- Persistent mount configuration

## Common Operations

### Updating Open WebUI
Choose the appropriate update script based on your Ollama setup:
- If Ollama is in a container: Use `update-open-webui.sh`
- If Ollama is on host: Use `update-open-webui-ollama-host-network.sh`

### Using the Backup & Restore Wizard

The script provides an interactive wizard interface for both backup and restore operations.

#### Creating Backups

1. Run the backup & restore script:
   ```bash
   ./backup-restore-open-webui.sh
   ```

2. Select "Create backup" from the wizard menu

3. Choose backup frequency:
   - One-time backup: Creates a single backup immediately
   - Weekly backup: Schedules backups every Sunday at midnight
   - Monthly backup: Schedules backups on the 1st of each month

4. Select backup location:
   - Local directory: Stores backups in $HOME/open-webui-backups
   - SMB share: Stores backups on a network share

5. If SMB share selected:
   - Enter share path (format: //hostname_or_ip/share_name)
   - Provide username and password
   - Optionally enter domain name
   - Credentials are stored securely

6. For scheduled backups:
   - Creates initial backup immediately
   - Sets up cron job for future backups
   - Verifies cron setup

#### Restoring from Backup

1. Run the backup & restore script:
   ```bash
   ./backup-restore-open-webui.sh
   ```

2. Select "Restore from backup" from the wizard menu

3. Choose backup location:
   - Local directory: Lists backups from $HOME/open-webui-backups
   - SMB share: Lists backups from configured network share

4. If SMB share selected:
   - Enter share details (same as backup process)
   - System will mount the share and list available backups

5. Select backup to restore:
   - Backups are listed chronologically
   - Each backup shows its creation timestamp
   - Most recent backup appears first

6. Review and confirm:
   - Warning displayed about data overwrite
   - Shows selected backup details
   - Requires typing 'yes' to proceed
   - Easy cancellation available

Important Notes:
- The restore process will overwrite all existing Open WebUI data
- Any changes made since the selected backup will be lost
- Container is automatically stopped during restore
- Data is safely restored from backup
- Container is restarted after restore completes
- Make sure to carefully review the backup date before confirming

### Checking Backup Status
- Local backups: Check `$HOME/open-webui-backups`
- SMB backups: Check mounted location at `/mnt/open-webui-backup`
- Cron jobs: `crontab -l`

## Error Handling

All scripts include:
- Comprehensive error checking
- Dependency verification
- Backup creation before risky operations
- Clear error messages
- Validation of inputs and configurations

## Security Features

- Secure credential storage for SMB
- Proper file permissions
- Safe handling of sensitive information
- Backup creation before updates
- Data persistence across updates

## Best Practices

1. Always run update scripts when Ollama is running
2. Ensure sufficient disk space for backups
3. Test SMB connectivity before setting up automated backups
4. Keep scripts up to date with the latest versions
5. Monitor backup logs periodically
6. Verify backup integrity regularly

## Troubleshooting

### Common Issues

1. Docker not running:
   - Check Docker service: `systemctl status docker`
   - Ensure user has Docker permissions

2. SMB Connection Issues:
   - Verify network connectivity
   - Check credentials
   - Ensure share permissions
   - Verify correct share path format

3. Backup Failures:
   - Check available disk space
   - Verify write permissions
   - Check network connectivity for SMB
   - Review cron logs for scheduled backups

### Getting Help

If you encounter issues:
1. Check the script output for error messages
2. Verify all requirements are met
3. Check system logs for more details
4. Ensure all dependencies are installed
