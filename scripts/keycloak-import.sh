#!/bin/bash

# =============================================================================
# Keycloak Import Script for Cloning OIDCRealm
# =============================================================================
# This script imports the exported Keycloak realm and client definitions
# to a new Keycloak instance for staging/testing purposes.
#
# Usage: ./keycloak-import.sh <target-keycloak-url> <admin-username> <admin-password> [--dry-run]
# Example: ./keycloak-import.sh https://staging-keycloak.example.com admin your-admin-password
# Dry run: ./keycloak-import.sh https://staging-keycloak.example.com admin your-admin-password --dry-run
#
# Alternative: ./keycloak-import.sh <target-keycloak-url> <admin-client-id> <admin-client-secret> --client-credentials [--dry-run]
# Example: ./keycloak-import.sh https://staging-keycloak.example.com admin-cli your-admin-secret --client-credentials
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
EXPORT_DIR="$SCRIPT_DIR/keycloak-exports"
LATEST_EXPORT=$(ls -t "$EXPORT_DIR" | head -n1)
EXPORT_PATH="$EXPORT_DIR/$LATEST_EXPORT"

# Parse arguments - extract flags first, then positional params
DRY_RUN=false
USE_CLIENT_CREDENTIALS=false
declare -a POSITIONAL_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;
        --client-credentials)
            USE_CLIENT_CREDENTIALS=true
            ;;
        *)
            POSITIONAL_ARGS+=("$arg")
            ;;
    esac
done

# Extract positional parameters (after flags are removed)
TARGET_KEYCLOAK_URL="${POSITIONAL_ARGS[0]:-}"
ADMIN_USERNAME="${POSITIONAL_ARGS[1]:-}"
ADMIN_PASSWORD="${POSITIONAL_ARGS[2]:-}"

# If using client credentials, treat username/password as client ID/secret
if [[ "$USE_CLIENT_CREDENTIALS" == "true" ]]; then
    ADMIN_CLIENT_ID="$ADMIN_USERNAME"
    ADMIN_CLIENT_SECRET="$ADMIN_PASSWORD"
fi

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_dry_run() {
    echo -e "${YELLOW}[DRY-RUN]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <target-keycloak-url> <admin-username> <admin-password> [--dry-run]"
    echo "   or: $0 <target-keycloak-url> <admin-client-id> <admin-client-secret> --client-credentials [--dry-run]"
    echo ""
    echo "Examples:"
    echo "  $0 https://staging-keycloak.example.com admin your-admin-password"
    echo "  $0 https://staging-keycloak.example.com admin your-admin-password --dry-run"
    echo "  $0 https://staging-keycloak.example.com admin-cli your-admin-secret --client-credentials"
    echo ""
    echo "This will import the latest export from: $EXPORT_PATH"
    echo ""
    echo "Notes:"
    echo "  - Use admin username/password for fresh Keycloak instances"
    echo "  - Use client credentials if you have an admin client configured"
    echo "  - Use --dry-run to preview what would be imported without making changes"
}

# Function to validate parameters
validate_parameters() {
    if [[ -z "$TARGET_KEYCLOAK_URL" ]]; then
        log_error "Missing required parameter: target-keycloak-url"
        show_usage
        exit 1
    fi
    
    # Only require credentials for non-dry-run mode
    if [[ "$DRY_RUN" == "false" && (-z "$ADMIN_USERNAME" || -z "$ADMIN_PASSWORD") ]]; then
        log_error "Missing required parameters: admin-username and admin-password"
        show_usage
        exit 1
    fi
    
    if [[ ! -d "$EXPORT_PATH" ]]; then
        log_error "Export directory not found: $EXPORT_PATH"
        log "Please run the export script first: ./keycloak-export.sh"
        exit 1
    fi
    
    log "Using export from: $EXPORT_PATH"
    log "Target Keycloak URL: $TARGET_KEYCLOAK_URL"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "DRY-RUN MODE: No changes will be made to the target Keycloak instance"
    fi
}

