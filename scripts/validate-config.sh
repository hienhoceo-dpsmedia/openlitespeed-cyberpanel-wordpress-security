#!/bin/bash

# ============================================================
# OPENLITESPEED CONFIGURATION VALIDATOR
# ============================================================
# Script: validate-config.sh
# Purpose: Validate OpenLiteSpeed configuration for syntax and compatibility
# Compatible with OpenLiteSpeed + CyberPanel

set -euo pipefail

# Configuration
CONFIG_FILE="/usr/local/lsws/conf.d/wordpress-security.conf"
TEST_LOG="/tmp/config-validation.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Check functions
check() {
    ((TOTAL_CHECKS++))
    echo -e "${BLUE}[CHECK $TOTAL_CHECKS]${NC} $1"
}

pass() {
    ((PASSED_CHECKS++))
    echo -e "${GREEN}✅ PASS${NC} $1"
}

fail() {
    ((FAILED_CHECKS++))
    echo -e "${RED}❌ FAIL${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠️  WARNING${NC} $1"
}

info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Validate Apache syntax (basic check)
validate_apache_syntax() {
    check "Apache-style syntax validation"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        fail "Configuration file not found: $CONFIG_FILE"
        return 1
    fi

    # Check for basic syntax errors
    local syntax_errors=0

    # Check for unmatched tags
    if grep -q "<IfModule" "$CONFIG_FILE"; then
        local open_modules=$(grep -c "<IfModule" "$CONFIG_FILE")
        local close_modules=$(grep -c "</IfModule>" "$CONFIG_FILE")

        if [[ $open_modules -ne $close_modules ]]; then
            fail "Unmatched <IfModule> tags: $open_modules open, $close_modules closed"
            ((syntax_errors++))
        else
            pass "All <IfModule> tags are properly matched"
        fi
    fi

    # Check for Files/Directory tags
    if grep -q "<Files" "$CONFIG_FILE"; then
        local open_files=$(grep -c "<Files" "$CONFIG_FILE")
        local close_files=$(grep -c "</Files>" "$CONFIG_FILE")

        if [[ $open_files -ne $close_files ]]; then
            fail "Unmatched <Files> tags: $open_files open, $close_files closed"
            ((syntax_errors++))
        else
            pass "All <Files> tags are properly matched"
        fi
    fi

    # Check for RequireAll tags
    if grep -q "<RequireAll>" "$CONFIG_FILE"; then
        local open_require=$(grep -c "<RequireAll>" "$CONFIG_FILE")
        local close_require=$(grep -c "</RequireAll>" "$CONFIG_FILE")

        if [[ $open_require -ne $close_require ]]; then
            fail "Unmatched <RequireAll> tags: $open_require open, $close_require closed"
            ((syntax_errors++))
        else
            pass "All <RequireAll> tags are properly matched"
        fi
    fi

    # Check for malformed RewriteCond
    if grep -q "RewriteCond" "$CONFIG_FILE"; then
        local malformed=$(grep "RewriteCond.*\[OR\]$" "$CONFIG_FILE" | wc -l)
        if [[ $malformed -gt 0 ]]; then
            fail "Found $malformed RewriteCond lines ending with [OR]"
            ((syntax_errors++))
        else
            pass "No RewriteCond syntax errors found"
        fi
    fi

    if [[ $syntax_errors -eq 0 ]]; then
        pass "Apache syntax validation passed"
        return 0
    else
        fail "Found $syntax_errors syntax errors"
        return 1
    fi
}

# Check OpenLiteSpeed compatibility
check_ols_compatibility() {
    check "OpenLiteSpeed compatibility"

    local compatibility_issues=0

    # Check for IncludeOptional (not supported by OpenLiteSpeed)
    if grep -q "IncludeOptional" "$CONFIG_FILE"; then
        fail "IncludeOptional directive found (not supported by OpenLiteSpeed)"
        ((compatibility_issues++))
    else
        pass "No IncludeOptional directives found"
    fi

    # Check for unsupported Apache modules
    local unsupported_modules=(
        "mod_remoteip"
        "mod_security2"
        "mod_evasive"
        "mod_reqtimeout"
    )

    for module in "${unsupported_modules[@]}"; do
        if grep -q "$module" "$CONFIG_FILE"; then
            warn "Potentially unsupported module: $module"
        fi
    done

    # Check for complex regex patterns that might cause performance issues
    local complex_regex=$(grep -c "RewriteCond.*\{.*\}.*\{.*\}" "$CONFIG_FILE" || echo "0")
    if [[ $complex_regex -gt 5 ]]; then
        warn "Found $complex_regex complex regex patterns (may affect performance)"
    else
        pass "Reasonable number of complex regex patterns"
    fi

    if [[ $compatibility_issues -eq 0 ]]; then
        pass "OpenLiteSpeed compatibility check passed"
        return 0
    else
        fail "Found $compatibility_issues OpenLiteSpeed compatibility issues"
        return 1
    fi
}

