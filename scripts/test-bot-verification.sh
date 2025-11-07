#!/bin/bash

# ============================================================
# SMART BOT VERIFICATION TEST SCRIPT
# ============================================================
# Script: test-bot-verification.sh
# Purpose: Test smart bot verification functionality
# Compatible with OpenLiteSpeed + CyberPanel

set -euo pipefail

# Configuration
DOMAIN="${1:-localhost}"
VERBOSE="${2:-false}"
TEST_LOG="/tmp/bot-verification-test.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Logging functions
print_test() {
    ((TOTAL_TESTS++))
    echo -e "${BLUE}[TEST $TOTAL_TESTS]${NC} $1"
}

print_pass() {
    ((PASSED_TESTS++))
    echo -e "${GREEN}✅ PASS${NC} $1"
}

print_fail() {
    ((FAILED_TESTS++))
    echo -e "${RED}❌ FAIL${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Test HTTP request function
test_request() {
    local url="$1"
    local user_agent="$2"
    local expected_code="$3"
    local test_name="$4"

    print_test "$test_name"

    if command -v curl >/dev/null 2>&1; then
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "User-Agent: $user_agent" \
            "$url" 2>/dev/null || echo "000")

        if [[ "$VERBOSE" == "true" ]]; then
            print_info "URL: $url | User-Agent: $user_agent | Expected: $expected_code | Got: $response_code"
        fi

        if [[ "$response_code" == "$expected_code" ]]; then
            print_pass "$test_name - HTTP $response_code (as expected)"
            return 0
        else
            print_fail "$test_name - HTTP $response_code (expected $expected_code)"
            return 1
        fi
    else
        print_fail "curl not available for testing"
        return 1
    fi
}

# Test bot verification components
test_bot_verification() {
    print_info "Testing Smart Bot Verification functionality..."

    # Test URLs
    local base_url="http://$DOMAIN"
    local test_url="$base_url/"

    # Check if site is accessible
    if ! curl -s --max-time 5 "$test_url" >/dev/null 2>&1; then
        print_info "Site not accessible, testing configuration files instead..."
        test_config_files
        return
    fi

    print_info "Testing live site: $base_url"

    # Test 1: Normal browser access
    test_request "$test_url" "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" "200" "Normal browser access"

    # Test 2: Fake Googlebot (should be blocked)
    test_request "$test_url" "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" "403" "Fake Googlebot blocked"

    # Test 3: Fake Bingbot (should be blocked)
    test_request "$test_url" "Mozilla/5.0 (compatible; Bingbot/2.0; +http://www.bing.com/bingbot.htm)" "403" "Fake Bingbot blocked"

    # Test 4: Malicious bot (should be blocked)
    test_request "$test_url" "sqlmap/1.7.5 (automatic SQL injection and database takeover tool)" "403" "Malicious bot blocked"

    # Test 5: Legitimate user agent (should be allowed)
    test_request "$test_url" "WordPress/6.4.3; http://localhost" "200" "WordPress user agent allowed"
}

