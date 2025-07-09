#!/bin/bash

# DNSimple DNS Records Updater - Run Script
# This script activates the virtual environment and runs the updater

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"

# Check if virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo "Virtual environment not found. Please run setup.sh first."
    exit 1
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Change to script directory
cd "$SCRIPT_DIR"

# Run the Python script with all passed arguments
python3 update-dnsimple-dns.py "$@"