# Check CyberPanel integration
check_cyberpanel_integration() {
    check "CyberPanel integration compatibility"

    local integration_issues=0

    # Check if config file is in the right location
    if [[ -f "$CONFIG_FILE" ]]; then
        pass "Configuration file found in CyberPanel location"
    else
        warn "Configuration file not in expected CyberPanel location"
        ((integration_issues++))
    fi

    # Check for hardcoded paths that might not work in CyberPanel
    local hardcoded_paths=(
        "/home/"
        "/var/www/"
        "/usr/local/apache2/"
    )

    for path in "${hardcoded_paths[@]}"; do
        if grep -q "$path" "$CONFIG_FILE"; then
            warn "Hardcoded path found: $path (may not work in all CyberPanel setups)"
        fi
    done

    # Check for dynamic path patterns (good for CyberPanel)
    if grep -q "^.*/wp-content/" "$CONFIG_FILE"; then
        pass "Using dynamic path patterns (CyberPanel compatible)"
    fi

    if [[ $integration_issues -eq 0 ]]; then
        pass "CyberPanel integration check passed"
        return 0
    else
        fail "Found $integration_issues CyberPanel integration issues"
        return 1
    fi
}

# Check SEO safety
check_seo_safety() {
    check "SEO safety validation"

    local seo_issues=0

    # Check for overly broad bot blocking
    if grep -q "User-Agent.*bot" "$CONFIG_FILE" && grep -q "suspicious_bot" "$CONFIG_FILE"; then
        warn "Broad bot blocking patterns found (verify SEO impact)"
        ((seo_issues++))
    else
        pass "No overly broad bot blocking patterns"
    fi

    # Check for legitimate search engine protection
    local protected_engines=0
    if grep -q "googlebot" "$CONFIG_FILE"; then
        ((protected_engines++))
        info "Googlebot protection found"
    fi

    if grep -q "bingbot" "$CONFIG_FILE"; then
        ((protected_engines++))
        info "Bingbot protection found"
    fi

    if [[ $protected_engines -gt 0 ]]; then
        pass "Search engine protection implemented ($protected_engines engines)"
    else
        warn "No specific search engine protection found"
    fi

    # Check for URL parameter blocking that might hurt SEO
    if grep -q "QUERY_STRING.*utm_" "$CONFIG_FILE"; then
        fail "UTM parameter blocking found (will hurt SEO)"
        ((seo_issues++))
    else
        pass "No SEO-critical parameter blocking"
    fi

    if [[ $seo_issues -eq 0 ]]; then
        pass "SEO safety check passed"
        return 0
    else
        fail "Found $seo_issues SEO safety issues"
        return 1
    fi
}

# Check performance impact
check_performance_impact() {
    check "Performance impact assessment"

    local performance_issues=0

    # Count rewrite rules
    local rewrite_rules=$(grep -c "RewriteRule" "$CONFIG_FILE" || echo "0")
    if [[ $rewrite_rules -gt 50 ]]; then
        warn "High number of rewrite rules: $rewrite_rules (may affect performance)"
        ((performance_issues++))
    elif [[ $rewrite_rules -gt 30 ]]; then
        info "Moderate number of rewrite rules: $rewrite_rules"
    else
        pass "Reasonable number of rewrite rules: $rewrite_rules"
    fi

    # Check for complex regex patterns
    local complex_patterns=$(grep -c "\(\.\*\.\*\)" "$CONFIG_FILE" || echo "0")
    if [[ $complex_patterns -gt 10 ]]; then
        warn "High number of complex regex patterns: $complex_patterns"
        ((performance_issues++))
    else
        pass "Reasonable number of complex patterns: $complex_patterns"
    fi

    # Check for file-based access control
    local file_checks=$(grep -c "<Files" "$CONFIG_FILE" || echo "0")
    if [[ $file_checks -gt 20 ]]; then
        warn "High number of file-based rules: $file_checks"
        ((performance_issues++))
    else
        pass "Reasonable number of file-based rules: $file_checks"
    fi

    if [[ $performance_issues -eq 0 ]]; then
        pass "Performance impact check passed"
        return 0
    else
        fail "Found $performance_issues performance concerns"
        return 1
    fi
}

# Show results
show_results() {
    echo -e "\n${BLUE}=== CONFIGURATION VALIDATION RESULTS ===${NC}"
    echo -e "Total Checks: $TOTAL_CHECKS"
    echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
    echo -e "${RED}Failed: $FAILED_CHECKS${NC}"

    if [[ $FAILED_CHECKS -eq 0 ]]; then
        echo -e "\n${GREEN}🎉 All validation checks passed! Configuration is ready for production.${NC}"
        return 0
    else
        echo -e "\n${RED}⚠️  $FAILED_CHECKS validation check(s) failed. Please review and fix the issues.${NC}"
        echo -e "\n${YELLOW}Recommendations:${NC}"
        echo "• Fix failed checks before deploying to production"
        echo "• Test configuration in a staging environment first"
        echo "• Monitor server performance after deployment"
        echo "• Check OpenLiteSpeed error logs for issues"
        return 1
    fi
}

# Main function
main() {
    echo -e "${BLUE}=== OPENLITESPEED CONFIGURATION VALIDATOR ===${NC}"
    echo "Validating: $CONFIG_FILE"
    echo ""

    validate_apache_syntax
    check_ols_compatibility
    check_cyberpanel_integration
    check_seo_safety
    check_performance_impact
    show_results
}

# Run main function
main "$@"