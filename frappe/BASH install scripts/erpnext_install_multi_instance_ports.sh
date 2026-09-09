#!/usr/bin/env bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m'

server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
server_ip=${server_ip:-127.0.0.1}

die() {
    echo -e "${RED}$1${NC}" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

find_common_site_configs() {
    local search_paths=()

    [[ -d /home ]] && search_paths+=("/home")
    [[ -d "$HOME" && "$HOME" != /home/* ]] && search_paths+=("$HOME")
    [[ -d /opt ]] && search_paths+=("/opt")
    [[ -d /var/www ]] && search_paths+=("/var/www")

    if [[ ${#search_paths[@]} -eq 0 ]]; then
        return 0
    fi

    find "${search_paths[@]}" -maxdepth 4 -path '*/sites/common_site_config.json' -print0 2>/dev/null | sort -zu
}

normalize_existing_bench_port_types() {
    local config_file=""

    while IFS= read -r -d '' config_file; do
        python3 - "$config_file" <<'PY'
import json
import sys

path = sys.argv[1]
numeric_keys = ("webserver_port", "socketio_port")

try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(0)

changed = False
for key in numeric_keys:
    value = data.get(key)
    if isinstance(value, str) and value.isdigit():
        data[key] = int(value)
        changed = True

if changed:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=True)
        f.write("\n")
PY
    done < <(find_common_site_configs || true)
}

ask_yes_no() {
    local prompt="$1"
    local answer=""

    while true; do
        read -rp "$prompt (yes/no): " answer
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
        case "$answer" in
            yes|y) return 0 ;;
            no|n) return 1 ;;
            *) echo -e "${RED}Please answer yes or no.${NC}" ;;
        esac
    done
}

ask_install_mode() {
    local mode=""

    echo
    echo -e "${YELLOW}Select installation mode:${NC}"
    echo "  1) development - use bench start manually"
    echo "  2) production  - configure supervisor/nginx"

    while true; do
        read -rp "Mode (1/2, default: 1): " mode
        mode=${mode:-1}

        case "$mode" in
            1|development|dev)
                INSTALL_MODE="development"
                return 0
                ;;
            2|production|prod)
                INSTALL_MODE="production"
                return 0
                ;;
            *)
                echo -e "${RED}Invalid mode. Choose 1 for development or 2 for production.${NC}"
                ;;
        esac
    done
}

ask_secret_twice() {
    local prompt="$1"
    local first=""
    local second=""

    while true; do
        read -rsp "$prompt: " first
        echo >&2
        read -rsp "Confirm password: " second
        echo >&2

        if [[ -n "$first" && "$first" == "$second" ]]; then
            echo "$first"
            return 0
        fi

        echo -e "${RED}Passwords are empty or do not match. Try again.${NC}" >&2
    done
}

sanitize_db_name() {
    local raw="$1"
    local sanitized=""

    sanitized=$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_]+/_/g; s/^_+//; s/_+$//')

    if [[ -z "$sanitized" ]]; then
        sanitized="frappe_site"
    fi

    if [[ "$sanitized" =~ ^[0-9] ]]; then
        sanitized="db_${sanitized}"
    fi

    echo "${sanitized:0:48}"
}

generate_site_db_name() {
    local prefix=""
    local random_id=""

    prefix=$(sanitize_db_name "$bench_name")
    prefix=${prefix:0:24}
    random_id=$(tr -dc 'a-z0-9' </dev/urandom | head -c 10)

    echo "${prefix}_${random_id}"
}

db_exists() {
    local db_name="$1"

    mysql -uroot -p"$db_root_password" -NBe "SHOW DATABASES LIKE '$db_name';" 2>/dev/null | grep -qx "$db_name"
}

