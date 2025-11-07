#!/bin/bash
#
# WordPress Security Test Script for OpenLiteSpeed + CyberPanel
# Tests security protections by simulating various attacks
#
# Author: WordPress Security with OpenLiteSpeed on CyberPanel
# License: MIT

set -euo pipefail

# Configuration
readonly DOMAIN="${1:-}"
readonly VERBOSE="${2:-false}"
readonly SKIP_CDN="${3:-false}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Test results counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Attack patterns
readonly ATTACK_PATTERNS=(
    "/wp-config.php"
    "/wp-config-sample.php"
    "/xmlrpc.php"
    "/readme.html"
    "/license.txt"
    "/wp-admin/install.php"
    "/wp-admin/upgrade.php"
    "/wp-content/debug.log"
    "/wp-content/uploads/test.php"
    "/wp-content/uploads/shell.php"
    "/wp-content/plugins/evil.php"
    "/wp-content/themes/malicious.php"
    "/wp-includes/backdoor.php"
    "/backup.sql"
    "/site.bak"
    "/config.backup"
    "webshell.php"
    "timthumb.php"
    "/wp-content/uploads/archive.zip"
    "/.git/config"
    "/.env"
    "/.htaccess"
    "script.py"
    "exec.exe"
    "/admin/"
    "/wp-admin/admin-ajax.php?action=revslider_show_image&img=../wp-config.php"
    "/?eval(base64_decode('malicious'))"
    "/?union select * from wp_users"
    "/etc/passwd"
    "/proc/self/environ"
)

# Malicious user agents
readonly MALICIOUS_UA=(
    "sqlmap/1.0"
    "nikto/2.1"
    "nmap"
    "w3af"
    "acunetix"
    "burp"
    "python-urllib"
    "curl"
    "java"
)

# Output functions
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[PASS]${NC} $*"; ((TESTS_PASSED++)); }
error() { echo -e "${RED}[FAIL]${NC} $*"; ((TESTS_FAILED++)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# Show test summary
show_summary() {
    echo -e "\n${BLUE}=== Test Results Summary ===${NC}"
    echo -e "Total tests: $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}🎉 All security tests passed! Your site is well protected.${NC}"
        return 0
    else
        echo -e "\n${RED}❌ Some security tests failed. Please review your configuration.${NC}"
        return 1
    fi
}

# Make HTTP request and check response
test_request() {
    local url="$1"
    local expected_status="$2"
    local description="$3"
    local user_agent="${4:-Mozilla/5.0 (compatible; SecurityTest/1.0)}"

    ((TESTS_TOTAL++))

    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${YELLOW}Testing: $description${NC}"
        echo "URL: $url"
        echo "Expected: HTTP $expected_status"
    fi

    local response_code=""
    local response_body=""

    # Make request with curl
    if [[ "$SKIP_CDN" == "true" ]]; then
        # Resolve domain to local IP to bypass CDN
        local domain=$(echo "$url" | sed 's|https\?://||' | cut -d'/' -f1)
        local local_ip=$(hostname -I | awk '{print $1}')
        response_code=$(curl -s -w "%{http_code}" -o /dev/null -H "User-Agent: $user_agent" \
            --resolve "$domain:443:$local_ip" --max-time 10 --connect-timeout 5 "$url" 2>/dev/null || echo "000")
    else
        response_code=$(curl -s -w "%{http_code}" -o /dev/null -H "User-Agent: $user_agent" \
            --max-time 10 --connect-timeout 5 "$url" 2>/dev/null || echo "000")
    fi

    # Check response
    case "$expected_status" in
        "403")
            if [[ "$response_code" == "403" ]]; then
                success "$description - HTTP 403 (Forbidden)"
                return 0
            elif [[ "$response_code" == "404" ]]; then
                success "$description - HTTP 404 (Not Found)"
                return 0
            else
                error "$description - Got HTTP $response_code (expected 403/404)"
                return 1
            fi
            ;;
        "200")
            if [[ "$response_code" == "200" ]]; then
                success "$description - HTTP 200 (OK)"
                return 0
            else
                error "$description - Got HTTP $response_code (expected 200)"
                return 1
            fi
            ;;
        "405")
            if [[ "$response_code" == "405" ]]; then
                success "$description - HTTP 405 (Method Not Allowed)"
                return 0
            else
                error "$description - Got HTTP $response_code (expected 405)"
                return 1
            fi
            ;;
        *)
            error "$description - Invalid expected status: $expected_status"
            return 1
            ;;
    esac
}

# Test file access protection
test_file_access() {
    info "Testing file access protection..."

    local base_url
    if [[ "$DOMAIN" == *"://"* ]]; then
        base_url="$DOMAIN"
    else
        base_url="https://$DOMAIN"
    fi

    # Test each attack pattern
    for pattern in "${ATTACK_PATTERNS[@]}"; do
        test_request "$base_url$pattern" "403" "Block access to: $pattern"
    done
}

# Test malicious user agents
test_user_agents() {
    info "Testing malicious user agent blocking..."

    local base_url
    if [[ "$DOMAIN" == *"://"* ]]; then
        base_url="$DOMAIN"
    else
        base_url="https://$DOMAIN"
    fi

    # Test each malicious user agent
    for ua in "${MALICIOUS_UA[@]}"; do
        test_request "$base_url/" "403" "Block user agent: $ua" "$ua"
    done
}

