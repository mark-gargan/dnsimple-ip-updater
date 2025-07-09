#!/bin/bash

# DNSimple DNS Simple Updater - Shell Script Version
# A lightweight shell script to update a single DNS record with current IP
# Requires: curl, jq (for JSON parsing)

set -e

# Configuration - Edit these variables or set as environment variables
DNSIMPLE_TOKEN="${DNSIMPLE_TOKEN:-}"
DNSIMPLE_ACCOUNT_ID="${DNSIMPLE_ACCOUNT_ID:-}"
DNSIMPLE_SANDBOX="${DNSIMPLE_SANDBOX:-false}"
HOSTNAME="${HOSTNAME:-}"
RECORD_ID="${RECORD_ID:-}"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/dns-update.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO - $1"
}

log_error() {
    log "ERROR - $1" >&2
}

log_warning() {
    log "WARNING - $1"
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_error "Please install: apt-get install curl jq  # or  brew install curl jq"
        exit 1
    fi
}

# Load configuration from .env file if it exists
load_env_config() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        log_info "Loading configuration from .env file"
        # Source the .env file, but only export the variables we need
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^[[:space:]]*# ]] && continue
            [[ -z $key ]] && continue
            
            # Remove quotes and whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
            
            case "$key" in
                DNSIMPLE_TOKEN)
                    DNSIMPLE_TOKEN="$value"
                    ;;
                DNSIMPLE_ACCOUNT_ID)
                    DNSIMPLE_ACCOUNT_ID="$value"
                    ;;
                DNSIMPLE_SANDBOX)
                    DNSIMPLE_SANDBOX="$value"
                    ;;
                HOSTNAME)
                    HOSTNAME="$value"
                    ;;
                RECORD_ID)
                    RECORD_ID="$value"
                    ;;
            esac
        done < "$SCRIPT_DIR/.env"
    fi
}

