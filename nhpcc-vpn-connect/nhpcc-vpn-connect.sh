#!/bin/bash
set -euo pipefail  # Strict error handling

# Configuration
VERSION="1.0"
DEFAULT_CONNECTION="my-hpc"
SCRIPT_NAME=$(basename "$0")
BACKUP_DIR="$HOME/.hpc-network-backups"
ORIGINAL_RESOLV="$BACKUP_DIR/resolv.conf.original"
CONNECTION_INFO="$BACKUP_DIR/connection.info"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Global variables
CONNECTION_NAME="$DEFAULT_CONNECTION"
DRY_RUN=false
DISCONNECT_MODE=false
VERBOSE=false

# Display usage
usage() {
    echo -e "${GREEN}HPC Network Configuration Script${NC}"
    echo "Version: $VERSION"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo "Configure HPC network routing and DNS for specialized access"
    echo ""
    echo "Options:"
    echo "  -c, --connection NAME    Use different connection name (default: my-hpc)"
    echo "  -d, --dry-run            Show what would be done without making changes"
    echo "  -x, --disconnect         Disconnect and restore original DNS"
    echo "  -v, --verbose            Show detailed output"
    echo "  -h, --help               Show this help"
    echo "  --version                Show version"
    echo ""
    echo "Examples:"
    echo "  $0                          # Connect with default settings"
    echo "  $0 -c vpn-hpc               # Use connection named 'vpn-hpc'"
    echo "  $0 -d                       # Dry run"
    echo "  $0 -x -c vpn-hpc            # Disconnect specific connection"
    echo "  $0 -x                       # Disconnect last used connection"
    echo ""
}

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--connection)
                if [[ -z "${2:-}" ]]; then
                    echo -e "${RED}❌ Option $1 requires an argument${NC}"
                    usage
                    exit 1
                fi
                CONNECTION_NAME="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -x|--disconnect)
                DISCONNECT_MODE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --version)
                echo "HPC Network Configuration Script v$VERSION"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Unknown option: $1${NC}"
                usage
                exit 1
                ;;
        esac
    done
}

# Save connection info for later disconnect
save_connection_info() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would save connection info: $CONNECTION_NAME"
        return 0
    fi
    
    mkdir -p "$BACKUP_DIR"
    echo "CONNECTION_NAME=$CONNECTION_NAME" > "$CONNECTION_INFO"
    echo "TIMESTAMP=$(date)" >> "$CONNECTION_INFO"
}

# Load connection info for disconnect
load_connection_info() {
    if [[ -f "$CONNECTION_INFO" ]]; then
        # Extract the connection name from the info file
        local saved_name=$(grep "^CONNECTION_NAME=" "$CONNECTION_INFO" | cut -d= -f2)
        if [[ -n "$saved_name" ]]; then
            CONNECTION_NAME="$saved_name"
            return 0
        fi
    fi
    return 1
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  Warning: Running as root directly${NC}"
        echo -e "${YELLOW}Consider running with sudo instead of as root user${NC}"
    elif ! sudo -n true 2>/dev/null && [[ "$DRY_RUN" == false ]]; then
        echo -e "${YELLOW}🔐 This script requires sudo privileges${NC}"
        if [[ "$DRY_RUN" == false ]]; then
            sudo -v
        fi
    fi
}

# Always backup current DNS configuration
backup_dns() {
    echo -e "${GREEN}📂 Backing up current DNS configuration...${NC}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would backup /etc/resolv.conf to $ORIGINAL_RESOLV"
        return 0
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Always backup current resolv.conf (overwrites previous backup)
    if [[ -f /etc/resolv.conf ]]; then
        sudo cp /etc/resolv.conf "$ORIGINAL_RESOLV"
        sudo chown "$USER:$USER" "$ORIGINAL_RESOLV"
        echo "✅ Backed up current /etc/resolv.conf"
    else
        echo -e "${RED}❌ /etc/resolv.conf not found${NC}"
        return 1
    fi
}

