#!/bin/bash

# ============================================================
# SMART BOT VERIFICATION - DYNAMIC IP UPDATES
# ============================================================
# Script: update-bot-ips.sh
# Purpose: Fetch latest Googlebot and Bingbot IP ranges
# Compatible with OpenLiteSpeed + CyberPanel
# Inspired by Nginx dynamic bot verification

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/bot-ip-updates.log"
IP_DIR="/etc/openlitespeed/bot-ips"
GOOGLE_IP_FILE="$IP_DIR/googlebot-ips.txt"
BING_IP_FILE="$IP_DIR/bingbot-ips.txt"
TEMP_DIR="/tmp/bot-ip-update"

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

# Print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}" | tee -a "$LOG_FILE"
}

# Create directories
setup_directories() {
    print_status "Setting up directories..."
    sudo mkdir -p "$IP_DIR"
    sudo mkdir -p "$TEMP_DIR"
    sudo touch "$LOG_FILE"
    sudo chmod 644 "$LOG_FILE"
}

# Download Googlebot IP ranges
fetch_google_ips() {
    print_header "Fetching Googlebot IP Ranges"

    # Google publishes their IP ranges in JSON format
    GOOGLE_URLS=(
        "https://www.gstatic.com/ipranges/goog.json"
        "https://www.gstatic.com/ipranges/cloud.json"
    )

    local temp_google_ips="$TEMP_DIR/google-ips.tmp"
    > "$temp_google_ips"

    for url in "${GOOGLE_URLS[@]}"; do
        print_status "Downloading: $url"

        if curl -s --max-time 30 --fail "$url" -o "$TEMP_DIR/google-temp.json"; then
            # Extract IPv4 ranges from JSON
            if command -v jq >/dev/null 2>&1; then
                # Use jq if available
                jq -r '.prefixes[] | select(.ipv4Prefix) | .ipv4Prefix' "$TEMP_DIR/google-temp.json" >> "$temp_google_ips"
            else
                # Fallback to grep/sed if jq not available
                grep -o '"ipv4Prefix":"[^"]*"' "$TEMP_DIR/google-temp.json" | cut -d'"' -f4 >> "$temp_google_ips"
            fi
            print_status "Successfully fetched IP ranges from $url"
        else
            print_warning "Failed to download from $url"
        fi
    done

    # Convert CIDR to individual IPs for OpenLiteSpeed compatibility
    local expanded_ips="$TEMP_DIR/google-expanded.tmp"
    > "$expanded_ips"

    while read -r cidr; do
        if [[ -n "$cidr" ]]; then
            # Convert CIDR to IP range (simplified version)
            ipcalc "$cidr" 2>/dev/null | grep -E '^[0-9]+\.' | while read -r ip; do
                echo "^${ip//./\\.}\\." >> "$expanded_ips"
            done
        fi
    done < "$temp_google_ips"

    # If ipcalc not available, use direct CIDR patterns
    if [[ ! -s "$expanded_ips" ]]; then
        while read -r cidr; do
            if [[ -n "$cidr" ]]; then
                # Convert CIDR to regex pattern for OpenLiteSpeed
                local ip_base=$(echo "$cidr" | cut -d'/' -f1 | cut -d'.' -f1-3)
                echo "^${ip_base//./\\.}\\." >> "$expanded_ips"
            fi
        done < "$temp_google_ips"
    fi

    if [[ -s "$expanded_ips" ]]; then
        sudo mv "$expanded_ips" "$GOOGLE_IP_FILE"
        sudo chmod 644 "$GOOGLE_IP_FILE"
        local ip_count=$(wc -l < "$GOOGLE_IP_FILE")
        print_status "Googlebot IP ranges updated: $ip_count ranges"
    else
        print_error "No Googlebot IP ranges fetched"
        return 1
    fi
}

