#!/bin/bash
#
# WordPress Security Installer for OpenLiteSpeed + CyberPanel
# Version 1.0
# Installs security rules for all WordPress sites on CyberPanel
#
# Author: WordPress Security with OpenLiteSpeed on CyberPanel
# License: MIT

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly CONFIG_DIR="/usr/local/lsws/conf"
readonly SECURITY_CONF_DIR="/usr/local/lsws/conf.d"
readonly SECURITY_INCLUDE="wordpress-security.conf"
readonly BACKUP_DIR="/var/backups/wp-security-cyberpanel"
readonly LOG_FILE="/var/log/wp-security-cyberpanel-install.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Progress tracking
TOTAL_STEPS=7
CURRENT_STEP=0

# Output functions
step() {
    ((CURRENT_STEP++))
    echo -e "\n${BLUE}📍 Step $CURRENT_STEP/$TOTAL_STEPS: $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Progress bar
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))

    printf "\r["
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $((width - filled)) | tr ' ' '░'
    printf "] %d%%" $percentage
}

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Check if CyberPanel is installed
check_cyberpanel() {
    if [[ ! -d "/usr/local/lsws" ]]; then
        error "OpenLiteSpeed not found. This script requires OpenLiteSpeed/CyberPanel."
        exit 1
    fi

    if [[ ! -d "/home" ]]; then
        error "CyberPanel home directory not found. This script requires CyberPanel."
        exit 1
    fi

    success "OpenLiteSpeed and CyberPanel detected"
}

# Create necessary directories
init_directories() {
    step "Initializing directories"

    mkdir -p "$SECURITY_CONF_DIR" "$BACKUP_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"

    # Set permissions
    chmod 755 "$SECURITY_CONF_DIR"
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"

    success "Directories initialized"
    log "Created security configuration directory: $SECURITY_CONF_DIR"
}

# Install security configuration file
install_security_config() {
    step "Installing security configuration"

    # Get script directory
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_source="$script_dir/../configs/$SECURITY_INCLUDE"

    if [[ ! -f "$config_source" ]]; then
        error "Security configuration file not found: $config_source"
        exit 1
    fi

    # Copy security configuration
    cp "$config_source" "$SECURITY_CONF_DIR/$SECURITY_INCLUDE"
    chmod 644 "$SECURITY_CONF_DIR/$SECURITY_INCLUDE"

    success "Security configuration installed"
    log "Installed security configuration to: $SECURITY_CONF_DIR/$SECURITY_INCLUDE"
}

# Backup existing configurations
backup_configs() {
    step "Creating configuration backups"

    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/lsws-backup-$backup_timestamp"

    mkdir -p "$backup_path"

    # Backup main LSWS configuration
    if [[ -f "$CONFIG_DIR/httpd_config.xml" ]]; then
        cp "$CONFIG_DIR/httpd_config.xml" "$backup_path/"
        log "Backed up httpd_config.xml"
    fi

    # Backup virtual host configurations
    if [[ -d "$CONFIG_DIR/vhosts" ]]; then
        cp -r "$CONFIG_DIR/vhosts" "$backup_path/"
        log "Backed up vhosts directory"
    fi

    success "Configuration backups created"
    info "Backup location: $backup_path"
}

# Find all WordPress sites in CyberPanel
find_wordpress_sites() {
    local sites=()

    while IFS= read -r -d '' user_dir; do
        # Find all domains under this user
        while IFS= read -r -d '' domain_dir; do
            local domain=$(basename "$domain_dir")
            local wp_config="$domain_dir/public_html/wp-config.php"

            if [[ -f "$wp_config" ]]; then
                sites+=("$domain:$domain_dir/public_html:$wp_config")
                log "Found WordPress site: $domain"
            fi
        done < <(find "$user_dir" -maxdepth 1 -type d -name "*.*" -print0 2>/dev/null)
    done < <(find /home -maxdepth 1 -type d ! -name "home" -print0 2>/dev/null)

    printf '%s\n' "${sites[@]}"
}