# Test configuration files
test_config_files() {
    print_info "Testing configuration files..."

    # Test if security config exists
    if [[ -f "/usr/local/lsws/conf.d/wordpress-security.conf" ]]; then
        print_pass "Security configuration file exists"

        # Check for bot verification rules
        if grep -q "SMART BOT VERIFICATION" "/usr/local/lsws/conf.d/wordpress-security.conf"; then
            print_pass "Smart bot verification rules found"
        else
            print_fail "Smart bot verification rules not found"
        fi

        # Check for dynamic include
        if grep -q "IncludeOptional.*bot-verification.conf" "/usr/local/lsws/conf.d/wordpress-security.conf"; then
            print_pass "Dynamic bot verification include found"
        else
            print_info "Dynamic include not found (using static rules)"
        fi
    else
        print_fail "Security configuration file not found"
    fi

    # Test if bot IP files exist
    if [[ -d "/etc/openlitespeed/bot-ips" ]]; then
        print_pass "Bot IP directory exists"

        if [[ -f "/etc/openlitespeed/bot-ips/googlebot-ips.txt" ]]; then
            local google_ips=$(wc -l < "/etc/openlitespeed/bot-ips/googlebot-ips.txt" 2>/dev/null || echo "0")
            print_pass "Googlebot IP file exists ($google_ips ranges)"
        else
            print_info "Googlebot IP file not found (will be created by update script)"
        fi

        if [[ -f "/etc/openlitespeed/bot-ips/bingbot-ips.txt" ]]; then
            local bing_ips=$(wc -l < "/etc/openlitespeed/bot-ips/bingbot-ips.txt" 2>/dev/null || echo "0")
            print_pass "Bingbot IP file exists ($bing_ips ranges)"
        else
            print_info "Bingbot IP file not found (will be created by update script)"
        fi

        if [[ -f "/etc/openlitespeed/bot-ips/bot-verification.conf" ]]; then
            print_pass "Dynamic bot verification configuration exists"
        else
            print_info "Dynamic bot verification configuration not found (will be created by update script)"
        fi
    else
        print_info "Bot IP directory not found (will be created by installation)"
    fi

    # Test if update script exists
    if [[ -f "/usr/local/bin/update-bot-ips.sh" ]]; then
        print_pass "Bot IP update script installed"

        # Check if executable
        if [[ -x "/usr/local/bin/update-bot-ips.sh" ]]; then
            print_pass "Bot IP update script is executable"
        else
            print_fail "Bot IP update script is not executable"
        fi
    else
        print_info "Bot IP update script not installed"
    fi

    # Test cron job
    if sudo crontab -l 2>/dev/null | grep -q "update-bot-ips"; then
        print_pass "Cron job for bot IP updates found"
    else
        print_info "Cron job for bot IP updates not found"
    fi
}

# Test installation dependencies
test_dependencies() {
    print_info "Testing required dependencies..."

    # Test curl
    if command -v curl >/dev/null 2>&1; then
        print_pass "curl is available"
    else
        print_fail "curl is not available (required for bot IP updates)"
    fi

    # Test jq (optional but recommended)
    if command -v jq >/dev/null 2>&1; then
        print_pass "jq is available (for JSON parsing)"
    else
        print_info "jq not found (will use fallback JSON parsing)"
    fi

    # Test ipcalc (optional but recommended)
    if command -v ipcalc >/dev/null 2>&1; then
        print_pass "ipcalc is available (for CIDR processing)"
    else
        print_info "ipcalc not found (will use simplified CIDR processing)"
    fi

    # Test OpenLiteSpeed
    if systemctl is-active --quiet openlitespeed || systemctl is-active --quiet lsws; then
        print_pass "OpenLiteSpeed is running"
    else
        print_fail "OpenLiteSpeed is not running"
    fi
}

# Show final results
show_results() {
    echo -e "\n${BLUE}=== BOT VERIFICATION TEST RESULTS ===${NC}"
    echo -e "Total Tests: $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "\n${GREEN}🎉 All tests passed! Smart bot verification is working correctly.${NC}"
        echo -e "\n${YELLOW}Next steps:${NC}"
        echo "• Monitor logs: tail -f /var/log/bot-ip-updates.log"
        echo "• Manual update: sudo /usr/local/bin/update-bot-ips.sh"
        echo "• Test with: curl -H 'User-Agent: Googlebot/2.1' http://$DOMAIN"
        exit 0
    else
        echo -e "\n${RED}⚠️  Some tests failed. Check the configuration.${NC}"
        echo -e "\n${YELLOW}Troubleshooting:${NC}"
        echo "• Ensure installation completed successfully"
        echo "• Check OpenLiteSpeed configuration"
        echo "• Verify dependencies are installed"
        echo "• Review logs for errors"
        exit 1
    fi
}

# Main function
main() {
    echo -e "${BLUE}=== SMART BOT VERIFICATION TEST ===${NC}"
    echo "Testing domain: $DOMAIN"
    echo "Verbose mode: $VERBOSE"
    echo ""

    test_dependencies
    test_bot_verification
    show_results
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE="true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [domain] [--verbose]"
            echo "  domain     Domain to test (default: localhost)"
            echo "  --verbose  Show detailed test output"
            echo "  --help     Show this help"
            exit 0
            ;;
        *)
            DOMAIN="$1"
            shift
            ;;
    esac
done

# Run main function
main "$@"