# Function to get admin access token
get_admin_token() {
    log "Obtaining admin access token for target Keycloak instance..."
    
    local token_response
    if [[ "$USE_CLIENT_CREDENTIALS" == "true" ]]; then
        log "Using client credentials authentication"
        token_response=$(curl -s -X POST \
            "$TARGET_KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=client_credentials" \
            -d "client_id=$ADMIN_CLIENT_ID" \
            -d "client_secret=$ADMIN_CLIENT_SECRET")
    else
        log "Using username/password authentication"
        token_response=$(curl -s -X POST \
            "$TARGET_KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=password" \
            -d "client_id=admin-cli" \
            -d "username=$ADMIN_USERNAME" \
            -d "password=$ADMIN_PASSWORD")
    fi
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to obtain admin token"
        exit 1
    fi
    
    # Extract access token
    ACCESS_TOKEN=$(echo "$token_response" | jq -r '.access_token')
    
    if [[ "$ACCESS_TOKEN" == "null" || -z "$ACCESS_TOKEN" ]]; then
        log_error "Failed to extract access token from response"
        log "Response: $token_response"
        exit 1
    fi
    
    log_success "Admin access token obtained"
}

# Function to import realm configuration
import_realm() {
    log "Importing realm configuration..."
    
    local realm_file="$EXPORT_PATH/realm-OIDCRealm.json"
    
    if [[ ! -f "$realm_file" ]]; then
        log_error "Realm configuration file not found: $realm_file"
        return 1
    fi
    
    # Show what would be imported
    local realm_name=$(jq -r '.realm' "$realm_file")
    log "Realm to import: $realm_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Would import realm: $realm_name"
        log_dry_run "Realm settings: $(jq -c '{displayName, enabled, loginTheme, accountTheme}' "$realm_file")"
        return 0
    fi
    
    # Keep the realm name for import
    local temp_realm_file="/tmp/realm-import.json"
    cp "$realm_file" "$temp_realm_file"
    
    local response
    response=$(curl -s -X POST \
        "$TARGET_KEYCLOAK_URL/admin/realms" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d @"$temp_realm_file")
    
    local exit_code=$?
    rm -f "$temp_realm_file"
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Failed to import realm configuration (curl error)"
        return 1
    fi
    
    # Check for API errors in response
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        local error_msg=$(echo "$response" | jq -r '.errorMessage // .error')
        log_error "Failed to import realm configuration: $error_msg"
        log "Response: $response"
        return 1
    fi
    
    log_success "Realm configuration imported successfully"
}