# Update virtual host configurations
update_vhosts() {
    step "Updating virtual host configurations"

    local sites=()
    while IFS= read -r site; do
        sites+=("$site")
    done < <(find_wordpress_sites)

    if [[ ${#sites[@]} -eq 0 ]]; then
        warn "No WordPress sites found"
        return 0
    fi

    info "Found ${#sites[@]} WordPress site(s)"

    local updated=0
    local total=${#sites[@]}

    for site in "${sites[@]}"; do
        IFS=':' read -r domain docroot wp_config <<< "$site"

        # Update progress
        show_progress $((updated + 1)) $total

        # Find virtual host configuration file
        local vhost_config=""
        if [[ -f "$CONFIG_DIR/vhosts/$domain/vhconf.conf" ]]; then
            vhost_config="$CONFIG_DIR/vhosts/$domain/vhconf.conf"
        elif [[ -f "$CONFIG_DIR/vhosts/$domain/$domain.conf" ]]; then
            vhost_config="$CONFIG_DIR/vhosts/$domain/$domain.conf"
        else
            # Search for vhost config
            vhost_config=$(find "$CONFIG_DIR/vhosts" -name "*$domain*" -type f 2>/dev/null | head -1)
        fi

        if [[ -n "$vhost_config" && -f "$vhost_config" ]]; then
            # Backup vhost config
            cp "$vhost_config" "$vhost_config.bak-$(date +%s)"

            # Check if security include already exists
            if grep -q "$SECURITY_INCLUDE" "$vhost_config"; then
                log "Security include already exists for $domain"
            else
                # Add security include before </virtualHost> closing tag
                # Using sed to insert before the closing virtualHost tag
                sed -i "/<\/virtualHost>/i\\    # WordPress Security Include\\n    include \/usr\/local\/lsws\/conf.d\/$SECURITY_INCLUDE" "$vhost_config"
                log "Added security include to $domain"
            fi

            ((updated++))
        else
            warn "Virtual host config not found for $domain"
            log "Missing vhost config for $domain"
        fi
    done

    echo # New line after progress bar
    success "Updated $updated virtual host configurations"
}

# Create .htaccess file for additional protection
create_htaccess() {
    step "Creating additional .htaccess protections"

    local sites=()
    while IFS= read -r site; do
        sites+=("$site")
    done < <(find_wordpress_sites)

    local created=0

    for site in "${sites[@]}"; do
        IFS=':' read -r domain docroot wp_config <<< "$site"

        local htaccess_file="$docroot/.htaccess"

        # Backup existing .htaccess
        if [[ -f "$htaccess_file" ]]; then
            cp "$htaccess_file" "$htaccess_file.bak-$(date +%s)"
        fi

        # Check if WordPress section already exists
        if grep -q "# WordPress Security Rules" "$htaccess_file" 2>/dev/null; then
            log "Security rules already exist in .htaccess for $domain"
            continue
        fi

        # Add security rules to .htaccess
        cat >> "$htaccess_file" << 'EOF'

# WordPress Security Rules - Added by WordPress Security Installer
# These rules provide additional protection at the directory level

# Block wp-config.php
<Files wp-config.php>
    Require all denied
</Files>

# Block xmlrpc.php
<Files xmlrpc.php>
    Require all denied
</Files>

# Block PHP in uploads
<Directory wp-content/uploads>
    <FilesMatch "\.php$">
        Require all denied
    </FilesMatch>
</Directory>

# Block sensitive files
<FilesMatch "\.(bak|backup|old|orig|sql|log)$">
    Require all denied
</FilesMatch>

# End WordPress Security Rules
EOF

        ((created++))
        log "Created .htaccess rules for $domain"
    done

    success "Created additional .htaccess rules for $created sites"
}

# Restart OpenLiteSpeed
restart_lsws() {
    step "Restarting OpenLiteSpeed"

    # Test configuration first
    if /usr/local/lsws/bin/lswsctrl -t >/dev/null 2>&1; then
        # Graceful restart
        /usr/local/lsws/bin/lswsctrl -r
        success "OpenLiteSpeed restarted successfully"
        log "OpenLiteSpeed service restarted"
    else
        error "OpenLiteSpeed configuration test failed"
        error "Please check the configuration manually"
        error "Run: /usr/local/lsws/bin/lswsctrl -t"
        exit 1
    fi
}

# Create nightly update script
create_nightly_script() {
    step "Setting up automatic updates"

    local nightly_script="/usr/local/sbin/wp-security-nightly-cyberpanel.sh"
    local update_script="/usr/local/share/wp-security/update-vhosts-cyberpanel.sh"

    # Create main wrapper script
    cat > "$nightly_script" << 'EOF'
#!/bin/bash
#
# WordPress Security Nightly Update for CyberPanel
# Runs nightly to protect new WordPress sites
#

LOG_FILE="/var/log/wp-security-cyberpanel-nightly.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "$DATE - Starting WordPress security nightly update" >> "$LOG_FILE"

# Run the actual update script
if [[ -f "/usr/local/share/wp-security/update-vhosts-cyberpanel.sh" ]]; then
    /usr/local/share/wp-security/update-vhosts-cyberpanel.sh >> "$LOG_FILE" 2>&1

    # Restart OpenLiteSpeed if changes were made
    if [[ $? -eq 0 ]]; then
        /usr/local/lsws/bin/lswsctrl -r >> "$LOG_FILE" 2>&1
        echo "$DATE - OpenLiteSpeed restarted" >> "$LOG_FILE"
    fi
else
    echo "$DATE - ERROR: Update script not found" >> "$LOG_FILE"
    exit 1
fi

echo "$DATE - WordPress security nightly update completed" >> "$LOG_FILE"

# Clean old backups (keep last 7 days)
find /var/backups/wp-security-cyberpanel -name "lsws-backup-*" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
EOF

    # Create the actual update script
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cat > "$update_script" << EOF
#!/bin/bash
# Update script for new WordPress sites

# Call the install script in update mode
"$script_dir/install.sh" --update-only
EOF

    chmod +x "$nightly_script" "$update_script"

    # Add to cron
    (crontab -l 2>/dev/null | grep -v "wp-security-nightly"; echo "30 2 * * * $nightly_script") | crontab -

    success "Nightly updates configured (runs at 02:30)"
    log "Created nightly update script: $nightly_script"
}

# Verify installation
verify_installation() {
    step "Verifying installation"

    # Check if security config exists
    if [[ ! -f "$SECURITY_CONF_DIR/$SECURITY_INCLUDE" ]]; then
        error "Security configuration file not found"
        return 1
    fi

    # Check if vhosts have been updated
    local updated_vhosts=0
    while IFS= read -r -d '' vhost_file; do
        if grep -q "$SECURITY_INCLUDE" "$vhost_file"; then
            ((updated_vhosts++))
        fi
    done < <(find "$CONFIG_DIR/vhosts" -name "*.conf" -type f -print0 2>/dev/null)

    if [[ $updated_vhosts -gt 0 ]]; then
        success "Security rules are active in $updated_vhosts virtual hosts"
    else
        warn "No virtual hosts found with security rules"
    fi

    # Test OpenLiteSpeed configuration
    if /usr/local/lsws/bin/lswsctrl -t >/dev/null 2>&1; then
        success "OpenLiteSpeed configuration is valid"
    else
        error "OpenLiteSpeed configuration test failed"
        return 1
    fi

    success "Installation verification completed"
}

# Show completion message
show_completion() {
    echo -e "\n${GREEN}🎉 WordPress Security Installation Completed!${NC}"
    echo
    echo -e "${BLUE}What was installed:${NC}"
    echo "• Security configuration file with comprehensive protection rules"
    echo "• Virtual host includes for all WordPress sites"
    echo "• Additional .htaccess protections"
    echo "• Nightly automatic updates for new sites"
    echo "• Configuration backups in $BACKUP_DIR"
    echo
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Test your site security:"
    echo "   wget -qO- https://raw.githubusercontent.com/hienhoceo-dpsmedia/wordpress-security-with-nginx-on-fastpanel/master/openlitespeed-cyberpanel/scripts/test-security.sh | bash -s your-domain.com"
    echo
    echo "2. Check logs:"
    echo "   Installation log: $LOG_FILE"
    echo "   Nightly update log: /var/log/wp-security-cyberpanel-nightly.log"
    echo
    echo "3. Monitor OpenLiteSpeed:"
    echo "   /usr/local/lsws/bin/lswsctrl -t  # Test configuration"
    echo "   /usr/local/lsws/bin/lswsctrl -r  # Restart service"
    echo
    echo -e "${YELLOW}⚠️  Important:${NC}"
    echo "• Configuration backups were created before any changes"
    echo "• If you encounter issues, restore from: $BACKUP_DIR"
    echo "• Nightly updates will automatically protect new WordPress sites"
    echo
}

# Main installation function
main() {
    echo -e "${BLUE}🛡️ WordPress Security Installer for OpenLiteSpeed + CyberPanel${NC}"
    echo -e "${BLUE}========================================================${NC}"

    # Handle command line arguments
    local update_only=false
    if [[ "${1:-}" == "--update-only" ]]; then
        update_only=true
        TOTAL_STEPS=3
        CURRENT_STEP=0
        echo -e "${YELLOW}Running in update-only mode${NC}"
    fi

    # Run installation steps
    check_root
    check_cyberpanel

    if [[ "$update_only" == false ]]; then
        init_directories
        install_security_config
        backup_configs
    fi

    update_vhosts
    create_htaccess
    restart_lsws

    if [[ "$update_only" == false ]]; then
        setup_smart_bot_verification
        create_nightly_script
        verify_installation
        show_completion
    else
        success "Update completed"
    fi
}

# Setup Smart Bot Verification
setup_smart_bot_verification() {
    step "Setting up Smart Bot Verification"

    local bot_script_dir="/usr/local/bin"
    local bot_script_name="update-bot-ips"
    local bot_script_path="$bot_script_dir/$bot_script_name.sh"

    # Copy bot verification script
    if [[ -f "$SCRIPT_DIR/update-bot-ips.sh" ]]; then
        info "Installing smart bot verification script..."
        sudo cp "$SCRIPT_DIR/update-bot-ips.sh" "$bot_script_path"
        sudo chmod 755 "$bot_script_path"

        # Install dependencies if missing
        if ! command -v curl >/dev/null 2>&1; then
            warn "Installing curl for bot IP updates..."
            if command -v apt >/dev/null 2>&1; then
                sudo apt update && sudo apt install -y curl
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y curl
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y curl
            fi
        fi

        # Install ipcalc for better CIDR handling
        if ! command -v ipcalc >/dev/null 2>&1; then
            warn "Installing ipcalc for improved IP range processing..."
            if command -v apt >/dev/null 2>&1; then
                sudo apt install -y ipcalc
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y ipcalc
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y ipcalc
            fi
        fi

        # Install jq for JSON parsing
        if ! command -v jq >/dev/null 2>&1; then
            warn "Installing jq for JSON parsing..."
            if command -v apt >/dev/null 2>&1; then
                sudo apt install -y jq
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y jq
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y jq
            fi
        fi

        # Run initial bot IP update
        info "Running initial bot IP verification setup..."
        if sudo "$bot_script_path"; then
            success "Smart bot verification configured successfully"
        else
            warn "Bot IP update failed, but security rules are still active"
        fi

        # Add cron job for automatic updates
        info "Setting up automatic bot IP updates..."
        local cron_entry="0 2 * * * $bot_script_path >> /var/log/bot-ip-updates.log 2>&1"

        # Add to crontab if not already present
        if ! sudo crontab -l 2>/dev/null | grep -q "$bot_script_name"; then
            (sudo crontab -l 2>/dev/null; echo "$cron_entry") | sudo crontab -
            success "Cron job added for automatic bot IP updates"
        else
            info "Cron job already exists"
        fi

        success "Smart bot verification setup completed"
        info "• Googlebot and Bingbot IPs will be automatically verified"
        info "• Fake search engine bots will be blocked"
        info "• IP ranges update daily at 2:00 AM"
        info "• Monitor logs: tail -f /var/log/bot-ip-updates.log"

    else
        warn "Smart bot verification script not found, skipping advanced bot protection"
        warn "Basic bot protection is still active"
    fi
}

# Trap errors
trap 'error "Script failed at line $LINENO"' ERR

# Run main function with all arguments
main "$@"