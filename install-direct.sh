#!/bin/bash
#
# WordPress Security Direct Installer for OpenLiteSpeed + CyberPanel
# One-command installation
# Downloads and runs the main installer
#

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

echo -e "${BLUE}🛡️ WordPress Security for OpenLiteSpeed + CyberPanel${NC}"
echo -e "${BLUE}===============================================${NC}"

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download installer
echo "Downloading installer..."
wget -q https://raw.githubusercontent.com/hienhoceo-dpsmedia/wordpress-security-with-nginx-on-fastpanel/master/openlitespeed-cyberpanel/scripts/install.sh

# Make executable
chmod +x install.sh

# Create configs directory and download security config
mkdir -p configs
wget -q https://raw.githubusercontent.com/hienhoceo-dpsmedia/wordpress-security-with-nginx-on-fastpanel/master/openlitespeed-cyberpanel/configs/wordpress-security.conf -O configs/wordpress-security.conf

# Run installer
echo -e "${GREEN}🚀 Starting installation...${NC}"
sudo ./install.sh "$@"

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo -e "${GREEN}✅ Installation completed!${NC}"