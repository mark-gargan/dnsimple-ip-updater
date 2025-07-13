#!/usr/bin/env python3
"""
Script to automatically update DNSimple DNS records
Sets HOSTNAMES to point to the local ethernet IP
Supports single hostname or multiple hostnames (comma-separated)
"""

import json
import os
import subprocess
import sys
import logging
from dotenv import load_dotenv
import socket
from dnsimple import Client

# Load environment variables from .env file
load_dotenv()

# Configuration from environment variables
DNSIMPLE_TOKEN = os.getenv("DNSIMPLE_TOKEN")
DNSIMPLE_ACCOUNT_ID = os.getenv("DNSIMPLE_ACCOUNT_ID")
DNSIMPLE_SANDBOX = os.getenv("DNSIMPLE_SANDBOX", "false").lower() == "true"
HOSTNAMES = os.getenv("HOSTNAMES")

# Logging setup
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def parse_hostnames():
    """Parse hostnames from HOSTNAMES environment variable"""
    if HOSTNAMES:
        # Parse comma-separated list of hostnames
        hostnames = [hostname.strip() for hostname in HOSTNAMES.split(',') if hostname.strip()]
        logger.info(f"Using HOSTNAMES configuration: {hostnames}")
        return hostnames
    else:
        logger.error("No hostnames configured. Please set HOSTNAMES in your .env file.")
        return []

def validate_hostname(hostname):
    """Enhanced hostname validation with security checks, including wildcard support"""
    if not hostname or len(hostname) > 253:
        return False
    
    # Check for suspicious patterns
    if hostname.startswith('.') or hostname.endswith('.') or '..' in hostname:
        return False
    
    # Split into parts
    parts = hostname.split('.')
    if len(parts) < 2:  # Require at least domain.tld
        return False
    
    # Validate each part
    for i, part in enumerate(parts):
        if not part or len(part) > 63:
            return False
        
        # Special handling for wildcard (*) - only allowed as first part
        if part == '*':
            if i != 0:  # Wildcard only allowed at the beginning
                return False
            continue
        
        # Regular hostname part validation
        # Must start and end with alphanumeric
        if not part[0].isalnum() or not part[-1].isalnum():
            return False
        # Only allow alphanumeric and hyphens
        if not all(c.isalnum() or c == '-' for c in part):
            return False
    
    return True

def get_ethernet_ip():
    """Get the IP address of the ethernet interface."""
    # Try platform-specific methods
    ip = get_ip_linux() or get_ip_macos()
    if ip:
        return ip
    
    logger.error("No ethernet IP address found on any platform")
    return None

def get_ip_linux():
    """Get IP address on Linux using ip command."""
    try:
        # Try using ip command (modern Linux)
        result = subprocess.run(['ip', 'route', 'get', '8.8.8.8'], capture_output=True, text=True, check=True)
        
        # Parse output to find source IP
        for line in result.stdout.split('\n'):
            if 'src' in line:
                parts = line.split()
                src_index = parts.index('src')
                if src_index + 1 < len(parts):
                    ip = parts[src_index + 1]
                    if not ip.startswith('127.') and not ip.startswith('169.254.'):
                        logger.info(f"Found IP using ip command: {ip}")
                        return ip
        
        # Fallback: try ip addr show
        result = subprocess.run(['ip', 'addr', 'show'], capture_output=True, text=True, check=True)
        lines = result.stdout.split('\n')
        
        for line in lines:
            line = line.strip()
            if line.startswith('inet ') and 'scope global' in line:
                parts = line.split()
                if len(parts) >= 2:
                    ip = parts[1].split('/')[0]  # Remove CIDR notation
                    if not ip.startswith('127.') and not ip.startswith('169.254.'):
                        logger.info(f"Found IP using ip addr: {ip}")
                        return ip
        
        return None
        
    except (subprocess.CalledProcessError, FileNotFoundError, ValueError):
        logger.debug("ip command not available or failed")
        return None
    except Exception as e:
        logger.debug(f"Error getting IP on Linux: {e}")
        return None

def get_ip_macos():
    """Get IP address on macOS using ifconfig."""
    try:
        # Get network interface info on macOS
        result = subprocess.run(['ifconfig'], capture_output=True, text=True, check=True)
        lines = result.stdout.split('\n')
        
        # Look for ethernet interface (en0 typically)
        current_interface = None
        for line in lines:
            line = line.strip()
            
            # New interface block
            if line.startswith('en'):
                current_interface = line.split(':')[0]
                logger.debug(f"Found interface: {current_interface}")
            
            # Look for inet address in ethernet interface
            elif line.startswith('inet ') and current_interface and current_interface.startswith('en'):
                # Extract IP address
                parts = line.split()
                if len(parts) >= 2:
                    ip = parts[1]
                    # Skip loopback and link-local addresses
                    if not ip.startswith('127.') and not ip.startswith('169.254.'):
                        logger.info(f"Found ethernet IP: {ip} on interface {current_interface}")
                        return ip
        
        return None
        
    except (subprocess.CalledProcessError, FileNotFoundError):
        logger.debug("ifconfig command not available or failed")
        return None
    except Exception as e:
        logger.debug(f"Error getting IP on macOS: {e}")
        return None

