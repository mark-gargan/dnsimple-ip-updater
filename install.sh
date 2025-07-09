#!/bin/bash

# DNSimple DNS Records Updater - Complete Installation Script
# This script performs the complete setup process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              DNSimple DNS Records Updater Installer          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Choose implementation
echo -e "${BLUE}Step 1: Choose implementation type...${NC}"
echo -e "${YELLOW}Which version would you like to use?${NC}"
echo "1) Python version (full-featured, multiple hostnames)"
echo "2) Shell script version (lightweight, single hostname)"
echo -e "${CYAN}For more details, see README.md${NC}"
echo ""

while true; do
    read -p "Enter your choice (1 or 2): " choice
    case $choice in
        1)
            IMPLEMENTATION="python"
            echo -e "${GREEN}✓ Selected Python version${NC}"
            break
            ;;
        2)
            IMPLEMENTATION="shell"
            echo -e "${GREEN}✓ Selected Shell script version${NC}"
            break
            ;;
        *)
            echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
            ;;
    esac
done

echo ""

# Step 2: Setup environment
if [ "$IMPLEMENTATION" = "python" ]; then
    echo -e "${BLUE}Step 2: Setting up Python virtual environment...${NC}"
    if "$SCRIPT_DIR/setup.sh"; then
        echo -e "${GREEN}✓ Python environment setup complete${NC}"
    else
        echo -e "${RED}✗ Python environment setup failed${NC}"
        exit 1
    fi
else
    echo -e "${BLUE}Step 2: Checking shell script dependencies...${NC}"
    missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}✗ Missing dependencies: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}Please install with:${NC}"
        echo "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
        echo "  macOS: brew install ${missing_deps[*]}"
        echo "  CentOS/RHEL: sudo yum install ${missing_deps[*]}"
        exit 1
    else
        echo -e "${GREEN}✓ All dependencies are available${NC}"
    fi
fi

echo ""

# Step 3: Configure .env file
echo -e "${BLUE}Step 3: Configuring environment...${NC}"
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo -e "${YELLOW}Creating .env file from template...${NC}"
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    echo -e "${YELLOW}⚠ Please edit .env file with your DNSimple settings:${NC}"
    echo "  - DNSIMPLE_TOKEN: Your DNSimple API token"
    echo "  - DNSIMPLE_ACCOUNT_ID: Your DNSimple account ID (optional)"
    echo "  - DNSIMPLE_SANDBOX: Set to 'true' for sandbox testing"
    
    if [ "$IMPLEMENTATION" = "python" ]; then
        echo "  - HOSTNAMES: Comma-separated list of hostnames to update"
    else
        echo "  - HOSTNAME: Single hostname to update (not HOSTNAMES)"
    fi
    echo ""
    echo -e "${YELLOW}Opening .env file for editing...${NC}"
    
    # Try to open with common editors
    if command -v nano &> /dev/null; then
        nano "$SCRIPT_DIR/.env"
    elif command -v vim &> /dev/null; then
        vim "$SCRIPT_DIR/.env"
    elif command -v code &> /dev/null; then
        code "$SCRIPT_DIR/.env"
        echo "Please save and close VS Code when done editing."
        read -p "Press Enter when you've finished editing the .env file..."
    else
        echo -e "${RED}No suitable editor found. Please manually edit: $SCRIPT_DIR/.env${NC}"
        read -p "Press Enter when you've finished editing the .env file..."
    fi
else
    echo -e "${GREEN}✓ .env file already exists${NC}"
fi

echo ""

# Step 4: Test the configuration
echo -e "${BLUE}Step 4: Testing configuration...${NC}"
if [ "$IMPLEMENTATION" = "python" ]; then
    if "$SCRIPT_DIR/run.sh" --dry-run; then
        echo -e "${GREEN}✓ Configuration test successful${NC}"
    else
        echo -e "${RED}✗ Configuration test failed${NC}"
        echo -e "${YELLOW}Please check your .env settings and try again.${NC}"
        exit 1
    fi
else
    if "$SCRIPT_DIR/update-dns-simple.sh" --dry-run; then
        echo -e "${GREEN}✓ Configuration test successful${NC}"
    else
        echo -e "${RED}✗ Configuration test failed${NC}"
        echo -e "${YELLOW}Please check your .env settings and try again.${NC}"
        exit 1
    fi
fi

echo ""

# Step 5: Install cron job
echo -e "${BLUE}Step 5: Setting up automatic updates...${NC}"
read -p "Install cron job for automatic updates every 15 minutes? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Create a custom cron script based on implementation choice
    if [ "$IMPLEMENTATION" = "python" ]; then
        if "$SCRIPT_DIR/install-cron.sh"; then
            echo -e "${GREEN}✓ Cron job installed successfully (Python version)${NC}"
        else
            echo -e "${RED}✗ Cron job installation failed${NC}"
            exit 1
        fi
    else
        # Create a shell script cron job
        CRON_SCRIPT="$SCRIPT_DIR/update-dns-simple-cron.sh"
        cat > "$CRON_SCRIPT" << 'EOF'
#!/bin/bash
# Cron job script to update DNSimple DNS records using shell script
# Run this every 15 minutes to keep DNS updated

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Change to script directory and run
cd "$SCRIPT_DIR"
./update-dns-simple.sh >> "$SCRIPT_DIR/dns-update.log" 2>&1
EOF
        chmod +x "$CRON_SCRIPT"
        
        # Install cron job
        CRON_ENTRY="*/15 * * * * $CRON_SCRIPT"
        (crontab -l 2>/dev/null | grep -v "$CRON_SCRIPT"; echo "$CRON_ENTRY") | crontab -
        
        echo -e "${GREEN}✓ Cron job installed successfully (Shell script version)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Skipping cron job installation${NC}"
    if [ "$IMPLEMENTATION" = "python" ]; then
        echo "You can install it later by running: $SCRIPT_DIR/install-cron.sh"
    else
        echo "You can install it later by running the shell script manually or setting up your own cron job"
    fi
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Installation Complete!                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Quick Commands:${NC}"
if [ "$IMPLEMENTATION" = "python" ]; then
    echo "  Test run:        ./run.sh --dry-run"
    echo "  Manual update:   ./run.sh"
    echo "  Install cron:    ./install-cron.sh"
    echo "  Remove cron:     ./uninstall-cron.sh"
else
    echo "  Test run:        ./update-dns-simple.sh --dry-run"
    echo "  Manual update:   ./update-dns-simple.sh"
    echo "  Show help:       ./update-dns-simple.sh --help"
fi
echo "  View logs:       tail -f dns-update.log"
echo ""
echo -e "${GREEN}Your DNSimple DNS records updater ($IMPLEMENTATION version) is ready to use!${NC}"