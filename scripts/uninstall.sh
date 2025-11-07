#!/bin/bash
#
# WordPress Security Uninstaller for OpenLiteSpeed + CyberPanel
# Removes all security rules and configurations
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
readonly LOG_FILE="/var/log/wp-security-cyberpanel-uninstall.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Output functions
step() {
    echo -e "\n${BLUE}📍 $1${NC}"
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

# Create backup before removal
create_backup() {
    step "Creating final backup"

    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/uninstall-backup-$backup_timestamp"

    mkdir -p "$backup_path"

    # Backup current security configuration
    if [[ -f "$SECURITY_CONF_DIR/$SECURITY_INCLUDE" ]]; then
        cp "$SECURITY_CONF_DIR/$SECURITY_INCLUDE" "$backup_path/"
        log "Backed up security configuration"
    fi

    # Backup current virtual hosts
    if [[ -d "$CONFIG_DIR/vhosts" ]]; then
        cp -r "$CONFIG_DIR/vhosts" "$backup_path/"
        log "Backed up virtual hosts"
    fi

    # Backup OpenLiteSpeed main config
    if [[ -f "$CONFIG_DIR/httpd_config.xml" ]]; then
        cp "$CONFIG_DIR/httpd_config.xml" "$backup_path/"
        log "Backed up OpenLiteSpeed main config"
    fi

    success "Final backup created: $backup_path"
}

# Remove security configuration file
remove_security_config() {
    step "Removing security configuration"

    if [[ -f "$SECURITY_CONF_DIR/$SECURITY_INCLUDE" ]]; then
        rm -f "$SECURITY_CONF_DIR/$SECURITY_INCLUDE"
        success "Security configuration file removed"
        log "Removed: $SECURITY_CONF_DIR/$SECURITY_INCLUDE"
    else
        warn "Security configuration file not found"
    fi
}

# Remove security includes from virtual hosts
remove_vhost_includes() {
    step "Removing security includes from virtual hosts"

    local updated=0
    local total=0

    while IFS= read -r -d '' vhost_file; do
        ((total++))

        if [[ -f "$vhost_file" ]]; then
            # Check if it contains our security include
            if grep -q "$SECURITY_INCLUDE" "$vhost_file"; then
                # Create backup
                cp "$vhost_file" "$vhost_file.uninstall-backup-$(date +%s)"

                # Remove security include lines
                sed -i "/# WordPress Security Include/d" "$vhost_file"
                sed -i "/include \/usr\/local\/lsws\/conf.d\/$SECURITY_INCLUDE/d" "$vhost_file"

                ((updated++))
                log "Removed security include from: $vhost_file"
            fi
        fi
    done < <(find "$CONFIG_DIR/vhosts" -name "*.conf" -type f -print0 2>/dev/null)

    if [[ $updated -gt 0 ]]; then
        success "Removed security includes from $updated virtual host files"
    else
        warn "No virtual hosts contained security includes"
    fi

    info "Total virtual hosts checked: $total"
}

# Remove .htaccess security rules
remove_htaccess_rules() {
    step "Removing .htaccess security rules"

    local removed=0
    local sites=()

    # Find WordPress sites
    while IFS= read -r -d '' user_dir; do
        while IFS= read -r -d '' domain_dir; do
            local wp_config="$domain_dir/public_html/wp-config.php"
            local htaccess="$domain_dir/public_html/.htaccess"

            if [[ -f "$wp_config" && -f "$htaccess" ]]; then
                sites+=("$htaccess")
            fi
        done < <(find "$user_dir" -maxdepth 1 -type d -name "*.*" -print0 2>/dev/null)
    done < <(find /home -maxdepth 1 -type d ! -name "home" -print0 2>/dev/null)

    for htaccess in "${sites[@]}"; do
        if [[ -f "$htaccess" ]]; then
            # Check if it contains our security rules
            if grep -q "# WordPress Security Rules" "$htaccess"; then
                # Create backup
                cp "$htaccess" "$htaccess.uninstall-backup-$(date +%s)"

                # Remove security rules (between the markers)
                sed -i '/# WordPress Security Rules - Added by WordPress Security Installer/,/# End WordPress Security Rules/d' "$htaccess"

                ((removed++))
                log "Removed security rules from: $htaccess"
            fi
        fi
    done

    if [[ $removed -gt 0 ]]; then
        success "Removed security rules from $removed .htaccess files"
    else
        warn "No .htaccess files contained security rules"
    fi
}

# Remove nightly update cron
remove_cron() {
    step "Removing nightly update cron"

    # Remove cron entry
    if crontab -l 2>/dev/null | grep -q "wp-security-nightly-cyberpanel"; then
        (crontab -l 2>/dev/null | grep -v "wp-security-nightly-cyberpanel") | crontab -
        success "Removed nightly update cron entry"
        log "Removed cron job for automatic updates"
    else
        warn "No nightly update cron entry found"
    fi

    # Remove cron scripts
    if [[ -f "/usr/local/sbin/wp-security-nightly-cyberpanel.sh" ]]; then
        rm -f "/usr/local/sbin/wp-security-nightly-cyberpanel.sh"
        log "Removed nightly update script"
    fi

    if [[ -f "/usr/local/share/wp-security/update-vhosts-cyberpanel.sh" ]]; then
        rm -f "/usr/local/share/wp-security/update-vhosts-cyberpanel.sh"
        log "Removed vhost update script"
    fi
}

# Restart OpenLiteSpeed
restart_lsws() {
    step "Restarting OpenLiteSpeed"

    # Test configuration first
    if /usr/local/lsws/bin/lswsctrl -t >/dev/null 2>&1; then
        # Graceful restart
        /usr/local/lsws/bin/lswsctrl -r
        success "OpenLiteSpeed restarted successfully"
        log "OpenLiteSpeed service restarted after uninstall"
    else
        error "OpenLiteSpeed configuration test failed"
        error "Please check the configuration manually"
        error "Run: /usr/local/lsws/bin/lswsctrl -t"
        exit 1
    fi
}

# Verify removal
verify_removal() {
    step "Verifying removal"

    local issues=0

    # Check if security config still exists
    if [[ -f "$SECURITY_CONF_DIR/$SECURITY_INCLUDE" ]]; then
        error "Security configuration file still exists"
        ((issues++))
    else
        success "Security configuration file removed"
    fi

    # Check if any vhosts still have security includes
    local vhosts_with_includes=0
    while IFS= read -r -d '' vhost_file; do
        if grep -q "$SECURITY_INCLUDE" "$vhost_file" 2>/dev/null; then
            ((vhosts_with_includes++))
            warn "Security include still found in: $(basename "$vhost_file")"
        fi
    done < <(find "$CONFIG_DIR/vhosts" -name "*.conf" -type f -print0 2>/dev/null)

    if [[ $vhosts_with_includes -eq 0 ]]; then
        success "All security includes removed from virtual hosts"
    else
        warn "Security includes still found in $vhosts_with_includes virtual hosts"
    fi

    # Check if cron is removed
    if crontab -l 2>/dev/null | grep -q "wp-security-nightly-cyberpanel"; then
        error "Cron entry still exists"
        ((issues++))
    else
        success "Cron entry removed"
    fi

    if [[ $issues -eq 0 ]]; then
        success "Uninstall verification completed successfully"
        return 0
    else
        error "Uninstall verification found $issues issue(s)"
        return 1
    fi
}

# Show completion message
show_completion() {
    echo -e "\n${GREEN}🎉 WordPress Security Uninstall Completed!${NC}"
    echo
    echo -e "${BLUE}What was removed:${NC}"
    echo "• Security configuration file ($SECURITY_INCLUDE)"
    echo "• Security includes from all virtual hosts"
    echo "• Additional .htaccess protection rules"
    echo "• Nightly automatic update cron job"
    echo "• Update scripts"
    echo
    echo -e "${BLUE}What was preserved:${NC}"
    echo "• All backup files in $BACKUP_DIR"
    echo "• Your WordPress sites and data"
    echo "• Original OpenLiteSpeed configuration"
    echo
    echo -e "${BLUE}Available backups:${NC}"
    if [[ -d "$BACKUP_DIR" ]]; then
        ls -la "$BACKUP_DIR" | grep "backup"
    fi
    echo
    echo -e "${YELLOW}⚠️  Important notes:${NC}"
    echo "• Your WordPress sites are now less protected"
    echo "• Consider installing a replacement security solution"
    echo "• Backups are kept in $BACKUP_DIR for your reference"
    echo "• You can manually restore specific configurations if needed"
    echo
}

# Main uninstall function
main() {
    echo -e "${BLUE}🗑️  WordPress Security Uninstaller${NC}"
    echo -e "${BLUE}OpenLiteSpeed + CyberPanel${NC}"
    echo -e "${BLUE}================================${NC}"

    # Safety confirmation
    echo -e "${YELLOW}This will remove all WordPress security protections from your server.${NC}"
    echo -e "${YELLOW}Your sites will be vulnerable after this process.${NC}"
    echo
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm

    if [[ "$confirm" != "yes" ]]; then
        echo "Uninstall cancelled."
        exit 0
    fi

    # Run uninstall steps
    check_root
    create_backup
    remove_security_config
    remove_vhost_includes
    remove_htaccess_rules
    remove_cron
    restart_lsws

    # Verify and show completion
    if verify_removal; then
        show_completion
    else
        error "Uninstall verification failed. Please check the logs."
        exit 1
    fi
}

# Trap errors
trap 'error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"