# Function to import client configurations
import_clients() {
    log "Importing manually configured client configurations..."
    
    local specific_clients_dir="$EXPORT_PATH/specific-clients"
    local clients_dir="$EXPORT_PATH/clients"
    
    # Check if at least one client directory exists
    if [[ ! -d "$specific_clients_dir" && ! -d "$clients_dir" ]]; then
        log_error "Neither specific-clients nor clients directory found:"
        log_error "  - $specific_clients_dir"
        log_error "  - $clients_dir"
        return 1
    fi
    
    if [[ ! -d "$specific_clients_dir" ]]; then
        log_warning "Specific clients directory not found: $specific_clients_dir"
        log "Will use clients directory instead: $clients_dir"
    fi
    
    local imported_count=0
    local failed_count=0
    
    # Define the clients we want to import (manually configured ones)
    local target_clients=("demo-workinpilot" "mailcow" "WipCloud" "actual-admin-cli")
    
    for client_name in "${target_clients[@]}"; do
        log "Processing client: $client_name"
        
        # Try specific-clients first, then fall back to clients directory
        local client_file="$specific_clients_dir/client-$client_name.json"
        if [[ ! -f "$client_file" ]]; then
            log "  → Not found in specific-clients, trying clients directory..."
            client_file="$EXPORT_PATH/clients/client-$client_name.json"
        else
            log "  → Found in specific-clients directory"
        fi
        
        if [[ ! -f "$client_file" ]]; then
            log_warning "Client file not found: $client_file"
            log_warning "  Searched locations:"
            log_warning "    1. $specific_clients_dir/client-$client_name.json"
            log_warning "    2. $EXPORT_PATH/clients/client-$client_name.json"
            ((failed_count++))
            continue
        fi
        
        log "  → Using file: $client_file"
        
        # Show client details (handle both array and object formats)
        local client_id client_protocol client_enabled
        if jq -e '.[0]' "$client_file" > /dev/null 2>&1; then
            # Array format (specific-clients)
            client_id=$(jq -r '.[0].clientId' "$client_file" 2>/dev/null || echo "unknown")
            client_protocol=$(jq -r '.[0].protocol' "$client_file" 2>/dev/null || echo "unknown")
            client_enabled=$(jq -r '.[0].enabled' "$client_file" 2>/dev/null || echo "unknown")
            if [[ "$client_id" == "null" || -z "$client_id" ]]; then
                log_warning "  → Failed to parse client ID from array format"
                ((failed_count++))
                continue
            fi
        else
            # Object format (clients)
            client_id=$(jq -r '.clientId' "$client_file" 2>/dev/null || echo "unknown")
            client_protocol=$(jq -r '.protocol' "$client_file" 2>/dev/null || echo "unknown")
            client_enabled=$(jq -r '.enabled' "$client_file" 2>/dev/null || echo "unknown")
            if [[ "$client_id" == "null" || -z "$client_id" ]]; then
                log_warning "  → Failed to parse client ID from object format"
                ((failed_count++))
                continue
            fi
        fi
        
        log "Client: $client_name (ID: $client_id, Protocol: $client_protocol, Enabled: $client_enabled)"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would import client: $client_name"
            local client_details
            if jq -e '.[0]' "$client_file" > /dev/null 2>&1; then
                # Array format
                client_details=$(jq -c '.[0] | {clientId, protocol, enabled, redirectUris, webOrigins}' "$client_file" 2>/dev/null || echo "Failed to parse array format")
                log_dry_run "Client details (array format): $client_details"
            else
                # Object format
                client_details=$(jq -c '{clientId, protocol, enabled, redirectUris, webOrigins}' "$client_file" 2>/dev/null || echo "Failed to parse object format")
                log_dry_run "Client details (object format): $client_details"
            fi
            ((imported_count++))
            continue
        fi
        
        log "Importing client: $client_name"
        
        # Remove client ID and secret to avoid conflicts (handle both formats)
        local temp_client_file="/tmp/client-import.json"
        if jq -e '.[0]' "$client_file" > /dev/null 2>&1; then
            jq '.[0] | del(.id, .secret)' "$client_file" > "$temp_client_file"
        else
            jq 'del(.id, .secret)' "$client_file" > "$temp_client_file"
        fi
        
        local response
        response=$(curl -s -w "\n%{http_code}" -X POST \
            "$TARGET_KEYCLOAK_URL/admin/realms/OIDCRealm/clients" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            -d @"$temp_client_file" 2>&1)
        
        local exit_code=$?
        local http_code=$(echo "$response" | tail -n1)
        local response_body=$(echo "$response" | sed '$d')
        rm -f "$temp_client_file"
        
        if [[ $exit_code -ne 0 ]]; then
            log_warning "Failed to import client: $client_name (curl error, exit code: $exit_code)"
            log_warning "  Response: $response_body"
            ((failed_count++))
            continue
        fi
        
        # Check HTTP status code
        if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
            log_warning "Failed to import client: $client_name (HTTP $http_code)"
            if [[ -n "$response_body" ]]; then
                log_warning "  Response: $response_body"
            fi
            ((failed_count++))
            continue
        fi
        
        # Check for API errors in response body
        if [[ -n "$response_body" ]]; then
            if echo "$response_body" | jq -e '.error' > /dev/null 2>&1; then
                local error_msg=$(echo "$response_body" | jq -r '.errorMessage // .error // .message // "Unknown error"')
                log_warning "Failed to import client: $client_name - $error_msg"
                log_warning "  Full response: $response_body"
                ((failed_count++))
                continue
            fi
        fi
        
        log_success "Client $client_name imported successfully"
        ((imported_count++))
    done
    
    # Always show summary, even if no clients were processed
    if [[ $imported_count -eq 0 && $failed_count -eq 0 ]]; then
        log_warning "No clients were processed - check if client files exist in export directory"
        log "  Searched in: $specific_clients_dir"
        log "  Searched in: $clients_dir"
    else
        log "Client import summary: $imported_count imported, $failed_count failed"
    fi
}