def get_dnsimple_client():
    """Initialize DNSimple client"""
    if not DNSIMPLE_TOKEN:
        logger.error("DNSimple token not configured")
        return None
    
    try:
        client = Client(sandbox=DNSIMPLE_SANDBOX, access_token=DNSIMPLE_TOKEN)
        return client
    except Exception as e:
        logger.error(f"Failed to initialize DNSimple client: {e}")
        return None

def get_account_id(client):
    """Get account ID from DNSimple"""
    try:
        if DNSIMPLE_ACCOUNT_ID:
            return DNSIMPLE_ACCOUNT_ID
        
        whoami = client.identity.whoami().data
        account_id = whoami.account.id
        logger.info(f"Using account ID: {account_id}")
        return account_id
    except Exception as e:
        logger.error(f"Failed to get account ID: {e}")
        return None

def get_existing_dns_records(client, account_id, zone_name):
    """Get existing DNS records from DNSimple for a zone"""
    try:
        # Try common method names for listing records
        if hasattr(client.zones, 'list_records'):
            records = client.zones.list_records(account_id, zone_name).data
        elif hasattr(client.zones, 'records'):
            records = client.zones.records(account_id, zone_name).data
        elif hasattr(client.zones, 'all_records'):
            records = client.zones.all_records(account_id, zone_name).data
        else:
            # Fall back to direct API call
            records = client.zones.list_zone_records(account_id, zone_name).data
        return records
    except Exception as e:
        logger.error(f"Failed to get existing DNS records for {zone_name}: {e}")
        return None

def delete_dns_record(client, account_id, zone_name, record_id):
    """Delete DNS record from DNSimple"""
    try:
        # Try common method names for deleting records
        if hasattr(client.zones, 'delete_record'):
            client.zones.delete_record(account_id, zone_name, record_id)
        else:
            client.zones.delete_zone_record(account_id, zone_name, record_id)
        logger.info(f"Deleted DNS record {record_id} from zone {zone_name}")
        return True
    except Exception as e:
        logger.error(f"Failed to delete DNS record {record_id}: {e}")
        return False

def validate_ip_address(ip):
    """Validate IP address format"""
    try:
        import ipaddress
        ipaddress.ip_address(ip)
        return True
    except ValueError:
        return False

def create_dns_record(client, account_id, zone_name, name, ip):
    """Create DNS A record in DNSimple"""
    try:
        # Validate IP address
        if not validate_ip_address(ip):
            logger.error(f"Invalid IP address format: {ip}")
            return False
        
        # Try common method names for creating records
        if hasattr(client.zones, 'create_record'):
            response = client.zones.create_record(account_id, zone_name, {
                "name": name,
                "type": "A",
                "content": ip,
                "ttl": 300
            })
        else:
            response = client.zones.create_zone_record(account_id, zone_name, {
                "name": name,
                "type": "A", 
                "content": ip,
                "ttl": 300
            })
        logger.info(f"Successfully created DNS record: {name}.{zone_name} -> {ip}")
        return response.data
        
    except Exception as e:
        logger.error(f"Failed to create DNS record: {e}")
        return False

def update_dns_record(client, account_id, zone_name, record_id, ip):
    """Update existing DNS A record in DNSimple"""
    try:
        # Validate IP address
        if not validate_ip_address(ip):
            logger.error(f"Invalid IP address format: {ip}")
            return False
        
        # Try common method names for updating records
        if hasattr(client.zones, 'update_record'):
            response = client.zones.update_record(account_id, zone_name, record_id, {
                "content": ip,
                "ttl": 300
            })
        else:
            response = client.zones.update_zone_record(account_id, zone_name, record_id, {
                "content": ip,
                "ttl": 300
            })
        logger.info(f"Successfully updated DNS record {record_id} -> {ip}")
        return response.data
        
    except Exception as e:
        logger.error(f"Failed to update DNS record {record_id}: {e}")
        return False

