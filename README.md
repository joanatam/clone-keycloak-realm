
# clone a keycloak realm

> Two Bash scripts for exporting and importing Keycloak realm configurations, including clients, roles, and users. Exports are stored in timestamped directories for easy versioning and reuse.

---

## Overview

This project provides two core scripts:

- `keycloak-export.sh`: Exports a Keycloak realm (including clients, roles, users, etc.) into a structured JSON format.
- `keycloak-import.sh`: Imports a previously exported Keycloak realm into a new or existing realm.

Exports are saved in timestamped directories under a `keycloak-exports` folder, making it easy to manage multiple versions of a realm.

---

## Setup

### 1. Create `.env` File

A `.env` file is required to store Keycloak credentials and configuration. Use the provided `.env.template` as a guide:

```bash
# .env
KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=yourpassword
KEYCLOAK_URL=https://keycloak.example.com/auth
KEYCLOAK_REALM=master
```

> **Note**: Ensure you have admin access to the Keycloak instance.

---

## Folder Structure

```
project-root/
├── .env                  # Keycloak credentials and configuration
├── keycloak-exports/     # Directory containing all exports
│   └── 2025-04-05T14:30:00Z/  # Timestamped export folder
│       ├── realm.json        # Exported realm configuration
│       ├── clients/          # Exported client configurations
│       ├── roles/            # Exported roles
│       └── service_accounts/ # Exported service account users
├── keycloak-export.sh      # Script to export Keycloak configurations
└── keycloak-import.sh      # Script to import Keycloak configurations
```

## Timestamped Folder Structure - Example

```
keycloak-exports/2025-04-05T14:30:00Z/
├── realm.json
├── clients/
│   ├── client-One.json
│   └── client-Another.json
├── specific-clients/
│   ├── client-Two.json
│   └── client-Third.json
├── roles/
│   └── role-Admin.json
└── service_accounts/
    └── user-service-account.json
```


---

## Exports

To export a Keycloak realm:

```bash
./keycloak-export.sh
```

### Output

- A new timestamped directory is created under `keycloak-exports/`.
- All exported data is stored in JSON format:
  - `realm.json`: Full realm configuration
  - `clients/`: Individual client configurations
  - `roles/`: Realm roles
  - `service_accounts/`: Service account users

---

## Imports

To import a previously exported realm:

```bash
./keycloak-import.sh --imported-realm <realm-name> <target-keycloak-url> <admin-username> <admin-password> [--dry-run]
```

### Options

- `--dry-run`: Simulate the import without making changes to the Keycloak instance.

> **Important**: The import script must be run from the **root directory** of the export folder (e.g., `2025-04-05T14:30:00Z/`).

---

## Example Workflow

### 1. Export a Realm

```bash
# Create .env file
cp .env.template .env

# Run export
./keycloak-export.sh
```

### 2. Import a Realm

```bash
# Navigate to export directory
cd keycloak-exports/2025-04-05T14:30:00Z/

# Run import
./keycloak-import.sh --imported-realm NewRealm https://keycloak.example.com/auth admin admin
```

---

## Note - To Clone Into a New Realm:
If you wish to import the exported realm into a NEW realm, you must
 1. change the .env file to replace old realm name with the new name, 
 2. remove the "id" field from .json import files (let Keycloak generate it), 
 3. change the realm.json and client.json files to replace the old realm name with the new realm name.
 4. get rid of 'id' element in json files, so that keycloak can generate a new id (must be unique within the realm)
 5. check the new realm-name is used by the clients referenced in `keycloak-import.sh` 
 6. set `--imported_realm` to your new realm name when. you run `keycloak-import.sh`


---

## General Notes

- **Exported data** can be imported into a **new or existing realm**.
- **Realm name** is not preserved during import — it is set via the `.env` file.
- **Role and client mappings** are preserved during import.
- **Service accounts** are exported as users for re-import.

---

## License

MIT License

---

## Contributing

Pull requests and feature suggestions are welcome! For major changes, please open an issue and include test and test results first.

---

## Contact

For issues, questions, or feature requests, open an issue on this repository.