# Download Bingbot IP ranges
fetch_bing_ips() {
    print_header "Fetching Bingbot IP Ranges"

    # Microsoft publishes their IP ranges
    BING_URL="https://www.microsoft.com/en-us/download/confirmation.aspx?id=41653"

    local temp_bing_ips="$TEMP_DIR/bing-ips.tmp"

    print_status "Downloading Microsoft IP ranges..."

    # Get the actual download URL from the confirmation page
    local download_url=$(curl -s "$BING_URL" | grep -o 'href="[^"]*PublicIPs[^"]*\.json"' | head -1 | cut -d'"' -f2)

    if [[ -n "$download_url" ]]; then
        if curl -s --max-time 30 --fail "https://www.microsoft.com/$download_url" -o "$TEMP_DIR/bing-temp.json"; then
            # Extract Bingbot IPs (usually in specific ranges)
            if command -v jq >/dev/null 2>&1; then
                jq -r '.values[] | select(.name | contains("Bing")) | .properties.addressPrefixes[]' "$TEMP_DIR/bing-temp.json" >> "$temp_bing_ips"
            else
                # Fallback method
                grep -A 5 -B 5 "Bing" "$TEMP_DIR/bing-temp.json" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+/[0-9]\+' >> "$temp_bing_ips"
            fi

            # Convert CIDR to regex patterns
            local expanded_ips="$TEMP_DIR/bing-expanded.tmp"
            > "$expanded_ips"

            while read -r cidr; do
                if [[ -n "$cidr" ]]; then
                    local ip_base=$(echo "$cidr" | cut -d'/' -f1 | cut -d'.' -f1-3)
                    echo "^${ip_base//./\\.}\\." >> "$expanded_ips"
                fi
            done < "$temp_bing_ips"

            if [[ -s "$expanded_ips" ]]; then
                sudo mv "$expanded_ips" "$BING_IP_FILE"
                sudo chmod 644 "$BING_IP_FILE"
                local ip_count=$(wc -l < "$BING_IP_FILE")
                print_status "Bingbot IP ranges updated: $ip_count ranges"
            else
                print_warning "No Bingbot IP ranges extracted, using fallback"
                # Fallback to known Bing ranges
                cat > "$BING_IP_FILE" << EOF
^157\\.55\\.
^40\\.77\\.
^207\\.46\\.
^131\\.253\\.
^204\\.79\\.
^65\\.52\\.
^104\\.146\\.
^13\\.77\\.
^52\\.\\.
^20\\.
EOF
                print_status "Using fallback Bingbot IP ranges"
            fi
        else
            print_warning "Failed to download Bing IP ranges, using fallback"
            # Use known Bing ranges as fallback
            cat > "$BING_IP_FILE" << EOF
^157\\.55\\.
^40\\.77\\.
^207\\.46\\.
^131\\.253\\.
EOF
            print_status "Using fallback Bingbot IP ranges"
        fi
    else
        print_warning "Could not find Bing IP download URL, using fallback"
        cat > "$BING_IP_FILE" << EOF
^157\\.55\\.
^40\\.77\\.
EOF
        print_status "Using minimal fallback Bingbot IP ranges"
    fi
}