# Restore original DNS configuration
restore_dns() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${GREEN}🔄 Restoring DNS configuration from backup...${NC}"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would restore /etc/resolv.conf from $ORIGINAL_RESOLV"
        return 0
    fi
    
    if [[ ! -f "$ORIGINAL_RESOLV" ]]; then
        echo -e "${RED}❌ No backup found at $ORIGINAL_RESOLV${NC}"
        echo "Cannot restore DNS configuration"
        return 1
    fi
    
    sudo cp "$ORIGINAL_RESOLV" /etc/resolv.conf
    sudo chmod 644 /etc/resolv.conf
    if [[ "$VERBOSE" == true ]]; then
        echo "✅ Successfully restored DNS configuration"
    fi

    # Show DNS info in verbose mode
    if [[ "$VERBOSE" == true ]]; then
        echo -e "\n${YELLOW}DNS configuration details:${NC}"
        echo "Content of /etc/resolv.conf:"
        cat /etc/resolv.conf
    fi
    
    return 0
}

# Disconnect and restore DNS
disconnect() {
    echo -e "${GREEN}🔌 Disconnecting and restoring DNS...${NC}"
    
    # If no specific connection name was provided, try to load the saved one
    if [[ "$CONNECTION_NAME" == "$DEFAULT_CONNECTION" ]]; then
        if load_connection_info; then
            echo "ℹ️  Using saved connection name: $CONNECTION_NAME"
        else
            echo -e "${YELLOW}⚠️  No saved connection found, using default: $CONNECTION_NAME${NC}"
            echo "Tip: Use -c option to specify which connection to disconnect"
        fi
    fi
    
    # 1. Restore DNS from backup
    if ! restore_dns; then
        echo -e "${YELLOW}⚠️  Could not restore DNS, but continuing...${NC}"
    fi
    
    # 2. Disconnect the network connection
    echo -e "\n${GREEN}🔗 Disconnecting '$CONNECTION_NAME'...${NC}"
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would run: nmcli connection down '$CONNECTION_NAME'"
    else
        # Check if connection exists
        if ! nmcli connection show "$CONNECTION_NAME" &>/dev/null; then
            echo -e "${RED}❌ Connection '$CONNECTION_NAME' not found${NC}"
            echo -e "${YELLOW}Available connections:${NC}"
            nmcli connection show | head -10
            return 1
        fi
        
        # Check if connection is active
        if nmcli connection show --active | grep -q "$CONNECTION_NAME"; then
            nmcli connection down "$CONNECTION_NAME"
            echo "✅ Disconnected '$CONNECTION_NAME'"
            
            # Note: The route will be automatically removed when the connection goes down
            if [[ "$VERBOSE" == true ]]; then
                echo "ℹ️  Custom route will be automatically removed with the connection"
            fi
        else
            echo "ℹ️  '$CONNECTION_NAME' is not currently active"
        fi
    fi
    
    # Clean up connection info file
    if [[ -f "$CONNECTION_INFO" ]]; then
        rm -f "$CONNECTION_INFO"
    fi
    
    echo -e "\n${GREEN}🎉 Disconnect completed!${NC}"
    if [[ "$VERBOSE" == true ]]; then
        echo "DNS has been restored to original state"
    fi
}

# Check if connection exists
check_connection() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would check if connection '$CONNECTION_NAME' exists"
        return 0
    fi
    
    if ! nmcli connection show "$CONNECTION_NAME" &>/dev/null; then
        echo -e "${RED}❌ Connection '$CONNECTION_NAME' not found${NC}"
        echo -e "${YELLOW}Available connections:${NC}"
        nmcli connection show | head -10
        return 1
    fi
    return 0
}

# Wait for connection to become active
wait_for_connection() {
    local max_attempts=10
    local attempt=1
    
    echo -e "${YELLOW}⏳ Waiting for connection to become active...${NC}"
    
    while [[ $attempt -le $max_attempts ]]; do
        if nmcli connection show --active | grep -q "$CONNECTION_NAME"; then
            echo "✅ Connection is active after $attempt second(s)"
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            echo -e "${YELLOW}⚠️  Connection not active after $max_attempts seconds, continuing anyway${NC}"
            return 1
        fi
        
        sleep 1
        ((attempt++))
    done
}

