# clone-keycloak-realm Deployment Instructions

## Export Information
- **Export Date**: Mon Nov  3 04:07:51 PM UTC 2025
- **Keycloak URL**: https://secure.example.com
- **Realm**: ExportedRealm

## Exported Components

### 1. Realm Configuration
- File: `realm-ExportedRealm.json`
- Contains: Complete realm settings, authentication flows, themes, etc.

### 2. Client Configurations
- **All Clients**: `clients-all.json` - List of all clients
- **Individual Clients**: `clients/` - Detailed configuration for each client
- **Specific Clients**: `specific-clients/` - Clients mentioned in environment config

### 3. Role Definitions
- **Realm Roles**: `realm-roles.json` - Global realm roles
- **Client Roles**: `client-roles/` - Roles specific to each client

## Deployment Steps

### 1. Import Realm Configuration
```bash
# Import the realm (this will create/update the realm)
curl -X POST \
  "https://secure.example.com/admin/realms" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d @realm-ExportedRealm.json
```

### 2. Import Client Configurations
```bash
# For each client in the clients/ directory
for client_file in clients/*.json; do
  curl -X POST \
    "https://secure.example.com/admin/realms/ExportedRealm/clients" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$client_file"
done
```

### 3. Import Role Definitions
```bash
# Import realm roles
curl -X POST \
  "https://secure.example.com/admin/realms/ExportedRealm/roles" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d @realm-roles.json
```

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
- **Main App Client**: demo-example
- **NextCloud Client**: WipCloud
- **MailCow Client**: mailcow

## Security Considerations

- Store exported files securely
- Rotate client secrets after import
- Verify all configurations before going live
- Test authentication flows thoroughly