# Function to import realm roles
import_realm_roles() {
    log "Importing realm roles..."
    
    local roles_file="$EXPORT_PATH/realm-roles.json"
    
    if [[ ! -f "$roles_file" ]]; then
        log_warning "Realm roles file not found: $roles_file"
        return 0
    fi
    
    # Import each role individually
    local role_count=0
    jq -r '.[] | @json' "$roles_file" | while read -r role_json; do
        local role_name=$(echo "$role_json" | jq -r '.name')
        
        # Skip default roles that are created automatically
        if [[ "$role_name" == "offline_access" || "$role_name" == "uma_authorization" || "$role_name" == "default-roles-oidcrealm" ]]; then
            log "Skipping default role: $role_name (created automatically by Keycloak)"
            continue
        fi
        
        log "Role: $role_name"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would import realm role: $role_name"
            log_dry_run "Role details: $(echo "$role_json" | jq -c '{name, description, composite}')"
            continue
        fi
        
        log "Importing realm role: $role_name"
        
        local response
        response=$(curl -s -X POST \
            "$TARGET_KEYCLOAK_URL/admin/realms/OIDCRealm/roles" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$role_json")
        
        if [[ $? -ne 0 ]]; then
            log_warning "Failed to import realm role: $role_name (curl error)"
        elif echo "$response" | jq -e '.error' > /dev/null 2>&1; then
            local error_msg=$(echo "$response" | jq -r '.errorMessage // .error')
            log_warning "Failed to import realm role: $role_name - $error_msg"
        else
            log_success "Realm role $role_name imported successfully"
        fi
        
        ((role_count++))
    done
    
    log "Realm roles import completed"
}

# Function to import service account role assignments
import_service_account_roles() {
    log "Importing service account role assignments..."
    
    local service_account_roles_dir="$EXPORT_PATH/service-account-roles"
    
    if [[ ! -d "$service_account_roles_dir" ]]; then
        log_warning "Service account roles directory not found: $service_account_roles_dir"
        log "Service account roles will need to be assigned manually"
        return 0
    fi
    
    local role_files
    role_files=$(find "$service_account_roles_dir" -name "service-account-roles-*.json" 2>/dev/null)
    
    if [[ -z "$role_files" ]]; then
        log_warning "No service account role files found in: $service_account_roles_dir"
        log "Service account roles will need to be assigned manually"
        return 0
    fi
    
    for role_file in $role_files; do
        local client_id
        client_id=$(jq -r '.clientId' "$role_file" 2>/dev/null)
        
        if [[ -z "$client_id" || "$client_id" == "null" ]]; then
            log_warning "Invalid service account role file: $role_file"
            continue
        fi
        
        log "Processing service account roles for client: $client_id"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            local realm_roles_count client_roles_count
            realm_roles_count=$(jq -r '.realmRoles | length' "$role_file" 2>/dev/null || echo "0")
            client_roles_count=$(jq -r '.clientRoles | length' "$role_file" 2>/dev/null || echo "0")
            log_dry_run "Would assign $realm_roles_count realm roles and $client_roles_count client roles to service account for: $client_id"
            continue
        fi
        
        # Get the client UUID from clientId
        local client_response
        client_response=$(curl -s -X GET \
            "$TARGET_KEYCLOAK_URL/admin/realms/OIDCRealm/clients?clientId=$client_id" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json")
        
        if [[ $? -ne 0 ]]; then
            log_warning "Failed to get client UUID for: $client_id"
            continue
        fi
        
        local client_uuid
        client_uuid=$(echo "$client_response" | jq -r '.[0].id // empty')
        
        if [[ -z "$client_uuid" || "$client_uuid" == "null" ]]; then
            log_warning "Client not found: $client_id"
            continue
        fi
        
        # Get service account user ID
        local sa_user_response
        sa_user_response=$(curl -s -X GET \
            "$TARGET_KEYCLOAK_URL/admin/realms/OIDCRealm/clients/$client_uuid/service-account-user" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json")
        
        if [[ $? -ne 0 ]]; then
            log_warning "Failed to get service account user for client: $client_id"
            continue
        fi
        
        local sa_user_id
        sa_user_id=$(echo "$sa_user_response" | jq -r '.id // empty')
        
        if [[ -z "$sa_user_id" || "$sa_user_id" == "null" ]]; then
            log_warning "Service account user not found for client: $client_id (ensure service accounts are enabled)"
            continue
        fi
        
        # Import realm role mappings
        local realm_roles
        realm_roles=$(jq -c '.realmRoles' "$role_file" 2>/dev/null)
        
        if [[ -n "$realm_roles" && "$realm_roles" != "null" && "$realm_roles" != "[]" ]]; then
            log "Assigning realm roles to service account for: $client_id"
            local response
            response=$(curl -s -X POST \
                "$TARGET_KEYCLOAK_URL/admin/realms/OIDCRealm/users/$sa_user_id/role-mappings/realm" \
                -H "Authorization: Bearer $ACCESS_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$realm_roles")
            
            if [[ $? -eq 0 ]]; then
                log_success "Realm roles assigned to service account for: $client_id"
            else
                log_warning "Failed to assign realm roles for: $client_id"
            fi
        fi
        
        # Import client role mappings
        local client_roles
        client_roles=$(jq -c '.clientRoles' "$role_file" 2>/dev/null)
        
        if [[ -n "$client_roles" && "$client_roles" != "null" && "$client_roles" != "[]" ]]; then
            # Client roles need to be assigned per client - get realm-management client ID
            local realm_mgmt_response
            realm_mgmt_response=$(curl -s -X GET \
                "$TARGET_KEYCLOAK_URL/admin/realms/OIDCRealm/clients?clientId=realm-management" \
                -H "Authorization: Bearer $ACCESS_TOKEN" \
                -H "Content-Type: application/json")
            
            local realm_mgmt_id
            realm_mgmt_id=$(echo "$realm_mgmt_response" | jq -r '.[0].id // empty')
            
            if [[ -n "$realm_mgmt_id" && "$realm_mgmt_id" != "null" ]]; then
                log "Assigning client roles to service account for: $client_id"
                local response
                response=$(curl -s -X POST \
                    "$TARGET_KEYCLOAK_URL/admin/realms/OIDCRealm/users/$sa_user_id/role-mappings/clients/$realm_mgmt_id" \
                    -H "Authorization: Bearer $ACCESS_TOKEN" \
                    -H "Content-Type: application/json" \
                    -d "$client_roles")
                
                if [[ $? -eq 0 ]]; then
                    log_success "Client roles assigned to service account for: $client_id"
                else
                    log_warning "Failed to assign client roles for: $client_id"
                fi
            fi
        fi
    done
    
    log_success "Service account role assignments completed"
}

# Function to create import summary
create_import_summary() {
    log "Creating import summary..."
    
    local summary_file="$EXPORT_PATH/import-summary-$(date +%Y%m%d_%H%M%S).json"
    
    cat > "$summary_file" << EOF
{
  "import_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "target_keycloak_url": "$TARGET_KEYCLOAK_URL",
  "source_export": "$LATEST_EXPORT",
  "imported_components": {
    "realm_configuration": "OIDCRealm",
    "clients": "clients/",
    "realm_roles": "realm-roles.json"
  },
  "notes": [
    "Client secrets need to be regenerated after import",
    "Redirect URIs may need to be updated for new environment",
    "Test all authentication flows after import"
  ]
}
EOF
    
    log_success "Import summary created: $summary_file"
}

# Function to show next steps
show_next_steps() {
    log "Import completed! Next steps:"
    echo ""
    echo "1. **Update Client Secrets**:"
    echo "   - Go to your new Keycloak admin console"
    echo "   - Navigate to Clients → [client-name] → Credentials"
    echo "   - Generate new client secrets"
    echo ""
    echo "2. **Update Redirect URIs**:"
    echo "   - Update redirect URIs for your staging environment"
    echo "   - Main app: http://staging.workinpilot.org/auth/keycloak/callback"
    echo "   - NextCloud: https://staging-cloud.workinpilot.org/callback"
    echo "   - MailCow: https://staging-mail.workinpilot.org/callback"
    echo ""
    echo "3. **Update Environment Variables**:"
    echo "   - Update your staging .env file with new Keycloak URL"
    echo "   - Update client secrets"
    echo ""
    echo "4. **Test Authentication**:"
    echo "   - Test login flows for all clients"
    echo "   - Verify redirect URIs work correctly"
    echo ""
    echo "5. **Export Staging Config**:"
    echo "   - Run: ./keycloak-export.sh (after updating .env)"
    echo "   - This will capture your staging-specific configuration"
}

# Main execution function
main() {
    log "Starting Keycloak import to: $TARGET_KEYCLOAK_URL"
    
    # Validate parameters
    validate_parameters
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "DRY-RUN MODE: Skipping authentication and showing import preview"
        log_dry_run "Target: $TARGET_KEYCLOAK_URL"
        log_dry_run "Source: $EXPORT_PATH"
    else
        # Get admin access token
        get_admin_token
    fi
    
    # Perform imports
    import_realm
    import_clients
    import_realm_roles
    import_service_account_roles
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "DRY-RUN completed. No changes were made."
        log_dry_run "To perform actual import, run without --dry-run flag"
    else
        # Create summary
        create_import_summary
        
        # Show next steps
        show_next_steps
        
        log_success "Keycloak import completed successfully!"
    fi
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log "Please install the missing dependencies and try again"
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_dependencies
    main "$@"
fi