# Activate the connection
activate_connection() {
    echo -e "${GREEN}🔗 Activating '$CONNECTION_NAME' connection...${NC}"
    
    if ! check_connection; then
        exit 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would run: nmcli connection up '$CONNECTION_NAME'"
        return 0
    fi
    
    # Try to activate the connection
    if nmcli connection up "$CONNECTION_NAME"; then
        echo "Connection activation command succeeded"
        
        # Wait for connection to become active
        if wait_for_connection; then
            echo "✅ Connection activated and verified"
        else
            echo -e "${YELLOW}⚠️  Connection activated but not verified as active${NC}"
        fi
        return 0
    else
        echo -e "${RED}❌ Failed to activate connection${NC}"
        
        # Check if it's already active
        if nmcli connection show --active | grep -q "$CONNECTION_NAME"; then
            echo "ℹ️  Connection is already active"
            return 0
        fi
        
        return 1
    fi
}

# Configure routing
configure_routing() {
    local tun_gateway="10.3.201.1"
    local tun_interface="tun0"
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${GREEN}🛣️  Configuring routing...${NC}"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would configure routing:"
        echo "  - Check if $tun_interface exists"
        echo "  - Remove existing default route via $tun_gateway"
        echo "  - Add default route via $tun_gateway dev $tun_interface metric 25000"
        return 0
    fi
    
    # Check if tun0 exists
    if ! ip link show "$tun_interface" &>/dev/null; then
        echo -e "${YELLOW}⚠️  Interface $tun_interface not found, checking in 5 seconds...${NC}"
        sleep 5
        
        if ! ip link show "$tun_interface" &>/dev/null; then
            echo -e "${RED}❌ Interface $tun_interface still not found after waiting${NC}"
            return 1
        fi
    fi
    
    # Show current routing table in verbose mode
    if [[ "$VERBOSE" == true ]]; then
        echo -e "\n${YELLOW}Current routing table:${NC}"
        ip route | grep -E "^default|^10\." || echo "No relevant routes found"
        echo ""
    fi
    
    # Remove existing default route via tun0 if exists
    if ip route | grep -q "default via $tun_gateway dev $tun_interface"; then
        if [[ "$VERBOSE" == true ]]; then
            echo "Removing existing default route via $tun_interface..."
        fi
        sudo ip route del default via "$tun_gateway" dev "$tun_interface" || true
    fi
    
    # Add new route with high metric
    if [[ "$VERBOSE" == true ]]; then
        echo "Adding default route via $tun_interface with metric 25000..."
    fi
    sudo ip route add default via "$tun_gateway" dev "$tun_interface" metric 25000
    
    # Verify the route was added
    if ip route | grep -q "default via $tun_gateway dev $tun_interface metric 25000"; then
        if [[ "$VERBOSE" == true ]]; then
            echo "✅ Route configured successfully"
        fi
        
        # Show new routing table in verbose mode
        if [[ "$VERBOSE" == true ]]; then
            echo -e "\n${YELLOW}Updated routing table:${NC}"
            ip route | grep -E "^default|^10\." || echo "No relevant routes found"
            echo -e "\n${YELLOW}Route details:${NC}"
            ip route | grep "default via $tun_gateway dev $tun_interface"
        fi
        return 0
    else
        echo -e "${RED}❌ Failed to configure route${NC}"
        return 1
    fi
}

# Configure DNS
configure_dns() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${GREEN}🔧 Configuring DNS servers...${NC}"
    fi
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would configure DNS with servers:"
        if [[ "$VERBOSE" == true ]]; then
            echo "  1. 10.3.0.1    # HPC Internal DNS"
            echo "  2. 8.8.8.8     # Google DNS (Primary)"
            echo "  3. 8.8.4.4     # Google DNS (Secondary)"
        fi
        return 0
    fi
    
    # Create temporary file
    local temp_resolv=$(mktemp)
    
    cat > "$temp_resolv" << EOF
# Generated by $SCRIPT_NAME on $(date)
# Connection: $CONNECTION_NAME

