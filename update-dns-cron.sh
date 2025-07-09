#!/bin/bash
# Cron job script to update DNSimple DNS records
# Run this every 15 minutes to keep DNS updated

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"

# Check if virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo "$(date): ERROR - Virtual environment not found at $VENV_DIR" >> "$SCRIPT_DIR/dns-update.log"
    exit 1
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Change to script directory and run
cd "$SCRIPT_DIR"
python3 update-dnsimple-dns.py >> "$SCRIPT_DIR/dns-update.log" 2>&1