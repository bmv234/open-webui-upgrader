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

### 3. Backup Script (`backup-open-webui.sh`)
Provides flexible backup options for Open WebUI data.

Features:
- Wizard-style interface
- Multiple backup frequencies:
  - One-time backup
  - Weekly backups (Sundays at midnight)
  - Monthly backups (1st of each month)
- Backup location options:
  - Local directory
  - SMB network share
- Secure credential handling
- Automatic dependency installation

Usage:
```bash
./backup-open-webui.sh
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

### Setting Up Automated Backups
1. Run the backup script:
   ```bash
   ./backup-open-webui.sh
   ```
2. Follow the wizard prompts:
   - Choose backup frequency
   - Select backup location
   - Provide necessary credentials (for SMB)

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