nameserver 10.3.0.1    # HPC Internal DNS
nameserver 8.8.8.8     # Google DNS (Primary)
nameserver 8.8.4.4     # Google DNS (Secondary)

# Search domains if needed (uncomment and modify)
# search hpc.internal example.com
EOF
    
    # Copy to /etc/resolv.conf
    sudo cp "$temp_resolv" /etc/resolv.conf
    sudo chmod 644 /etc/resolv.conf
    
    # Clean up
    rm -f "$temp_resolv"
    if [[ "$VERBOSE" == true ]]; then
        echo "✅ DNS configured with:"
        echo "  1. 10.3.0.1 (HPC)"
        echo "  2. 8.8.8.8 (Google)"
        echo "  3. 8.8.4.4 (Google)"
    fi
    
    # Show DNS details in verbose mode
    if [[ "$VERBOSE" == true ]]; then
        echo -e "\n${YELLOW}DNS configuration details:${NC}"
        echo "Content of /etc/resolv.conf:"
        cat /etc/resolv.conf
    fi
}

# Verify configuration
verify_configuration() {
    echo -e "${GREEN}🔍 Verifying configuration...${NC}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would verify:"
        echo "  - Route via tun0 with metric 25000 exists"
        echo "  - DNS contains 10.3.0.1"
        echo "  - Connection '$CONNECTION_NAME' is active"
        return 0
    fi
    
    local errors=0
    
    # Check route
    if ! ip route | grep -q "default.*tun0.*metric 25000"; then
        echo -e "${RED}❌ Route verification failed${NC}"
        ((errors++))
    fi
    
    # Check DNS
    if ! sudo grep -q "nameserver 10.3.0.1" /etc/resolv.conf; then
        echo -e "${RED}❌ DNS verification failed${NC}"
        ((errors++))
    fi
    
    # Check connection
    if ! nmcli connection show --active | grep -q "$CONNECTION_NAME"; then
        echo -e "${RED}❌ Connection not active${NC}"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        echo "✅ All configurations verified successfully"
        return 0
    else
        echo -e "${YELLOW}⚠️  Found $errors issue(s) - please review${NC}"
        return 1
    fi
}

# Connect function
connect() {
    check_root
    
    # Save connection info for future disconnect
    save_connection_info
    
    # Always backup DNS before making changes
    if ! backup_dns; then
        echo -e "${YELLOW}⚠️  Continuing despite backup issues...${NC}"
    fi
    
    if ! activate_connection; then
        echo -e "${YELLOW}⚠️  Continuing despite connection issues...${NC}"
    fi
    
    sleep 2  # Give connection time to establish
    
    configure_routing
    configure_dns
    
    if verify_configuration; then
        echo -e "\n${GREEN}🎉 HPC network configuration completed successfully!${NC}"
    else
        echo -e "\n${YELLOW}⚠️  Configuration completed with warnings${NC}"
    fi
    
    # Show final status
    if [[ "$DRY_RUN" == false ]]; then
        if [[ "$VERBOSE" == true ]]; then
            echo ""
            echo -e "${GREEN}📊 Final Status:${NC}"
            echo "Active connection:"
            nmcli connection show --active | grep -A2 -B2 "$CONNECTION_NAME" || true
            echo ""
            echo "Default route:"
            ip route | grep "^default" || true
            echo ""
            echo "DNS servers:"
            sudo grep "^nameserver" /etc/resolv.conf || sudo cat /etc/resolv.conf
            echo ""
            echo -e "${YELLOW}Note: Original DNS backed up to $ORIGINAL_RESOLV${NC}"
            echo "Connection info saved for disconnect"
            echo "Use '$0 -x' to disconnect and restore DNS"
            echo "Or use '$0 -x -c $CONNECTION_NAME' to specify connection"
        fi
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${GREEN}🚀 HPC Network Configuration Script${NC}"
        echo "Version: $VERSION"
        echo "Timestamp: $(date)"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}⚠️  DRY RUN MODE - No changes will be made${NC}"
    fi
    
    if [[ "$DISCONNECT_MODE" == true ]]; then
        disconnect
        exit $?
    fi
    
    connect
}

# Run main function with all arguments
main "$@"