port_is_busy() {
    local port="$1"

    if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$port" 2>/dev/null | grep -q ":$port"; then
        return 0
    fi

    if command -v netstat >/dev/null 2>&1 && netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$port$"; then
        return 0
    fi

    if command -v lsof >/dev/null 2>&1 && lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

port_is_configured_in_existing_bench() {
    local port="$1"
    local config_file=""

    while IFS= read -r -d '' config_file; do
        if grep -Eq "(:|\")$port(\"|,|$)" "$config_file"; then
            return 0
        fi
    done < <(find_common_site_configs || true)

    return 1
}

find_free_port() {
    local start_port="$1"
    local port="$start_port"

    while port_is_busy "$port" || port_is_configured_in_existing_bench "$port"; do
        port=$((port + 1))
    done

    echo "$port"
}

suggest_web_port() {
    find_free_port 8000
}

find_free_port_block() {
    local base="$1"
    local web_port=""
    local socketio_port=""
    local redis_cache_port=""
    local redis_queue_port=""
    local redis_socketio_port=""

    while true; do
        web_port="$base"
        socketio_port=$((base + 1000))
        redis_cache_port=$((base + 5000))
        redis_queue_port=$((base + 3000))
        redis_socketio_port=$((base + 4000))

        if ! port_is_busy "$web_port" && ! port_is_configured_in_existing_bench "$web_port" && \
           ! port_is_busy "$socketio_port" && ! port_is_configured_in_existing_bench "$socketio_port" && \
           ! port_is_busy "$redis_cache_port" && ! port_is_configured_in_existing_bench "$redis_cache_port" && \
           ! port_is_busy "$redis_queue_port" && ! port_is_configured_in_existing_bench "$redis_queue_port" && \
           ! port_is_busy "$redis_socketio_port" && ! port_is_configured_in_existing_bench "$redis_socketio_port"; then
            WEBSERVER_PORT="$web_port"
            SOCKETIO_PORT="$socketio_port"
            REDIS_CACHE_PORT="$redis_cache_port"
            REDIS_QUEUE_PORT="$redis_queue_port"
            REDIS_SOCKETIO_PORT="$redis_socketio_port"
            return 0
        fi

        base=$((base + 1))
    done
}

detect_existing_benches() {
    local config_file=""
    local found=false

    echo -e "${YELLOW}Checking existing Frappe/ERPNext benches...${NC}"

    while IFS= read -r -d '' config_file; do
        found=true
        echo -e "${BLUE}- ${config_file%/sites/common_site_config.json}${NC}"
        grep -E 'webserver_port|socketio_port|redis_cache|redis_queue|redis_socketio' "$config_file" || true
    done < <(find_common_site_configs || true)

    if [[ "$found" == false ]]; then
        echo -e "${GREEN}No existing bench configuration detected.${NC}"
    fi
}

next_bench_name() {
    local requested="$1"
    local candidate="$requested"
    local index=2

    while [[ -e "$HOME/$candidate" ]]; do
        candidate="${requested}-${index}"
        index=$((index + 1))
    done

    echo "$candidate"
}

configure_bench_ports() {
    echo -e "${YELLOW}Configuring isolated ports for this bench...${NC}"

    bench set-config -g supervisor_group "$bench_name"
    bench set-config -g webserver_port "$WEBSERVER_PORT" --parse
    bench set-config -g socketio_port "$SOCKETIO_PORT" --parse
    bench set-config -g redis_cache "redis://127.0.0.1:$REDIS_CACHE_PORT"
    bench set-config -g redis_queue "redis://127.0.0.1:$REDIS_QUEUE_PORT"
    bench set-config -g redis_socketio "redis://127.0.0.1:$REDIS_SOCKETIO_PORT"

    if bench setup redis >/dev/null 2>&1; then
        echo -e "${GREEN}Redis config files regenerated for this bench.${NC}"
    else
        echo -e "${YELLOW}bench setup redis failed or is unavailable. bench start may still generate/use the config.${NC}"
    fi
}

redis_port_is_ready() {
    local port="$1"

    if command -v redis-cli >/dev/null 2>&1; then
        redis-cli -h 127.0.0.1 -p "$port" ping 2>/dev/null | grep -q PONG
        return $?
    fi

    port_is_busy "$port"
}

start_redis_port() {
    local name="$1"
    local port="$2"
    local config_file="config/redis_${name}.conf"

    if redis_port_is_ready "$port"; then
        echo -e "${GREEN}Redis $name already running on port $port.${NC}"
        return 0
    fi

    echo -e "${YELLOW}Starting Redis $name on port $port...${NC}"

    if [[ -f "$config_file" ]]; then
        redis-server "$config_file" --daemonize yes
    else
        redis-server --bind 127.0.0.1 --port "$port" --daemonize yes --dir "$PWD" --dbfilename "redis-${name}.rdb"
    fi

    for _ in {1..10}; do
        if redis_port_is_ready "$port"; then
            return 0
        fi
        sleep 1
    done

    die "Redis $name did not start on port $port."
}

start_bench_redis() {
    require_command redis-server

    start_redis_port cache "$REDIS_CACHE_PORT"
    start_redis_port queue "$REDIS_QUEUE_PORT"

    if [[ -f config/redis_socketio.conf || "$REDIS_SOCKETIO_PORT" != "$REDIS_CACHE_PORT" ]]; then
        start_redis_port socketio "$REDIS_SOCKETIO_PORT"
    else
        echo -e "${GREEN}Redis socketio uses Redis cache on port $REDIS_CACHE_PORT.${NC}"
    fi
}

configure_supervisor_for_bench() {
    echo -e "${YELLOW}Configuring Supervisor for bench group $bench_name...${NC}"

    bench set-config -g supervisor_group "$bench_name"
    bench setup supervisor

    if [[ -f "$PWD/config/supervisor.conf" ]]; then
        sudo ln -sf "$PWD/config/supervisor.conf" "/etc/supervisor/conf.d/${bench_name}.conf"
    fi

    sudo systemctl restart supervisor || sudo service supervisor restart
    sudo supervisorctl reread
    sudo supervisorctl update
}

configure_nginx_for_bench() {
    echo -e "${YELLOW}Configuring Nginx for bench $bench_name...${NC}"

    bench setup nginx

    if [[ -f "$PWD/config/nginx.conf" ]]; then
        sudo ln -sf "$PWD/config/nginx.conf" "/etc/nginx/conf.d/${bench_name}.conf"
    fi

    if ! sudo nginx -t >/dev/null 2>&1 && grep -q ' main;' "$PWD/config/nginx.conf" 2>/dev/null; then
        echo -e "${YELLOW}Nginx log format 'main' is missing. Patching bench nginx config...${NC}"
        sed -i 's/ main;/ combined;/g' "$PWD/config/nginx.conf"
    fi

    sudo nginx -t
    sudo systemctl reload nginx || sudo service nginx reload
}

configure_ssl_certificate() {
    if ! command -v certbot >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing Certbot...${NC}"

        if command -v snap >/dev/null 2>&1; then
            sudo snap install core || true
            sudo snap refresh core || true
            sudo snap install --classic certbot
            sudo ln -sf /snap/bin/certbot /usr/bin/certbot
        else
            sudo apt update -y
            sudo apt install certbot python3-certbot-nginx -y
        fi
    fi

    echo -e "${YELLOW}Requesting SSL certificate for $site_name...${NC}"
    sudo certbot --nginx --non-interactive --agree-tos --email "$SSL_EMAIL" -d "$site_name"
}

print_port_summary() {
    echo -e "${GREEN}Assigned ports:${NC}"
    echo "  Web:             $WEBSERVER_PORT"
    echo "  Socket.IO:       $SOCKETIO_PORT"
    echo "  Redis cache:     $REDIS_CACHE_PORT"
    echo "  Redis queue:     $REDIS_QUEUE_PORT"
    echo "  Redis socketio:  $REDIS_SOCKETIO_PORT"
}

print_install_summary() {
    echo
    echo -e "${GREEN}Installation summary:${NC}"
    echo "  Bench path:       $HOME/$bench_name"
    echo "  Version:          $bench_version"
    echo "  Site/FQDN:        $site_name"
    echo "  Database name:    $db_name"
    echo "  Mode:             $INSTALL_MODE"
    echo "  Install ERPNext:  $INSTALL_ERPNEXT"
    echo "  SSL certificate:  $INSTALL_SSL"
    if [[ "${INSTALL_SSL:-no}" == "yes" ]]; then
        echo "  SSL email:        $SSL_EMAIL"
    fi
    print_port_summary
    echo
}

echo -e "${BLUE}Frappe/ERPNext multi-instance installer${NC}"
echo -e "${YELLOW}This script creates a new bench with non-conflicting ports.${NC}"

require_command bench
require_command grep
require_command find
require_command python3

normalize_existing_bench_port_types
detect_existing_benches

versions=("version-13" "version-14" "version-15" "version-16" "develop")
echo -e "${YELLOW}Select Frappe/ERPNext version:${NC}"
select bench_version in "${versions[@]}"; do
    [[ -n "${bench_version:-}" ]] && break
    echo -e "${RED}Invalid option.${NC}"
done

if [[ "$bench_version" == "develop" ]]; then
    ask_yes_no "Develop is unstable. Continue anyway" || die "Installation cancelled."
fi

read -rp "Enter a name for your bench folder (default: frappe-bench): " requested_bench_name
requested_bench_name=${requested_bench_name:-frappe-bench}
bench_name=$(next_bench_name "$requested_bench_name")

if [[ "$bench_name" != "$requested_bench_name" ]]; then
    echo -e "${YELLOW}$requested_bench_name already exists. Using $bench_name instead.${NC}"
fi

suggested_web_port=$(suggest_web_port)
read -rp "Starting web port to try (default: $suggested_web_port): " base_port
base_port=${base_port:-$suggested_web_port}
[[ "$base_port" =~ ^[0-9]+$ ]] || die "Invalid port: $base_port"

find_free_port_block "$base_port"

ask_install_mode

echo
echo -e "${YELLOW}Site and database information${NC}"
read -rp "Enter the site name/FQDN: " site_name
[[ -n "$site_name" ]] || die "Site name is required."

echo
db_root_password=$(ask_secret_twice "Enter MariaDB/MySQL root password")
echo
admin_password=$(ask_secret_twice "Enter Frappe Administrator password")
echo

db_name=$(generate_site_db_name)

if command -v mysql >/dev/null 2>&1 && db_exists "$db_name"; then
    die "Generated database $db_name already exists. Run the script again."
fi

echo

if ask_yes_no "Install ERPNext app"; then
    INSTALL_ERPNEXT="yes"
else
    INSTALL_ERPNEXT="no"
fi

INSTALL_SSL="no"
SSL_EMAIL=""
if [[ "$INSTALL_MODE" == "production" ]]; then
    if ask_yes_no "Install SSL certificate with Certbot/Nginx"; then
        INSTALL_SSL="yes"
        echo
        read -rp "Enter email for SSL certificate notifications: " SSL_EMAIL
        [[ -n "$SSL_EMAIL" ]] || die "SSL email is required."
    fi
fi

print_install_summary
ask_yes_no "Create this new instance" || die "Installation cancelled."

cd "$HOME"

echo -e "${YELLOW}Initialising bench $bench_name...${NC}"
bench init "$bench_name" --version "$bench_version" --verbose

cd "$bench_name"
configure_bench_ports
start_bench_redis

echo -e "${YELLOW}Creating site $site_name...${NC}"
bench new-site "$site_name" \
    --db-name "$db_name" \
    --db-root-username root \
    --db-root-password "$db_root_password" \
    --admin-password "$admin_password"

if [[ "$INSTALL_ERPNEXT" == "yes" ]]; then
    bench get-app erpnext --branch "$bench_version"
    bench --site "$site_name" install-app erpnext
fi

bench use "$site_name"

if [[ "$INSTALL_MODE" == "production" ]]; then
    configure_bench_ports
    if ! yes | sudo bench setup production "$USER"; then
        echo -e "${YELLOW}bench setup production returned an error. Continuing with explicit Supervisor/Nginx setup for this bench...${NC}"
    fi
    configure_bench_ports
    configure_supervisor_for_bench
    configure_nginx_for_bench
    sudo supervisorctl restart "${bench_name}:" || sudo supervisorctl restart all || true

    if [[ "$INSTALL_SSL" == "yes" ]]; then
        configure_ssl_certificate
    fi
else
    echo -e "${YELLOW}Development mode selected. Start it with: cd $PWD && bench start${NC}"
fi

echo -e "${GREEN}--------------------------------------------------------------------------------${NC}"
echo -e "${GREEN}Installation finished for bench: $PWD${NC}"
echo -e "${GREEN}Site: $site_name${NC}"
print_port_summary
echo -e "${GREEN}Open: http://$server_ip:$WEBSERVER_PORT${NC}"
echo -e "${GREEN}--------------------------------------------------------------------------------${NC}"