# Validate configuration
validate_config() {
    local errors=()
    
    if [ -z "$DNSIMPLE_TOKEN" ]; then
        errors+=("DNSIMPLE_TOKEN is required")
    fi
    
    if [ -z "$HOSTNAME" ]; then
        errors+=("HOSTNAME is required")
    fi
    
    if [ ${#errors[@]} -gt 0 ]; then
        log_error "Configuration errors:"
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        exit 1
    fi
}

# Determine API base URL
get_api_base_url() {
    if [ "$DNSIMPLE_SANDBOX" = "true" ]; then
        echo "https://api.sandbox.dnsimple.com/v2"
    else
        echo "https://api.dnsimple.com/v2"
    fi
}

# Get account ID if not provided
get_account_id() {
    if [ -n "$DNSIMPLE_ACCOUNT_ID" ]; then
        echo "$DNSIMPLE_ACCOUNT_ID"
        return
    fi
    
    log_info "Auto-detecting account ID"
    local api_base_url=$(get_api_base_url)
    
    local response=$(curl -s -w "%{http_code}" \
        -H "Authorization: Bearer $DNSIMPLE_TOKEN" \
        -H "Accept: application/json" \
        "$api_base_url/whoami")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "200" ]; then
        log_error "Failed to get account ID. HTTP code: $http_code"
        log_error "Response: $body"
        exit 1
    fi
    
    local account_id=$(echo "$body" | jq -r '.data.account.id')
    
    if [ "$account_id" = "null" ] || [ -z "$account_id" ]; then
        log_error "Could not extract account ID from response"
        exit 1
    fi
    
    log_info "Detected account ID: $account_id"
    echo "$account_id"
}

# Get current IP address
get_current_ip() {
    local ip
    
    # Try multiple IP detection services
    for service in "http://icanhazip.com" "http://ipecho.net/plain" "http://checkip.amazonaws.com"; do
        ip=$(curl -s --connect-timeout 10 "$service" 2>/dev/null | tr -d '\n\r')
        
        # Validate IP format
        if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            log_info "Current IP: $ip (from $service)"
            echo "$ip"
            return
        fi
    done
    
    log_error "Could not determine current IP address"
    exit 1
}

# Parse hostname to get zone and record name
parse_hostname() {
    local hostname="$1"
    
    # Split hostname into parts
    IFS='.' read -ra parts <<< "$hostname"
    
    if [ ${#parts[@]} -lt 2 ]; then
        log_error "Invalid hostname format: $hostname"
        exit 1
    fi
    
    # Extract zone name (last two parts for basic domains)
    local zone_name="${parts[-2]}.${parts[-1]}"
    
    # Extract record name (everything before the zone)
    local record_name=""
    if [ ${#parts[@]} -gt 2 ]; then
        record_name=$(IFS='.'; echo "${parts[*]:0:${#parts[@]}-2}")
    fi
    
    # Log wildcard record handling
    if [ "$record_name" = "*" ]; then
        log_info "Processing wildcard record for zone $zone_name"
    elif [[ "$record_name" == \** ]]; then
        log_info "Processing wildcard record: $record_name for zone $zone_name"
    fi
    
    echo "$zone_name|$record_name"
}

# Get existing DNS record
get_existing_record() {
    local account_id="$1"
    local zone_name="$2"
    local record_name="$3"
    local api_base_url=$(get_api_base_url)
    
    log_info "Getting existing DNS records for zone: $zone_name"
    
    local response=$(curl -s -w "%{http_code}" \
        -H "Authorization: Bearer $DNSIMPLE_TOKEN" \
        -H "Accept: application/json" \
        "$api_base_url/$account_id/zones/$zone_name/records")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "200" ]; then
        log_error "Failed to get DNS records. HTTP code: $http_code"
        log_error "Response: $body"
        exit 1
    fi
    
    # Find A record matching the record name
    local record_id=$(echo "$body" | jq -r --arg name "$record_name" '.data[] | select(.type == "A" and .name == $name) | .id')
    
    if [ "$record_id" = "null" ] || [ -z "$record_id" ]; then
        log_info "No existing A record found for $record_name"
        echo ""
    else
        log_info "Found existing A record ID: $record_id"
        echo "$record_id"
    fi
}

# Create DNS record
create_dns_record() {
    local account_id="$1"
    local zone_name="$2"
    local record_name="$3"
    local ip="$4"
    local api_base_url=$(get_api_base_url)
    
    log_info "Creating DNS record: $record_name.$zone_name -> $ip"
    
    local json_data=$(jq -n \
        --arg name "$record_name" \
        --arg type "A" \
        --arg content "$ip" \
        --argjson ttl 300 \
        '{name: $name, type: $type, content: $content, ttl: $ttl}')
    
    local response=$(curl -s -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $DNSIMPLE_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$json_data" \
        "$api_base_url/$account_id/zones/$zone_name/records")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" = "201" ]; then
        log_info "Successfully created DNS record"
        return 0
    else
        log_error "Failed to create DNS record. HTTP code: $http_code"
        log_error "Response: $body"
        return 1
    fi
}

# Update DNS record
update_dns_record() {
    local account_id="$1"
    local zone_name="$2"
    local record_id="$3"
    local ip="$4"
    local api_base_url=$(get_api_base_url)
    
    log_info "Updating DNS record ID $record_id -> $ip"
    
    local json_data=$(jq -n \
        --arg content "$ip" \
        --argjson ttl 300 \
        '{content: $content, ttl: $ttl}')
    
    local response=$(curl -s -w "%{http_code}" \
        -X PATCH \
        -H "Authorization: Bearer $DNSIMPLE_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$json_data" \
        "$api_base_url/$account_id/zones/$zone_name/records/$record_id")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" = "200" ]; then
        log_info "Successfully updated DNS record"
        return 0
    else
        log_error "Failed to update DNS record. HTTP code: $http_code"
        log_error "Response: $body"
        return 1
    fi
}

# Main function
main() {
    log_info "Starting DNSimple DNS Simple Updater"
    
    # Check dependencies
    check_dependencies
    
    # Load configuration
    load_env_config
    
    # Validate configuration
    validate_config
    
    # Get account ID
    local account_id=$(get_account_id)
    
    # Get current IP
    local current_ip=$(get_current_ip)
    
    # Parse hostname
    local hostname_parts=$(parse_hostname "$HOSTNAME")
    local zone_name=$(echo "$hostname_parts" | cut -d'|' -f1)
    local record_name=$(echo "$hostname_parts" | cut -d'|' -f2)
    
    log_info "Zone: $zone_name, Record: $record_name"
    
    # Get existing record
    local existing_record_id=$(get_existing_record "$account_id" "$zone_name" "$record_name")
    
    if [ -n "$existing_record_id" ]; then
        # Update existing record
        if update_dns_record "$account_id" "$zone_name" "$existing_record_id" "$current_ip"; then
            log_info "DNS update completed successfully"
        else
            log_error "DNS update failed"
            exit 1
        fi
    else
        # Create new record
        if create_dns_record "$account_id" "$zone_name" "$record_name" "$current_ip"; then
            log_info "DNS record creation completed successfully"
        else
            log_error "DNS record creation failed"
            exit 1
        fi
    fi
}

# Help function
show_help() {
    cat << EOF
DNSimple DNS Simple Updater - Shell Script Version

Updates a single DNS record with the current IP address.

Usage: $0 [options]

Options:
  -h, --help    Show this help message
  --dry-run     Show what would be done without making changes

Environment Variables:
  DNSIMPLE_TOKEN        Your DNSimple API token (required)
  DNSIMPLE_ACCOUNT_ID   Your DNSimple account ID (optional, auto-detected)
  DNSIMPLE_SANDBOX      Set to 'true' for sandbox testing (default: false)
  HOSTNAME              The hostname to update (required)
  RECORD_ID             The DNS record ID to update (optional, auto-detected)

Configuration file (.env):
  You can also set these variables in a .env file in the same directory.

Examples:
  DNSIMPLE_TOKEN=abc123 HOSTNAME=myhost.example.com $0
  $0 --dry-run
  $0 --help

Dependencies:
  - curl (for API requests)
  - jq (for JSON parsing)

EOF
}

# Dry run function
dry_run() {
    echo -e "${BLUE}DRY RUN MODE - No changes will be made${NC}"
    
    load_env_config
    validate_config
    
    local current_ip=$(get_current_ip)
    local hostname_parts=$(parse_hostname "$HOSTNAME")
    local zone_name=$(echo "$hostname_parts" | cut -d'|' -f1)
    local record_name=$(echo "$hostname_parts" | cut -d'|' -f2)
    
    echo -e "${GREEN}Configuration:${NC}"
    echo "  Token: ${DNSIMPLE_TOKEN:0:8}..."
    echo "  Account ID: ${DNSIMPLE_ACCOUNT_ID:-[auto-detect]}"
    echo "  Sandbox: $DNSIMPLE_SANDBOX"
    echo "  Hostname: $HOSTNAME"
    echo "  Zone: $zone_name"
    echo "  Record: $record_name"
    echo "  Current IP: $current_ip"
    
    echo -e "${BLUE}Would update DNS record: $HOSTNAME -> $current_ip${NC}"
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    --dry-run)
        dry_run
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac