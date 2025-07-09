# DNSimple DNS Records Updater

Automatically updates DNSimple DNS records to point hostnames to the local IP address. Perfect for home servers and self-hosted services that need dynamic IP updates.

## Features

- **Two Implementation Options**: Choose between Python (full-featured) or Shell script (lightweight)
- **Flexible hostname support**: Configure single hostname or comma-separated list of hostnames
- **Cross-platform IP detection**: Works on macOS (ifconfig) and Linux (ip command)
- **Automatic scheduling**: Runs every 15 minutes via cron
- **DNSimple API integration**: Uses official DNSimple Python client or REST API
- **Virtual environment isolation**: Clean Python dependency management (Python version)
- **Enhanced security**: Input validation and secure API communication
- **Comprehensive logging**: Detailed logs for monitoring and debugging
- **Easy installation**: One-command setup with guided configuration
- **Sandbox support**: Test against DNSimple sandbox environment

## Quick Start

### Automatic Installation (Recommended)

Run the complete installer:
```bash
./install.sh
```

This will:
1. Set up Python virtual environment
2. Install dependencies
3. Guide you through configuration
4. Test your setup
5. Optionally install cron job for automatic updates

### Manual Installation

1. **Setup environment:**
```bash
./setup.sh
```

2. **Configure settings:**
```bash
cp .env.example .env
# Edit .env with your AdGuard credentials
```

3. **Test configuration:**
```bash
./run.sh --dry-run
```

4. **Install automatic updates:**
```bash
./install-cron.sh
```

## Usage Options

### Python Version (Full-Featured)
```bash
# Show help
./run.sh --help

# Dry run (show what would be done)
./run.sh --dry-run

# Manual execution
./run.sh
```

### Shell Script Version (Lightweight)
```bash
# Show help
./update-dns-simple.sh --help

# Dry run (show what would be done)
./update-dns-simple.sh --dry-run

# Manual execution
./update-dns-simple.sh
```
## Configuration

### Python Version
Environment variables in `.env`:
- `DNSIMPLE_TOKEN`: Your DNSimple API token
- `DNSIMPLE_ACCOUNT_ID`: Your DNSimple account ID (optional, auto-detected if not provided)
- `DNSIMPLE_SANDBOX`: Set to 'true' to use sandbox environment (default: false)
- `HOSTNAMES`: Comma-separated list of domain names to update

### Shell Script Version
Environment variables in `.env`:
- `DNSIMPLE_TOKEN`: Your DNSimple API token
- `DNSIMPLE_ACCOUNT_ID`: Your DNSimple account ID (optional, auto-detected if not provided)
- `DNSIMPLE_SANDBOX`: Set to 'true' to use sandbox environment (default: false)
- `HOSTNAME`: Single domain name to update (note: singular, not plural)

## Configuration Examples

### Python Version Examples

#### Single Hostname
```bash
HOSTNAMES=myhost.example.com
```

#### Multiple Hostnames
```bash
HOSTNAMES=myhost.example.com,server.example.com,api.example.com,web.example.com
```

#### Home Server Services
```bash
HOSTNAMES=home.example.com,plex.example.com,sonarr.example.com,radarr.example.com,sabnzbd.example.com
```

#### Complete Python Example
```bash
DNSIMPLE_TOKEN=your_api_token_here
DNSIMPLE_ACCOUNT_ID=12345
DNSIMPLE_SANDBOX=false
HOSTNAMES=home.example.com,api.example.com
```

### Shell Script Version Examples

#### Basic Shell Script Configuration
```bash
DNSIMPLE_TOKEN=your_api_token_here
DNSIMPLE_ACCOUNT_ID=12345
DNSIMPLE_SANDBOX=false
HOSTNAME=myhost.example.com
```

#### Sandbox Testing
```bash
DNSIMPLE_TOKEN=your_sandbox_token_here
DNSIMPLE_SANDBOX=true
HOSTNAME=test.example.com
```

## Management Commands

```bash
# Install cron job
./install-cron.sh

# Remove cron job
./uninstall-cron.sh

# View current cron jobs
crontab -l

# Monitor logs in real-time
tail -f dns-update.log
```

## Logs

All activity is logged to `dns-update.log` in the script directory. Use `tail -f dns-update.log` to monitor real-time updates.

## DNSimple Setup

1. **Create DNSimple Account**: Sign up at [DNSimple](https://dnsimple.com)
2. **Get API Token**: Go to Account Settings > API Access and generate a new token
3. **Find Account ID**: Your account ID is shown in the DNSimple dashboard
4. **Add Domains**: Ensure your domains are registered or managed through DNSimple
5. **Test with Sandbox**: Use `DNSIMPLE_SANDBOX=true` to test in sandbox environment first

## Which Version Should I Use?

### Use Python Version When:
- You need to update multiple hostnames simultaneously
- You want comprehensive error handling and logging
- You need cross-platform compatibility features
- You prefer the official DNSimple Python client

### Use Shell Script Version When:
- You only need to update a single hostname
- You want minimal dependencies (just curl and jq)
- You prefer lightweight shell scripts
- You want faster execution times
- You're working in resource-constrained environments

### Dependencies Comparison

**Python Version:**
- Python 3.8+
- python-dotenv
- dnsimple (official client)
- Virtual environment setup

**Shell Script Version:**
- bash
- curl
- jq (for JSON parsing)
- No virtual environment needed