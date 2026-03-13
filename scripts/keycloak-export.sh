#!/bin/bash

# =============================================================================
# Keycloak Export Script for Deployment Preparation
# =============================================================================
# This script exports Keycloak realm and client definitions using the Admin API
# for backup and deployment preparation purposes.
#
# Usage: ./keycloak-export.sh
# Reads configuration from .env
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
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXPORT_DIR="$SCRIPT_DIR/keycloak-exports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# No environment parameter needed - uses .env directly

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

# Function to load environment variables
load_env() {
    local env_file="$PROJECT_ROOT/.env"
    
    if [[ ! -f "$env_file" ]]; then
        log_error "Environment file not found: $env_file"
        log ""
        log "Please create .env with your Keycloak configuration:"
        log "KEYCLOAK_URL=https://secure.example.com"
        log "KEYCLOAK_REALM=ExampleRealm"
        log "KEYCLOAK_ADMIN_REALM=ExampleRealm"
        log "KEYCLOAK_ADMIN_CLIENT_ID=actual-admin-cli"
        log "KEYCLOAK_ADMIN_CLIENT_SECRET=your-admin-secret"
        log "KEYCLOAK_CLIENT_ID=demo-example"
        log "STALWART_CLIENT_ID=stalwart-client"
        log "SOGO_CLIENT_ID=sogo-client"
        log ""
        log "You can copy from env.example and update with your real values"
        exit 1
    fi
    
    log "Loading environment from: $env_file"
    
    # Use a safer approach to source the file
    set +u  # Temporarily disable unbound variable checking
    source "$env_file"
    set -u  # Re-enable unbound variable checking
    
    # Validate required environment variables
    local required_vars=(
        "KEYCLOAK_URL"
        "KEYCLOAK_REALM"
        "KEYCLOAK_ADMIN_REALM"
        "KEYCLOAK_ADMIN_CLIENT_ID"
        "KEYCLOAK_ADMIN_CLIENT_SECRET"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    log_success "Environment variables loaded successfully"
}

# Function to get admin access token
get_admin_token() {
    log "Obtaining admin access token..."
    
    local token_response
    token_response=$(curl -s -X POST \
        "$KEYCLOAK_URL/realms/$KEYCLOAK_ADMIN_REALM/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials" \
        -d "client_id=$KEYCLOAK_ADMIN_CLIENT_ID" \
        -d "client_secret=$KEYCLOAK_ADMIN_CLIENT_SECRET")
    
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

# Function to create export directory
create_export_dir() {
    local export_path="$EXPORT_DIR/$TIMESTAMP"
    mkdir -p "$export_path"
    EXPORT_PATH="$export_path"
    log "Created export directory: $EXPORT_PATH"
}

# Function to export realm configuration
export_realm() {
    log "Exporting realm configuration for: $KEYCLOAK_REALM"
    
    local realm_export="$EXPORT_PATH/realm-$KEYCLOAK_REALM.json"
    
    curl -s -X GET \
        "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        | jq '.' > "$realm_export"
    
    if [[ $? -eq 0 ]]; then
        log_success "Realm configuration exported to: $realm_export"
    else
        log_error "Failed to export realm configuration"
        return 1
    fi
}

# Function to export all clients in the realm
export_clients() {
    log "Exporting all clients from realm: $KEYCLOAK_REALM"
    
    local clients_export="$EXPORT_PATH/clients-all.json"
    local clients_dir="$EXPORT_PATH/clients"
    mkdir -p "$clients_dir"
    
    # Get all clients
    local clients_response
    clients_response=$(curl -s -w "\n%{http_code}" -X GET \
        "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/clients" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json")
    
    local http_code=$(echo "$clients_response" | tail -n1)
    local response_body=$(echo "$clients_response" | sed '$d')
    
    if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
        log_error "Failed to export clients list (HTTP $http_code)"
        log_error "Response: $response_body"
        return 1
    fi
    
    # Validate JSON and check if it's an array
    if ! echo "$response_body" | jq '.' > "$clients_export" 2>/dev/null; then
        log_error "Invalid JSON response from Keycloak"
        log_error "Response: $response_body"
        return 1
    fi
    
    # Check if response is an array
    if ! echo "$response_body" | jq -e 'type == "array"' > /dev/null 2>&1; then
        log_error "Expected array of clients, got: $(echo "$response_body" | jq -r 'type')"
        log_error "Response: $response_body"
        
        # Check if it's an error message
        if echo "$response_body" | jq -e '.error' > /dev/null 2>&1; then
            local error_msg=$(echo "$response_body" | jq -r '.errorMessage // .error')
            log_error "Keycloak error: $error_msg"
        fi
        return 1
    fi
    
    log_success "Clients list exported to: $clients_export"
    
    # Export individual client configurations
    local client_ids
    client_ids=$(jq -r '.[].id' "$clients_export" 2>/dev/null)
    
    if [[ -z "$client_ids" ]]; then
        log_warning "No client IDs found in export (realm may have no clients)"
        return 0
    fi
    
    for client_id in $client_ids; do
        local client_name
        client_name=$(jq -r --arg id "$client_id" '.[] | select(.id == $id) | .clientId' "$clients_export")
        
        log "Exporting client: $client_name (ID: $client_id)"
        
        curl -s -X GET \
            "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/clients/$client_id" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            | jq '.' > "$clients_dir/client-$client_name.json"
        
        if [[ $? -eq 0 ]]; then
            log_success "Client $client_name exported successfully"
        else
            log_warning "Failed to export client: $client_name"
        fi
    done
    
    log_success "All clients exported to: $clients_dir"
}

# Function to export specific clients mentioned in environment
export_specific_clients() {
    log "Exporting specific clients mentioned in environment configuration"
    
    local specific_clients_dir="$EXPORT_PATH/specific-clients"
    mkdir -p "$specific_clients_dir"
    
    # List of client IDs from environment variables
    local env_clients=(
        "KEYCLOAK_CLIENT_ID"
        "STALWART_CLIENT_ID"
        "SOGO_CLIENT_ID"
    )
    
    for env_var in "${env_clients[@]}"; do
        local client_id="${!env_var:-}"
        if [[ -n "$client_id" ]]; then
            log "Exporting specific client: $client_id"
            
            # Get client by clientId (not internal ID)
            local client_response
            client_response=$(curl -s -X GET \
                "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/clients?clientId=$client_id" \
                -H "Authorization: Bearer $ACCESS_TOKEN" \
                -H "Content-Type: application/json")
            
            if [[ $? -eq 0 ]]; then
                echo "$client_response" | jq '.' > "$specific_clients_dir/client-$client_id.json"
                log_success "Specific client $client_id exported"
            else
                log_warning "Failed to export specific client: $client_id"
            fi
        fi
    done
}

# Function to export realm roles
export_realm_roles() {
    log "Exporting realm roles"
    
    local roles_export="$EXPORT_PATH/realm-roles.json"
    
    curl -s -X GET \
        "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/roles" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        | jq '.' > "$roles_export"
    
    if [[ $? -eq 0 ]]; then
        log_success "Realm roles exported to: $roles_export"
    else
        log_warning "Failed to export realm roles"
    fi
}

# Function to export client roles
export_client_roles() {
    log "Exporting client roles"
    
    local client_roles_dir="$EXPORT_PATH/client-roles"
    mkdir -p "$client_roles_dir"
    
    # Get all clients first
    local clients_response
    clients_response=$(curl -s -X GET \
        "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/clients" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json")
    
    # Extract client IDs and names
    local client_data
    client_data=$(echo "$clients_response" | jq -r '.[] | "\(.id)|\(.clientId)"')
    
    for client_info in $client_data; do
        IFS='|' read -r client_id client_name <<< "$client_info"
        
        log "Exporting roles for client: $client_name"
        
        curl -s -X GET \
            "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/clients/$client_id/roles" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            | jq '.' > "$client_roles_dir/roles-$client_name.json"
        
        if [[ $? -eq 0 ]]; then
            log_success "Client roles for $client_name exported"
        else
            log_warning "Failed to export roles for client: $client_name"
        fi
    done
}

# Function to export service account role assignments
export_service_account_roles() {
    log "Exporting service account role assignments"
    
    local service_account_roles_dir="$EXPORT_PATH/service-account-roles"
    mkdir -p "$service_account_roles_dir"
    
    # Get all clients first
    local clients_response
    clients_response=$(curl -s -X GET \
        "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/clients" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json")
    
    if [[ $? -ne 0 ]]; then
        log_warning "Failed to get clients list for service account roles export"
        return 0
    fi
    
    # Check if response is valid array
    if ! echo "$clients_response" | jq -e 'type == "array"' > /dev/null 2>&1; then
        log_warning "Invalid clients response, skipping service account roles export"
        return 0
    fi
    
    # Extract client IDs and names, check if service accounts are enabled
    local client_data
    client_data=$(echo "$clients_response" | jq -r '.[] | select(.serviceAccountsEnabled == true) | "\(.id)|\(.clientId)"')
    
    if [[ -z "$client_data" ]]; then
        log "No clients with service accounts enabled found"
        return 0
    fi
    
    for client_info in $client_data; do
        IFS='|' read -r client_id client_name <<< "$client_info"
        
        log "Exporting service account roles for client: $client_name"
        
        # Get service account user ID first
        local sa_user_response
        sa_user_response=$(curl -s -X GET \
            "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/clients/$client_id/service-account-user" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json")
        
        if [[ $? -ne 0 ]]; then
            log_warning "Failed to get service account user for client: $client_name"
            continue
        fi
        
        local sa_user_id
        sa_user_id=$(echo "$sa_user_response" | jq -r '.id // empty')
        
        if [[ -z "$sa_user_id" || "$sa_user_id" == "null" ]]; then
            log_warning "Service account user not found for client: $client_name"
            continue
        fi
        
        # Get realm role mappings
        local realm_roles_response
        realm_roles_response=$(curl -s -X GET \
            "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/users/$sa_user_id/role-mappings/realm" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json")
        
        # Get client role mappings (from realm-management client typically)
        local client_roles_response
        client_roles_response=$(curl -s -X GET \
            "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/users/$sa_user_id/role-mappings/clients" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json")
        
        # Combine into a single export file
        local roles_export="$service_account_roles_dir/service-account-roles-$client_name.json"
        cat > "$roles_export" << EOF
{
  "clientId": "$client_name",
  "clientUuid": "$client_id",
  "serviceAccountUserId": "$sa_user_id",
  "realmRoles": $(echo "$realm_roles_response" | jq '. // []'),
  "clientRoles": $(echo "$client_roles_response" | jq '. // []')
}
EOF
        
        if [[ $? -eq 0 ]]; then
            log_success "Service account roles for $client_name exported"
        else
            log_warning "Failed to export service account roles for client: $client_name"
        fi
    done
    
    log_success "Service account role assignments exported"
}

# Function to create export summary
create_export_summary() {
    log "Creating export summary"
    
    local summary_file="$EXPORT_PATH/export-summary.json"
    
    cat > "$summary_file" << EOF
{
  "export_timestamp": "$TIMESTAMP",
  "keycloak_url": "$KEYCLOAK_URL",
  "realm": "$KEYCLOAK_REALM",
  "admin_realm": "$KEYCLOAK_ADMIN_REALM",
  "exported_components": {
    "realm_configuration": "realm-$KEYCLOAK_REALM.json",
    "all_clients": "clients-all.json",
    "individual_clients": "clients/",
    "specific_clients": "specific-clients/",
    "realm_roles": "realm-roles.json",
    "client_roles": "client-roles/"
  },
  "environment_clients": {
    "main_app_client": "${KEYCLOAK_CLIENT_ID:-N/A}",
    "stalwart_client": "${STALWART_CLIENT_ID:-N/A}",
    "sogo_client": "${SOGO_CLIENT_ID:-N/A}"
  }
}
EOF
    
    log_success "Export summary created: $summary_file"
}

# Function to validate exports
validate_exports() {
    log "Validating exported files"
    
    local validation_errors=0
    
    # Check if main files exist and are valid JSON
    local main_files=(
        "realm-$KEYCLOAK_REALM.json"
        "clients-all.json"
        "realm-roles.json"
    )
    
    for file in "${main_files[@]}"; do
        local file_path="$EXPORT_PATH/$file"
        if [[ -f "$file_path" ]]; then
            if jq empty "$file_path" 2>/dev/null; then
                log_success "Valid JSON: $file"
            else
                log_error "Invalid JSON: $file"
                ((validation_errors++))
            fi
        else
            log_error "Missing file: $file"
            ((validation_errors++))
        fi
    done
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "All exports validated successfully"
    else
        log_error "Validation failed with $validation_errors errors"
        return 1
    fi
}

# Function to create deployment instructions
create_deployment_instructions() {
    log "Creating deployment instructions"
    
    local instructions_file="$EXPORT_PATH/DEPLOYMENT_INSTRUCTIONS.md"
    
    cat > "$instructions_file" << EOF
# Keycloak Deployment Instructions

## Export Information
- **Export Date**: $(date)
- **Keycloak URL**: $KEYCLOAK_URL
- **Realm**: $KEYCLOAK_REALM

## Exported Components

### 1. Realm Configuration
- File: \`realm-$KEYCLOAK_REALM.json\`
- Contains: Complete realm settings, authentication flows, themes, etc.

### 2. Client Configurations
- **All Clients**: \`clients-all.json\` - List of all clients
- **Individual Clients**: \`clients/\` - Detailed configuration for each client
- **Specific Clients**: \`specific-clients/\` - Clients mentioned in environment config

### 3. Role Definitions
- **Realm Roles**: \`realm-roles.json\` - Global realm roles
- **Client Roles**: \`client-roles/\` - Roles specific to each client

## Deployment Steps

### 1. Import Realm Configuration
\`\`\`bash
# Import the realm (this will create/update the realm)
curl -X POST \\
  "$KEYCLOAK_URL/admin/realms" \\
  -H "Authorization: Bearer \$ADMIN_TOKEN" \\
  -H "Content-Type: application/json" \\
  -d @realm-$KEYCLOAK_REALM.json
\`\`\`

### 2. Import Client Configurations
\`\`\`bash
# For each client in the clients/ directory
for client_file in clients/*.json; do
  curl -X POST \\
    "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/clients" \\
    -H "Authorization: Bearer \$ADMIN_TOKEN" \\
    -H "Content-Type: application/json" \\
    -d @"\$client_file"
done
\`\`\`

### 3. Import Role Definitions
\`\`\`bash
# Import realm roles
curl -X POST \\
  "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/roles" \\
  -H "Authorization: Bearer \$ADMIN_TOKEN" \\
  -H "Content-Type: application/json" \\
  -d @realm-roles.json
\`\`\`

## Important Notes

1. **Client Secrets**: Client secrets are NOT exported for security reasons.
   You'll need to regenerate or set new secrets after import.

2. **User Data**: This export does NOT include user accounts or user-specific data.
   Only configuration is exported.

3. **Environment Variables**: Update your environment variables to match the
   imported client IDs and new secrets.

4. **Testing**: Always test the import in a staging environment first.

## Environment-Specific Clients

Based on your environment configuration:
- **Main App Client**: ${KEYCLOAK_CLIENT_ID:-N/A}
- **Stalwart Client**: ${STALWART_CLIENT_ID:-N/A}
- **SOGo Client**: ${SOGO_CLIENT_ID:-N/A}

## Security Considerations

- Store exported files securely
- Rotate client secrets after import
- Verify all configurations before going live
- Test authentication flows thoroughly
EOF
    
    log_success "Deployment instructions created: $instructions_file"
}

# Main execution function
main() {
    log "Starting Keycloak export from .env"
    
    # Load environment variables
    load_env
    
    # Get admin access token
    get_admin_token
    
    # Create export directory
    create_export_dir
    
    # Perform exports
    export_realm
    export_clients
    export_specific_clients
    export_realm_roles
    export_client_roles
    export_service_account_roles
    
    # Create summary and instructions
    create_export_summary
    create_deployment_instructions
    
    # Validate exports
    validate_exports
    
    log_success "Keycloak export completed successfully!"
    log "Export location: $EXPORT_PATH"
    log "Files exported:"
    find "$EXPORT_PATH" -type f -name "*.json" -o -name "*.md" | sort | while read -r file; do
        echo "  - $(basename "$file")"
    done
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
