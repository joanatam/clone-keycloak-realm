# clone-keycloak-realm
Script to export objects and import same from / to a selected keycloak realm.  Exported content is stored in a timestamped collection of json files that can later be imported under a new realm name.

## Setup

You must setup an .env file before you begin.  This file will contain important object names slated to be cloned.

## Exports

The export script will require a .env file to begin.

Exports will be written to a timestamped subfolder of a ```keycloak-exports``` subfolder of the current folder.  

```
# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXPORT_DIR="$SCRIPT_DIR/keycloak-exports"
```

There will be 1 timestamped sub-folder created per export.

## Imports

The ```keycloak-import.sh``` script must be run in the same folder as the *root* of the latest export.  By default it will select the latest export objects to import.

You need a keycloak admin id and password to run the import script:
```
 Usage: ./keycloak-import.sh <target-keycloak-url> <admin-username> <admin-password> [--dry-run]
```