# Test HTTP methods
test_http_methods() {
    info "Testing HTTP method restrictions..."

    local base_url
    if [[ "$DOMAIN" == *"://"* ]]; then
        base_url="$DOMAIN"
    else
        base_url="https://$DOMAIN"
    fi

    local dangerous_methods=("TRACE" "TRACK" "CONNECT" "DEBUG" "MOVE")

    for method in "${dangerous_methods[@]}"; do
        ((TESTS_TOTAL++))

        if [[ "$VERBOSE" == "true" ]]; then
            echo -e "${YELLOW}Testing: Block HTTP $method method${NC}"
        fi

        # Use curl to test HTTP method
        local response_code
        response_code=$(curl -s -w "%{http_code}" -o /dev/null -X "$method" \
            --max-time 5 --connect-timeout 3 "$base_url/" 2>/dev/null || echo "000")

        if [[ "$response_code" == "405" || "$response_code" == "501" || "$response_code" == "400" ]]; then
            success "Block HTTP $method method - HTTP $response_code"
        else
            error "Block HTTP $method method - Got HTTP $response_code (expected 405/501/400)"
            ((TESTS_FAILED++))
        fi
    done
}

# Test query string filtering
test_query_strings() {
    info "Testing query string filtering..."

    local base_url
    if [[ "$DOMAIN" == *"://"* ]]; then
        base_url="$DOMAIN"
    else
        base_url="https://$DOMAIN"
    fi

    local malicious_queries=(
        "?eval(base64_decode('test'))"
        "?union select * from wp_users"
        "?GLOBALS['_']"
        "?REQUEST['test']"
        "?<script>alert('xss')</script>"
        "?etc/passwd"
        "?127.0.0.1"
        "?javascript:alert(1)"
    )

    for query in "${malicious_queries[@]}"; do
        test_request "$base_url/$query" "403" "Block query string: $query"
    done
}

# Test normal functionality
test_normal_functionality() {
    info "Testing normal site functionality..."

    local base_url
    if [[ "$DOMAIN" == *"://"* ]]; then
        base_url="$DOMAIN"
    else
        base_url="https://$DOMAIN"
    fi

    # Test homepage
    test_request "$base_url/" "200" "Homepage access"

    # Test WordPress login (should work)
    test_request "$base_url/wp-login.php" "200" "WordPress login page"

    # Test WordPress admin (should redirect or work)
    test_request "$base_url/wp-admin/" "200" "WordPress admin area"

    # Test CSS/JS files (should work)
    test_request "$base_url/wp-includes/css/dashicons.min.css" "200" "WordPress CSS files"
}

# Test OpenLiteSpeed specific features
test_openlitespeed_features() {
    info "Testing OpenLiteSpeed specific protections..."

    local base_url
    if [[ "$DOMAIN" == *"://"* ]]; then
        base_url="$DOMAIN"
    else
        base_url="https://$DOMAIN"
    fi

    # Test if security headers are present
    ((TESTS_TOTAL++))

    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${YELLOW}Testing: Security headers${NC}"
    fi

    local headers=$(curl -s -I -H "User-Agent: Mozilla/5.0" --max-time 5 "$base_url/" 2>/dev/null || echo "")

    local security_headers_found=0

    if echo "$headers" | grep -qi "X-Content-Type-Options"; then
        info "✓ X-Content-Type-Options header found"
        ((security_headers_found++))
    fi

    if echo "$headers" | grep -qi "X-Frame-Options"; then
        info "✓ X-Frame-Options header found"
        ((security_headers_found++))
    fi

    if echo "$headers" | grep -qi "X-XSS-Protection"; then
        info "✓ X-XSS-Protection header found"
        ((security_headers_found++))
    fi

    if [[ $security_headers_found -gt 0 ]]; then
        success "Security headers present ($security_headers_found found)"
    else
        warn "No security headers detected (this may be normal)"
        ((TESTS_TOTAL--)) # Don't count this as a failure
    fi
}

# Show help
show_help() {
    cat << EOF
WordPress Security Test Suite for OpenLiteSpeed + CyberPanel

USAGE:
    $0 <DOMAIN> [OPTIONS]

ARGUMENTS:
    DOMAIN              Domain name to test (required)

OPTIONS:
    --verbose           Show detailed test output
    --skip-cdn          Bypass CDN by resolving to local IP
    --help              Show this help message

EXAMPLES:
    $0 example.com
    $0 https://example.com --verbose
    $0 example.com --skip-cdn

TESTS PERFORMED:
    • File access protection (wp-config.php, uploads, etc.)
    • Malicious user agent blocking
    • HTTP method restrictions
    • Query string filtering
    • Normal functionality verification
    • OpenLiteSpeed security headers

EXPECTED RESULTS:
    • Sensitive files → HTTP 403/404 (blocked)
    • Normal pages → HTTP 200 (allowed)
    • Malicious requests → HTTP 403 (blocked)

For more information, see the project documentation.
EOF
}

# Main function
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                VERBOSE="true"
                shift
                ;;
            --skip-cdn)
                SKIP_CDN="true"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                if [[ -z "$DOMAIN" ]]; then
                    DOMAIN="$1"
                fi
                shift
                ;;
        esac
    done

    # Check if domain is provided
    if [[ -z "$DOMAIN" ]]; then
        error "Domain name is required"
        echo
        show_help
        exit 1
    fi

    echo -e "${BLUE}🛡️ WordPress Security Test Suite${NC}"
    echo -e "${BLUE}OpenLiteSpeed + CyberPanel${NC}"
    echo -e "${BLUE}=============================${NC}"
    echo -e "Testing domain: ${YELLOW}$DOMAIN${NC}"
    echo

    # Run tests
    test_normal_functionality
    test_file_access
    test_user_agents
    test_http_methods
    test_query_strings
    test_openlitespeed_features

    # Show summary
    show_summary
}

# Execute main function with all arguments
main "$@"