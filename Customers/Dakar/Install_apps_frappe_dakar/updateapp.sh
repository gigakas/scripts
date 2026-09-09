#!/bin/bash
set -euo pipefail

# --- CONFIGURATION ---
DEFAULT_SITE="local.frappe.lan"
DEFAULT_BENCH_DIR="$HOME/frappe-bench"
DEFAULT_GIT_REMOTE="upstream"
DEFAULT_BACKUP_BASE_DIR="$HOME/backups-frappe"

APPS=(
    "applauncher"
    "helpdesk"
    "dakarprojects"
    "dakartimesheets"
    "calltrack"
    "hs_manager"
    "chatbot"
    "customers"
)
# ---------------------

read -rp "Enter the site/domain [$DEFAULT_SITE]: " SITE
SITE="${SITE:-$DEFAULT_SITE}"

read -rp "Enter the bench folder [$DEFAULT_BENCH_DIR]: " BENCH_DIR
BENCH_DIR="${BENCH_DIR:-$DEFAULT_BENCH_DIR}"

read -rp "Enter the git remote name [$DEFAULT_GIT_REMOTE]: " GIT_REMOTE
GIT_REMOTE="${GIT_REMOTE:-$DEFAULT_GIT_REMOTE}"

DEFAULT_BACKUP_DIR="$DEFAULT_BACKUP_BASE_DIR/$SITE"
read -rp "Enter the backup folder [$DEFAULT_BACKUP_DIR]: " BACKUP_DIR
BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"

read -sp "Enter your Azure DevOps Personal Access Token (PAT): " GIT_TOKEN
echo ""

if [ -z "$GIT_TOKEN" ]; then
    echo "Error: The token cannot be empty."
    exit 1
fi

cd "$BENCH_DIR" || exit 1

STAMP="$(date +%Y%m%d-%H%M%S)"

echo "--- Creating backup directory ---"
mkdir -p "$BACKUP_DIR/$STAMP"

echo "--- Creating site backup ---"
bench --site "$SITE" backup --with-files

echo "--- Moving backup files to $BACKUP_DIR/$STAMP ---"
find "sites/$SITE/private/backups" -maxdepth 1 -type f -mmin -10 -exec mv {} "$BACKUP_DIR/$STAMP/" \;

echo "--- Stashing local changes ---"

for APP_NAME in "${APPS[@]}"; do
    APP_DIR="apps/$APP_NAME"

    if [ ! -d "$APP_DIR/.git" ]; then
        echo ">> Skipping $APP_NAME: no git repository found at $APP_DIR"
        continue
    fi

    echo ">> Checking local changes in $APP_NAME..."

    if ! git -C "$APP_DIR" diff --quiet || \
       ! git -C "$APP_DIR" diff --cached --quiet || \
       [ -n "$(git -C "$APP_DIR" ls-files --others --exclude-standard)" ]; then
        git -C "$APP_DIR" stash push -u -m "prod-stash-before-update-$STAMP"
        echo "   Stash created for $APP_NAME"
    else
        echo "   No local changes found"
    fi
done

echo "--- Updating custom apps from remote: $GIT_REMOTE ---"

for APP_NAME in "${APPS[@]}"; do
    APP_DIR="apps/$APP_NAME"

    if [ ! -d "$APP_DIR/.git" ]; then
        echo ">> Skipping $APP_NAME: no git repository found at $APP_DIR"
        continue
    fi

    if ! git -C "$APP_DIR" remote get-url "$GIT_REMOTE" >/dev/null 2>&1; then
        echo ">> Skipping $APP_NAME: remote '$GIT_REMOTE' is not configured"
        continue
    fi

    echo ">> Updating $APP_NAME from $GIT_REMOTE..."

    REMOTE_URL=$(git -C "$APP_DIR" remote get-url "$GIT_REMOTE")
    CLEAN_URL=$(echo "$REMOTE_URL" | sed 's|https://[^@]*@|https://|')

    if [[ "$CLEAN_URL" == https://*dev.azure.com/* ]]; then
        AUTH_URL=$(echo "$CLEAN_URL" | sed "s|https://|https://dakarsoftware:${GIT_TOKEN}@|")
        SAFE_URL=$(echo "$CLEAN_URL" | sed 's|https://|https://dakarsoftware@|')

        git -C "$APP_DIR" remote set-url "$GIT_REMOTE" "$AUTH_URL"
        git -C "$APP_DIR" fetch "$GIT_REMOTE"

        CURRENT_BRANCH=$(git -C "$APP_DIR" rev-parse --abbrev-ref HEAD)
        git -C "$APP_DIR" pull --ff-only "$GIT_REMOTE" "$CURRENT_BRANCH"

        git -C "$APP_DIR" remote set-url "$GIT_REMOTE" "$SAFE_URL"
    else
        git -C "$APP_DIR" fetch "$GIT_REMOTE"

        CURRENT_BRANCH=$(git -C "$APP_DIR" rev-parse --abbrev-ref HEAD)
        git -C "$APP_DIR" pull --ff-only "$GIT_REMOTE" "$CURRENT_BRANCH"
    fi
done

echo "--- Installing Python requirements ---"
bench setup requirements

echo "--- Building selected app assets ---"

for APP_NAME in "${APPS[@]}"; do
    APP_DIR="apps/$APP_NAME"

    if [ ! -d "$APP_DIR" ]; then
        echo ">> Skipping $APP_NAME: app directory not found"
        continue
    fi

    echo ">> Building assets for $APP_NAME..."
    bench build --apps "$APP_NAME"
done

echo "--- Running migrations ---"
bench --site "$SITE" migrate

echo "--- Clearing cache ---"
bench --site "$SITE" clear-cache
bench --site "$SITE" clear-website-cache

echo "--- Restarting bench ---"
bench restart

echo "--- Update completed successfully ---"
echo "Backup location: $BACKUP_DIR/$STAMP"
echo "Created stashes are labeled as: prod-stash-before-update-$STAMP"
