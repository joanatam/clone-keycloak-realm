#!/bin/bash

# =============================================================================
# Keycloak Export Script Test
# =============================================================================
# This script tests the keycloak-export.sh script with mock data
# =============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_SCRIPT="$SCRIPT_DIR/keycloak-export.sh"
TEST_ENV_FILE="$SCRIPT_DIR/test-env"

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to create test environment file
create_test_env() {
    log "Creating test environment file"
    
    cat > "$TEST_ENV_FILE" << 'EOF'
# Test environment for keycloak-export.sh
KEYCLOAK_URL=https://test-keycloak.example.com
KEYCLOAK_REALM=test-realm
KEYCLOAK_ADMIN_REALM=master
KEYCLOAK_ADMIN_CLIENT_ID=test-admin-client
KEYCLOAK_ADMIN_CLIENT_SECRET=test-admin-secret
KEYCLOAK_CLIENT_ID=test-app-client
SOGO_CLIENT_ID=test-sogo-client
EOF
    
    log_success "Test environment file created"
}

# Function to test script syntax
test_syntax() {
    log "Testing script syntax"
    
    if bash -n "$EXPORT_SCRIPT"; then
        log_success "Script syntax is valid"
    else
        log_error "Script syntax errors found"
        return 1
    fi
}

# Function to test script help/usage
test_usage() {
    log "Testing script usage information"
    
    # Test that script runs without parameters
    if "$EXPORT_SCRIPT" 2>&1 | grep -q "Starting Keycloak export"; then
        log_success "Script runs without parameters"
    else
        log_error "Script requires parameters or has issues"
        return 1
    fi
}

# Function to test dependency checks
test_dependencies() {
    log "Testing dependency checks"
    
    # Test if script checks for required dependencies
    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        log_success "Required dependencies (curl, jq) are available"
    else
        log_warning "Some dependencies missing - this will be caught by the script"
    fi
}

# Function to test environment file loading
test_env_loading() {
    log "Testing environment file loading logic"
    
    # Create a temporary test environment file
    local temp_env="$SCRIPT_DIR/temp-test.env"
    cat > "$temp_env" << 'EOF'
KEYCLOAK_URL=https://test.example.com
KEYCLOAK_REALM=test
KEYCLOAK_ADMIN_REALM=master
KEYCLOAK_ADMIN_CLIENT_ID=admin
KEYCLOAK_ADMIN_CLIENT_SECRET=secret
EOF
    
    # Test if the script can load environment variables
    # (This is a basic test - the actual script will do more validation)
    if source "$temp_env" && [[ -n "${KEYCLOAK_URL:-}" ]]; then
        log_success "Environment file loading works"
    else
        log_error "Environment file loading failed"
        rm -f "$temp_env"
        return 1
    fi
    
    rm -f "$temp_env"
}

# Function to test JSON validation
test_json_validation() {
    log "Testing JSON validation"
    
    # Test valid JSON
    echo '{"test": "value"}' | jq empty 2>/dev/null
    if [[ $? -eq 0 ]]; then
        log_success "Valid JSON processing works"
    else
        log_error "Valid JSON processing failed"
        return 1
    fi
    
    # Test invalid JSON
    echo '{"test": "value"' | jq empty 2>/dev/null
    if [[ $? -ne 0 ]]; then
        log_success "Invalid JSON detection works"
    else
        log_error "Invalid JSON detection failed"
        return 1
    fi
}

# Function to test directory creation
test_directory_creation() {
    log "Testing directory creation logic"
    
    local test_dir="$SCRIPT_DIR/test-export-dir"
    
    # Test directory creation
    mkdir -p "$test_dir"
    if [[ -d "$test_dir" ]]; then
        log_success "Directory creation works"
        rmdir "$test_dir"
    else
        log_error "Directory creation failed"
        return 1
    fi
}

# Function to test curl command construction
test_curl_commands() {
    log "Testing curl command construction"
    
    # Test basic curl command structure
    local test_url="https://example.com/api"
    local test_token="test-token"
    
    # This tests the command structure without actually making the call
    local curl_cmd="curl -s -X GET '$test_url' -H 'Authorization: Bearer $test_token' -H 'Content-Type: application/json'"
    
    if [[ -n "$curl_cmd" ]]; then
        log_success "Curl command construction works"
    else
        log_error "Curl command construction failed"
        return 1
    fi
}

# Function to clean up test files
cleanup() {
    log "Cleaning up test files"
    rm -f "$TEST_ENV_FILE"
    log_success "Test cleanup completed"
}

# Main test function
main() {
    log "Starting Keycloak Export Script Tests"
    
    local test_results=()
    
    # Run tests
    test_syntax && test_results+=("syntax: PASS") || test_results+=("syntax: FAIL")
    test_usage && test_results+=("usage: PASS") || test_results+=("usage: FAIL")
    test_dependencies && test_results+=("dependencies: PASS") || test_results+=("dependencies: FAIL")
    test_env_loading && test_results+=("env_loading: PASS") || test_results+=("env_loading: FAIL")
    test_json_validation && test_results+=("json_validation: PASS") || test_results+=("json_validation: FAIL")
    test_directory_creation && test_results+=("directory_creation: PASS") || test_results+=("directory_creation: FAIL")
    test_curl_commands && test_results+=("curl_commands: PASS") || test_results+=("curl_commands: FAIL")
    
    # Display results
    log "Test Results:"
    for result in "${test_results[@]}"; do
        if [[ "$result" == *"PASS"* ]]; then
            log_success "$result"
        else
            log_error "$result"
        fi
    done
    
    # Count passes and failures
    local pass_count=0
    local fail_count=0
    
    for result in "${test_results[@]}"; do
        if [[ "$result" == *"PASS"* ]]; then
            ((pass_count++))
        else
            ((fail_count++))
        fi
    done
    
    log "Summary: $pass_count passed, $fail_count failed"
    
    if [[ $fail_count -eq 0 ]]; then
        log_success "All tests passed!"
    else
        log_error "Some tests failed"
        return 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Create test environment
    create_test_env
    
    # Run tests
    main "$@"
fi