def process_hostname(client, account_id, hostname, local_ip):
    """Process a single hostname for DNS record update"""
    logger.info(f"Processing hostname: {hostname}")
    
    # Validate hostname
    if not validate_hostname(hostname):
        logger.error(f"Invalid hostname format: {hostname}")
        return False
    
    # Parse hostname to get zone and record name
    parts = hostname.split('.')
    if len(parts) < 2:
        logger.error(f"Invalid hostname format: {hostname}")
        return False
    
    # Extract zone name (last two parts for basic domains)
    zone_name = '.'.join(parts[-2:])
    
    # Handle record name, including wildcard support
    if len(parts) > 2:
        record_name = '.'.join(parts[:-2])
    else:
        record_name = ''
    
    # Log wildcard record creation
    if record_name == '*':
        logger.info(f"Creating wildcard record for zone {zone_name}")
    elif record_name.startswith('*.'):
        logger.info(f"Creating wildcard record: {record_name} for zone {zone_name}")
    
    # Get existing records for this zone
    existing_records = get_existing_dns_records(client, account_id, zone_name)
    if existing_records is None:
        logger.error(f"Could not retrieve existing records for zone {zone_name}")
        return False
    
    # Check if A record already exists for this hostname
    existing_record = None
    for record in existing_records:
        if record.type == 'A' and record.name == record_name:
            existing_record = record
            break
    
    if existing_record:
        if existing_record.content == local_ip:
            logger.info(f"DNS record already exists and is current: {hostname} -> {local_ip}")
            return True
        else:
            logger.info(f"DNS record exists but IP is different: {existing_record.content} -> {local_ip}")
            # Update existing record
            if update_dns_record(client, account_id, zone_name, existing_record.id, local_ip):
                logger.info(f"Successfully updated DNS record: {hostname} -> {local_ip}")
                return True
            else:
                logger.error(f"Failed to update DNS record for {hostname}")
                return False
    else:
        # Create new record
        if create_dns_record(client, account_id, zone_name, record_name, local_ip):
            logger.info(f"Successfully created DNS record: {hostname} -> {local_ip}")
            return True
        else:
            logger.error(f"Failed to create DNS record for {hostname}")
            return False

def update_dns_records():
    """Main function to update DNS records for all hostnames"""
    logger.info("Starting DNS records update...")
    
    # Initialize DNSimple client
    client = get_dnsimple_client()
    if not client:
        logger.error("Could not initialize DNSimple client")
        return False
    
    # Get account ID
    account_id = get_account_id(client)
    if not account_id:
        logger.error("Could not get account ID")
        return False
    
    # Parse hostnames
    hostnames = parse_hostnames()
    if not hostnames:
        logger.error("No hostnames configured")
        return False
    
    logger.info(f"Processing {len(hostnames)} hostname(s): {hostnames}")
    
    # Get local IP
    local_ip = get_ethernet_ip()
    if not local_ip:
        logger.error("Could not determine local IP address")
        return False
    
    logger.info(f"Local IP: {local_ip}")
    
    # Process each hostname
    success_count = 0
    total_count = len(hostnames)
    
    for hostname in hostnames:
        if process_hostname(client, account_id, hostname, local_ip):
            success_count += 1
        else:
            logger.error(f"Failed to process hostname: {hostname}")
            # Continue processing other hostnames instead of failing completely
    
    # Log summary
    if success_count == total_count:
        logger.info(f"DNS records update completed successfully for all {total_count} hostname(s)")
        return True
    elif success_count > 0:
        logger.warning(f"DNS records update partially completed: {success_count}/{total_count} hostname(s) succeeded")
        return True  # Return success if at least one hostname was processed
    else:
        logger.error("DNS records update failed for all hostnames")
        return False

def main():
    """Main entry point"""
    if len(sys.argv) > 1 and sys.argv[1] in ['-h', '--help']:
        hostnames = parse_hostnames()
        hostname_display = ', '.join(hostnames) if hostnames else '[not configured]'
        
        print(f"""
DNSimple DNS Records Updater

Updates DNSimple DNS records to point hostname(s) to local ethernet IP.

Configuration (edit .env file to change):
- DNSimple Token: {'[configured]' if DNSIMPLE_TOKEN else '[not configured]'}
- Account ID: {DNSIMPLE_ACCOUNT_ID or '[auto-detected]'}
- Sandbox Mode: {'Enabled' if DNSIMPLE_SANDBOX else 'Disabled'}
- Hostname(s): {hostname_display}

Environment Variables:
- HOSTNAMES: Comma-separated list of hostnames
  Examples: 
    Single hostname: HOSTNAMES=myhost.example.com
    Multiple hostnames: HOSTNAMES=myhost.example.com,server.example.com,api.example.com
- DNSIMPLE_TOKEN: Your DNSimple API token
- DNSIMPLE_ACCOUNT_ID: Your DNSimple account ID (optional, auto-detected if not provided)
- DNSIMPLE_SANDBOX: Set to 'true' to use sandbox environment (default: false)

Usage: {sys.argv[0]} [options]
Options:
  -h, --help    Show this help message
  --dry-run     Show what would be done without making changes
        """)
        return
    
    if len(sys.argv) > 1 and sys.argv[1] == '--dry-run':
        logger.info("DRY RUN MODE - No changes will be made")
        hostnames = parse_hostnames()
        local_ip = get_ethernet_ip()
        if local_ip and hostnames:
            logger.info(f"Would update {len(hostnames)} hostname(s): {hostnames}")
            for hostname in hostnames:
                if validate_hostname(hostname):
                    logger.info(f"  {hostname} -> {local_ip}")
                else:
                    logger.error(f"  Invalid hostname format: {hostname}")
        elif not hostnames:
            logger.error("No hostnames configured")
        else:
            logger.error("Could not determine local IP")
        return
    
    success = update_dns_records()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()