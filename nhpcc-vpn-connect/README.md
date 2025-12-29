# NHPCC Network Configuration Script

## Overview

This script automates the process of connecting to NHPCC VPN network while maintaining proper network segregation and easy restoration.

## Features

- **Automated Connection Management**: Activate and configure NHPCC VPN network connection
- **DNS Configuration**: Backup original DNS and configure NHPCC-specific DNS server
- **Routing Management**: Set up custom routes with appropriate metrics
- **Safe Disconnect**: Restore original network settings when disconnecting
- **Dry Run Mode**: Preview changes without applying them
- **Connection Persistence**: Remember which connection was used for easy disconnection
- **Verbose Output**: Detailed logging for troubleshooting
- **Root Privilege Management**: Proper handling of sudo privileges

## Prerequisites

- **NetworkManager**: Requires `nmcli` for connection management which should be available in most modern Gnu/Linux distros.
- **sudo privileges**: Required for system-level network configuration changes
- **Bash**: Version 4.0 or higher recommended

## Installation

1. Download the script:
   ```bash
   curl -O https://raw.githubusercontent.com/iut-nhpcc/user-tools/refs/heads/main/nhpcc-vpn-connect.sh
   chmod +x nhpcc-vpn-connect.sh

## Usage

### Basic Connection
```bash
./nhpcc-vpn-connect.sh
```
Connects using the default connection name my-hpc.

### Specify Connection Name
```bash
./nhpcc-vpn-connect.sh -c vpn-hpc
```
Use a specific NetworkManager connection.

### Dry Run (Preview Changes)
```bash
./nhpcc-vpn-connect.sh -d
```
Show what would be done without making actual changes.

### Disconnect
```bash
./nhpcc-vpn-connect.sh -x
```
Disconnect and restore original DNS settings.

### Verbose Mode
```bash
./nhpcc-vpn-connect.sh -v
```
Show detailed output of all operations.

### Help and Version
```bash
./nhpcc-vpn-connect.sh -h
./nhpcc-vpn-connect.sh --version
```

## Command Line Options

| Option | Short | Description |
|--------|-------|-------------|
| `--connection` | `-c` | Use different connection name (default: my-hpc) |
| `--dry-run` | `-d` | Show what would be done without making changes |
| `--disconnect` | `-x` | Disconnect and restore original DNS |
| `--verbose` | `-v` | Show detailed output |
| `--help` | `-h` | Show help message |
| `--version` | | Show version information |

## What the Script Does

### When Connecting:
1. **Backup Current DNS**: Saves `/etc/resolv.conf` to `~/.hpc-network-backups/`
2. **Activate Connection**: Uses NetworkManager to activate the specified connection
3. **Configure Routing**: Sets up a default route via tun0 with high metric (25000)
4. **Configure DNS**: Updates DNS servers to include HPC internal DNS and Google DNS
5. **Verify Configuration**: Checks that all changes were applied correctly

### When Disconnecting:
1. **Restore DNS**: Restores the original `/etc/resolv.conf` from backup
2. **Deactivate Connection**: Brings down the NetworkManager connection
3. **Clean Up**: Removes saved connection information

## Network Configuration Details

### DNS Configuration
The script configures the following DNS servers:
- `10.3.0.1` - HPC Internal DNS
- `8.8.8.8` - Google DNS (Primary)
- `8.8.4.4` - Google DNS (Secondary)

### Routing Configuration
- Interface: `tun0`
- Gateway: `10.3.201.1`
- Metric: `25000` (ensures this is not the primary route)

## Examples

### Connect to specific HPC connection:
```bash
./nhpcc-vpn-connect.sh -c hpc-vpn -v
```

### Preview connection changes:
```bash
./nhpcc-vpn-connect.sh -c hpc-vpn -d -v
```

### Disconnect from last used connection:
```bash
./nhpcc-vpn-connect.sh -x
```

### Disconnect specific connection:
```bash
sudo ./nhpcc-vpn-connect.sh -x -c hpc-vpn
```

## Version History

### v1.0
- Initial release
- Basic connect/disconnect functionality
- DNS backup and restore
- Routing configuration
- Dry run and verbose modes

## Security Notes

- This script modifies system network configuration
- Always review the script before running with sudo
- The backup directory contains sensitive network information
- Use dry-run mode (-d) to understand what changes will be made
- Only use with trusted network connections
