# clone-keycloak-realm
Script to export objects and import same from / to a selected keycloak realm.  Exported content is stored in a timestamped collection of json files that can later be imported under a new realm name.

## SETUP

You must setup an .env file before you begin.  This file will contain important object names slated to be exported.

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