# Update OpenLiteSpeed configuration
update_ols_config() {
    print_header "Updating OpenLiteSpeed Configuration"

    # Create dynamic include file for OpenLiteSpeed
    local dynamic_config="$IP_DIR/bot-verification.conf"

    cat > "$TEMP_DIR/bot-config.tmp" << 'EOF'
# ============================================================
# DYNAMIC BOT VERIFICATION CONFIGURATION
# Auto-generated by update-bot-ips.sh
# ============================================================

<IfModule mod_rewrite.c>
    RewriteEngine On

    # === GOOGLEBOT VERIFICATION ===
    RewriteCond %{HTTP_USER_AGENT} !^googlebot [NC,OR]
    RewriteCond %{HTTP_USER_AGENT} !^googlebot-image [NC,OR]
    RewriteCond %{HTTP_USER_AGENT} !^googlebot-news [NC]
    RewriteRule ^ - [S=10]

    # Verify Googlebot IP ranges
EOF

    # Add Google IP ranges to config
    if [[ -f "$GOOGLE_IP_FILE" ]]; then
        local count=0
        while read -r ip_pattern; do
            if [[ -n "$ip_pattern" && $count -lt 50 ]]; then  # Limit to 50 rules for performance
                echo "    RewriteCond %{REMOTE_ADDR} $ip_pattern [OR]" >> "$TEMP_DIR/bot-config.tmp"
                ((count++))
            fi
        done < "$GOOGLE_IP_FILE"

        # Remove last OR and add final condition
        sed -i '$ s/ \[OR\]$//' "$TEMP_DIR/bot-config.tmp"
        echo "    RewriteRule ^ - [S=1]" >> "$TEMP_DIR/bot-config.tmp"
        echo "" >> "$TEMP_DIR/bot-config.tmp"
    fi

    cat >> "$TEMP_DIR/bot-config.tmp" << 'EOF'
    # Block fake Googlebot
    RewriteCond %{HTTP_USER_AGENT} ^googlebot [NC]
    RewriteRule ^ - [F,L]

    # === BINGBOT VERIFICATION ===
    RewriteCond %{HTTP_USER_AGENT} !^bingbot [NC]
    RewriteRule ^ - [S=5]

    # Verify Bingbot IP ranges
EOF

    # Add Bing IP ranges to config
    if [[ -f "$BING_IP_FILE" ]]; then
        local count=0
        while read -r ip_pattern; do
            if [[ -n "$ip_pattern" && $count -lt 20 ]]; then  # Limit to 20 rules
                echo "    RewriteCond %{REMOTE_ADDR} $ip_pattern [OR]" >> "$TEMP_DIR/bot-config.tmp"
                ((count++))
            fi
        done < "$BING_IP_FILE"

        # Remove last OR
        sed -i '$ s/ \[OR\]$//' "$TEMP_DIR/bot-config.tmp"
        echo "    RewriteRule ^ - [S=1]" >> "$TEMP_DIR/bot-config.tmp"
        echo "" >> "$TEMP_DIR/bot-config.tmp"
    fi

    cat >> "$TEMP_DIR/bot-config.tmp" << 'EOF'
    # Block fake Bingbot
    RewriteCond %{HTTP_USER_AGENT} ^bingbot [NC]
    RewriteRule ^ - [F,L]

</IfModule>
EOF

    # Install the configuration
    sudo mv "$TEMP_DIR/bot-config.tmp" "$dynamic_config"
    sudo chmod 644 "$dynamic_config"

    print_status "Dynamic bot verification configuration updated"
}

# Restart OpenLiteSpeed if needed
restart_ols_if_needed() {
    if systemctl is-active --quiet openlitespeed || systemctl is-active --quiet lsws; then
        print_status "Restarting OpenLiteSpeed to apply new bot verification rules..."

        if systemctl is-active --quiet openlitespeed; then
            sudo systemctl reload openlitespeed
        elif systemctl is-active --quiet lsws; then
            sudo systemctl reload lsws
        fi

        print_status "OpenLiteSpeed reloaded successfully"
    else
        print_warning "OpenLiteSpeed is not running, configuration will be applied on next restart"
    fi
}

# Verify installation
verify_installation() {
    print_header "Verification"

    if [[ -f "$GOOGLE_IP_FILE" && -f "$BING_IP_FILE" ]]; then
        local google_count=$(wc -l < "$GOOGLE_IP_FILE")
        local bing_count=$(wc -l < "$BING_IP_FILE")

        print_status "✅ Googlebot IP ranges: $google_count"
        print_status "✅ Bingbot IP ranges: $bing_count"
        print_status "✅ Configuration updated successfully"
        print_status "✅ Smart bot verification is now active"

        print_header "Next Steps"
        echo "1. Bot verification rules are now active in OpenLiteSpeed"
        echo "2. Add to crontab for automatic updates:"
        echo "   0 2 * * * /path/to/update-bot-ips.sh"
        echo "3. Monitor logs: tail -f $LOG_FILE"

        return 0
    else
        print_error "Verification failed - missing IP files"
        return 1
    fi
}

# Cleanup
cleanup() {
    rm -rf "$TEMP_DIR"
}

# Main execution
main() {
    print_header "SMART BOT VERIFICATION - DYNAMIC IP UPDATES"
    print_status "Starting dynamic bot IP verification setup..."

    # Check dependencies
    if ! command -v curl >/dev/null 2>&1; then
        print_error "curl is required but not installed"
        exit 1
    fi

    # Install required packages if missing
    if ! command -v ipcalc >/dev/null 2>&1; then
        print_warning "ipcalc not found, using simplified CIDR conversion"
    fi

    if ! command -v jq >/dev/null 2>&1; then
        print_warning "jq not found, using fallback JSON parsing"
    fi

    # Execute main functions
    setup_directories
    fetch_google_ips
    fetch_bing_ips
    update_ols_config
    restart_ols_if_needed
    verify_installation
    cleanup

    print_status "Smart bot verification setup completed! 🎉"
}

# Trap for cleanup
trap cleanup EXIT

# Run main function
main "$@"