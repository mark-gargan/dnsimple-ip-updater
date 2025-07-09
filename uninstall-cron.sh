#!/bin/bash

# AdGuard DNS Rewrite Updater - Cron Uninstall Script
# This script removes the cron job for the updater

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}AdGuard DNS Rewrite Updater - Cron Removal${NC}"
echo "=============================================="

# Get current crontab
TEMP_CRON=$(mktemp)
crontab -l 2>/dev/null > "$TEMP_CRON" || true

# Check if cron job exists
if grep -q "update-dns-cron.sh" "$TEMP_CRON" 2>/dev/null; then
    echo -e "${YELLOW}Removing cron job...${NC}"
    # Remove the cron job
    grep -v "update-dns-cron.sh" "$TEMP_CRON" > "${TEMP_CRON}.new" || true
    mv "${TEMP_CRON}.new" "$TEMP_CRON"
    
    # Install updated crontab
    crontab "$TEMP_CRON"
    echo -e "${GREEN}Cron job removed successfully!${NC}"
else
    echo -e "${YELLOW}No cron job found for AdGuard DNS updater.${NC}"
fi

rm "$TEMP_CRON"

echo ""
echo -e "${BLUE}To view remaining cron jobs:${NC}"
echo "crontab -l"