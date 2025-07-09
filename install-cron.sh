#!/bin/bash

# AdGuard DNS Rewrite Updater - Cron Installation Script
# This script sets up a cron job to run the updater every 15 minutes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON_SCRIPT="$SCRIPT_DIR/update-dns-cron.sh"

echo -e "${GREEN}AdGuard DNS Rewrite Updater - Cron Setup${NC}"
echo "============================================="

# Check if virtual environment exists
if [ ! -d "$SCRIPT_DIR/venv" ]; then
    echo -e "${RED}Error: Virtual environment not found. Please run setup.sh first.${NC}"
    exit 1
fi

# Check if .env file exists
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo -e "${RED}Error: .env file not found. Please copy .env.example to .env and configure it.${NC}"
    exit 1
fi

# Make cron script executable
chmod +x "$CRON_SCRIPT"

# Test the script first
echo -e "${YELLOW}Testing the updater script...${NC}"
if "$SCRIPT_DIR/run.sh" --dry-run; then
    echo -e "${GREEN}Test successful!${NC}"
else
    echo -e "${RED}Test failed. Please check your configuration.${NC}"
    exit 1
fi

# Get current crontab
TEMP_CRON=$(mktemp)
crontab -l 2>/dev/null > "$TEMP_CRON" || true

# Check if cron job already exists
if grep -q "update-dns-cron.sh" "$TEMP_CRON" 2>/dev/null; then
    echo -e "${YELLOW}Cron job already exists. Updating...${NC}"
    # Remove existing entry
    grep -v "update-dns-cron.sh" "$TEMP_CRON" > "${TEMP_CRON}.new" || true
    mv "${TEMP_CRON}.new" "$TEMP_CRON"
fi

# Add new cron job (every 15 minutes)
echo "*/15 * * * * $CRON_SCRIPT" >> "$TEMP_CRON"

# Install new crontab
crontab "$TEMP_CRON"
rm "$TEMP_CRON"

echo -e "${GREEN}Cron job installed successfully!${NC}"
echo ""
echo -e "${BLUE}Cron job details:${NC}"
echo "Schedule: Every 15 minutes"
echo "Command: $CRON_SCRIPT"
echo "Log file: $SCRIPT_DIR/dns-update.log"
echo ""
echo -e "${BLUE}To view current cron jobs:${NC}"
echo "crontab -l"
echo ""
echo -e "${BLUE}To monitor logs:${NC}"
echo "tail -f $SCRIPT_DIR/dns-update.log"
echo ""
echo -e "${BLUE}To remove the cron job later:${NC}"
echo "$SCRIPT_DIR/uninstall-cron.sh"