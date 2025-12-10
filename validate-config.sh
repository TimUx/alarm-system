#!/bin/bash
# Configuration Validation Script for Alarm System
# This script checks if all required configuration is set correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0

echo "=========================================="
echo "Alarm System Configuration Validator"
echo "=========================================="
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}ERROR: .env file not found!${NC}"
    echo "Please copy .env.example to .env and configure it:"
    echo "  cp .env.example .env"
    exit 1
fi

echo "✓ .env file found"
echo ""

# Load .env file
source .env

echo "Checking required configuration..."
echo ""

# Function to check if variable is set and not empty
check_required() {
    local var_name=$1
    local var_value=$2
    local description=$3
    
    if [ -z "$var_value" ]; then
        echo -e "${RED}ERROR: $var_name is not set${NC}"
        echo "  Description: $description"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}✓ $var_name is set${NC}"
    fi
}

# Function to check if variable contains default/example value
check_not_default() {
    local var_name=$1
    local var_value=$2
    local default_value=$3
    
    if [ "$var_value" = "$default_value" ]; then
        echo -e "${YELLOW}WARNING: $var_name still has default value${NC}"
        echo "  Please change it to a secure value"
        WARNINGS=$((WARNINGS + 1))
    fi
}

# Function to check API key strength
check_api_key_strength() {
    local var_name=$1
    local var_value=$2
    
    if [ ${#var_value} -lt 32 ]; then
        echo -e "${YELLOW}WARNING: $var_name is too short (${#var_value} chars)${NC}"
        echo "  Recommended: 64 characters (openssl rand -hex 32)"
        WARNINGS=$((WARNINGS + 1))
    fi
}

echo "=== IMAP Configuration ==="
check_required "ALARM_MAIL_IMAP_HOST" "$ALARM_MAIL_IMAP_HOST" "IMAP server hostname"
check_required "ALARM_MAIL_IMAP_USERNAME" "$ALARM_MAIL_IMAP_USERNAME" "IMAP username"
check_required "ALARM_MAIL_IMAP_PASSWORD" "$ALARM_MAIL_IMAP_PASSWORD" "IMAP password"

check_not_default "ALARM_MAIL_IMAP_HOST" "$ALARM_MAIL_IMAP_HOST" "imap.example.com"
check_not_default "ALARM_MAIL_IMAP_USERNAME" "$ALARM_MAIL_IMAP_USERNAME" "alarm@example.com"
check_not_default "ALARM_MAIL_IMAP_PASSWORD" "$ALARM_MAIL_IMAP_PASSWORD" "change-me"

echo ""
echo "=== API Keys (Security) ==="
check_required "ALARM_MONITOR_API_KEY" "$ALARM_MONITOR_API_KEY" "API key for alarm-monitor"
check_required "ALARM_MESSENGER_API_SECRET_KEY" "$ALARM_MESSENGER_API_SECRET_KEY" "API key for alarm-messenger"
check_required "ALARM_MESSENGER_JWT_SECRET" "$ALARM_MESSENGER_JWT_SECRET" "JWT secret for admin interface"

check_not_default "ALARM_MONITOR_API_KEY" "$ALARM_MONITOR_API_KEY" "change-me-to-random-api-key-for-monitor"
check_not_default "ALARM_MESSENGER_API_SECRET_KEY" "$ALARM_MESSENGER_API_SECRET_KEY" "change-me-to-random-api-key-for-messenger"
check_not_default "ALARM_MESSENGER_JWT_SECRET" "$ALARM_MESSENGER_JWT_SECRET" "change-me-to-random-jwt-secret"

check_api_key_strength "ALARM_MONITOR_API_KEY" "$ALARM_MONITOR_API_KEY"
check_api_key_strength "ALARM_MESSENGER_API_SECRET_KEY" "$ALARM_MESSENGER_API_SECRET_KEY"
check_api_key_strength "ALARM_MESSENGER_JWT_SECRET" "$ALARM_MESSENGER_JWT_SECRET"

# Check if API keys are different
if [ "$ALARM_MONITOR_API_KEY" = "$ALARM_MESSENGER_API_SECRET_KEY" ]; then
    echo -e "${YELLOW}WARNING: ALARM_MONITOR_API_KEY and ALARM_MESSENGER_API_SECRET_KEY are identical${NC}"
    echo "  It's recommended to use different keys for each service"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "=== Messenger Configuration ==="
check_required "ALARM_MESSENGER_SERVER_URL" "$ALARM_MESSENGER_SERVER_URL" "Server URL for QR code generation"

if [[ "$ALARM_MESSENGER_SERVER_URL" == *"localhost"* ]]; then
    echo -e "${YELLOW}WARNING: ALARM_MESSENGER_SERVER_URL contains 'localhost'${NC}"
    echo "  Mobile devices won't be able to connect!"
    echo "  Use your server's IP address or domain name"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "=== Docker Environment Check ==="

# Check if Docker is installed
if command -v docker &> /dev/null; then
    echo -e "${GREEN}✓ Docker is installed${NC}"
    docker --version
else
    echo -e "${RED}ERROR: Docker is not installed${NC}"
    echo "  Please install Docker: https://docs.docker.com/get-docker/"
    ERRORS=$((ERRORS + 1))
fi

# Check if Docker Compose is installed
if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
    echo -e "${GREEN}✓ Docker Compose is installed${NC}"
    docker-compose version 2>/dev/null || docker compose version
else
    echo -e "${RED}ERROR: Docker Compose is not installed${NC}"
    echo "  Please install Docker Compose: https://docs.docker.com/compose/install/"
    ERRORS=$((ERRORS + 1))
fi

# Check if user is in docker group
if groups | grep -q docker; then
    echo -e "${GREEN}✓ Current user is in docker group${NC}"
else
    echo -e "${YELLOW}WARNING: Current user is not in docker group${NC}"
    echo "  You may need to run docker commands with sudo"
    echo "  To fix: sudo usermod -aG docker $USER (requires logout/login)"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "=== Port Availability Check ==="

# Function to check if port is available
check_port() {
    local port=$1
    local service=$2
    
    if command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":$port "; then
            echo -e "${YELLOW}WARNING: Port $port is already in use (needed for $service)${NC}"
            WARNINGS=$((WARNINGS + 1))
        else
            echo -e "${GREEN}✓ Port $port is available${NC}"
        fi
    elif command -v ss &> /dev/null; then
        if ss -tuln | grep -q ":$port "; then
            echo -e "${YELLOW}WARNING: Port $port is already in use (needed for $service)${NC}"
            WARNINGS=$((WARNINGS + 1))
        else
            echo -e "${GREEN}✓ Port $port is available${NC}"
        fi
    else
        echo "  (Cannot check port availability - netstat/ss not found)"
    fi
}

check_port "${ALARM_MONITOR_PORT:-8000}" "alarm-monitor"
check_port "${ALARM_MESSENGER_PORT:-3000}" "alarm-messenger"

echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Configuration looks good!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Start the system: docker-compose up -d"
    echo "  2. Check logs: docker-compose logs -f"
    echo "  3. Create admin user: see QUICKSTART.md"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Configuration is valid but has $WARNINGS warning(s)${NC}"
    echo ""
    echo "You can proceed, but it's recommended to fix the warnings."
    echo ""
    echo "To start anyway: docker-compose up -d"
    exit 0
else
    echo -e "${RED}✗ Configuration has $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo "Please fix the errors before starting the system."
    echo ""
    echo "For help, see:"
    echo "  - README.md"
    echo "  - QUICKSTART.md"
    echo "  - .env.example"
    exit 1
fi
