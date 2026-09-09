#!/usr/bin/env bash

handle_error() {
    local line=$1
    local exit_code=$?
    echo "An error occurred on line $line with exit status $exit_code"
    exit $exit_code
}

trap 'handle_error $LINENO' ERR
set -e

server_ip=$(hostname -I | awk '{print $1}')

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
LIGHT_BLUE='\033[1;34m'
NC='\033[0m' 

SUPPORTED_DISTRIBUTIONS=("Ubuntu" "Debian")
SUPPORTED_VERSIONS=("26.04" "24.04" "23.04" "22.04" "20.04" "12" "11" "10" "9" "8")

check_os() {
    local os_name=$(lsb_release -is)
    local os_version=$(lsb_release -rs)
    local os_supported=false
    local version_supported=false

    for i in "${SUPPORTED_DISTRIBUTIONS[@]}"; do
        if [[ "$i" = "$os_name" ]]; then
            os_supported=true
            break
        fi
    done

    for i in "${SUPPORTED_VERSIONS[@]}"; do
        if [[ "$i" = "$os_version" ]]; then
            version_supported=true
            break
        fi
    done

    if [[ "$os_supported" = false ]] || [[ "$version_supported" = false ]]; then
        echo -e "${RED}This script is not compatible with your operating system or its version.${NC}"
        exit 1
    fi
}

check_os

OS="$(uname)"
case $OS in
  'Linux')
    OS='Linux'
    if [ -f /etc/redhat-release ] ; then
      DISTRO='CentOS'
    elif [ -f /etc/debian_version ] ; then
      if [ "$(lsb_release -si)" == "Ubuntu" ]; then
        DISTRO='Ubuntu'
      else
        DISTRO='Debian'
      fi
    fi
    ;;
  *) ;;
esac

ask_twice() {
    local prompt="$1"
    local secret="$2"
    local val1 val2

    while true; do
        if [ "$secret" = "true" ]; then
            read -rsp "$prompt: " val1
            echo >&2
        else
            read -rp "$prompt: " val1
            echo >&2
        fi

        if [ "$secret" = "true" ]; then
            read -rsp "Confirm password: " val2
            echo >&2
        else
            read -rp "Confirm password: " val2
            echo >&2
        fi

        if [ "$val1" = "$val2" ]; then
            printf "${GREEN}Password confirmed${NC}\n" >&2
            echo "$val1"
            break
        else
            printf "${RED}Inputs do not match. Please try again${NC}\n" >&2
            echo -e "\n"
        fi
    done
}

extract_app_name_from_setup() {
    local setup_file="$1"
    local app_name=""
    
    if [[ -f "$setup_file" ]]; then
        app_name=$(grep -oE 'name\s*=\s*["\047][^"\047]+["\047]' "$setup_file" 2>/dev/null | head -1 | sed -E 's/.*name\s*=\s*["\047]([^"\047]+)["\047].*/\1/')
        
        if [[ -z "$app_name" ]]; then
            app_name=$(grep -oE 'name\s*=\s*["\047][^"\047]*["\047]' "$setup_file" 2>/dev/null | head -1 | sed -E 's/.*["\047]([^"\047]+)["\047].*/\1/')
        fi
        
        if [[ -z "$app_name" ]]; then
            app_name=$(awk '/setup\s*\(/,/\)/ { if (/name\s*=/) { gsub(/.*name\s*=\s*["\047]/, ""); gsub(/["\047].*/, ""); print; exit } }' "$setup_file" 2>/dev/null | head -1 | tr -d ' \t')
        fi
        
        if [[ -z "$app_name" ]]; then
            app_name=$(grep "name.*=" "$setup_file" 2>/dev/null | head -1 | sed -E 's/.*["\047]([^"\047]+)["\047].*/\1/' | tr -d ' \t')
        fi
        
        if [[ -z "$app_name" ]]; then
            local app_base_dir=$(dirname "$setup_file")
            for subdir in "$app_base_dir"/*/; do
                if [[ -d "$subdir" && -f "$subdir/__init__.py" ]]; then
                    local module_dir=$(basename "$subdir")
                    if [[ -n "$module_dir" && "$module_dir" != "." && "$module_dir" != "tests" && "$module_dir" != "docs" ]]; then
                        app_name="$module_dir"
                        break
                    fi
                fi
            done
        fi
    fi
    
    echo "$app_name"
}

check_existing_installations() {
    local existing_installations=()
    local installation_paths=()
    
    local search_paths=(
        "$HOME/$bench_name"
        "/home/*/$bench_name"
        "/opt/$bench_name"
        "/var/www/$bench_name"
    )
    
    echo -e "${YELLOW}Checking for existing ERPNext installations...${NC}"
    
    for path in "${search_paths[@]}"; do
        if [[ -d "$path" ]] && [[ -f "$path/apps/frappe/frappe/__init__.py" ]]; then
            local version_info=""
            if [[ -f "$path/apps/frappe/frappe/__version__.py" ]]; then
                version_info=$(grep -o 'version.*=.*[0-9]' "$path/apps/frappe/frappe/__version__.py" 2>/dev/null || echo "unknown")
            fi
            
            local branch_info=""
            if [[ -d "$path/apps/frappe/.git" ]]; then
                branch_info=$(cd "$path/apps/frappe" && git branch --show-current 2>/dev/null || echo "unknown")
            fi
            
            existing_installations+=("$path")
            installation_paths+=("Path: $path | Version: $version_info | Branch: $branch_info")
        fi
    done
    
    if [[ ${#existing_installations[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}⚠️  EXISTING ERPNEXT INSTALLATION(S) DETECTED ⚠️${NC}"
        echo ""
        echo -e "${YELLOW}Found the following ERPNext installation(s):${NC}"
        for info in "${installation_paths[@]}"; do
            echo -e "${LIGHT_BLUE}• $info${NC}"
        done
        echo ""
        echo -e "${RED}WARNING: Installing different ERPNext versions on the same server can cause:${NC}"
        echo -e "${YELLOW}• Port conflicts (Redis, Node.js services)${NC}"
        echo -e "${YELLOW}• Dependency version conflicts${NC}"
        echo -e "${YELLOW}• Supervisor configuration conflicts${NC}"
        echo -e "${YELLOW}• Database schema incompatibilities${NC}"
        echo -e "${YELLOW}• System instability${NC}"
        echo ""
        echo -e "${LIGHT_BLUE}Recommended actions:${NC}"
        echo -e "${GREEN}1. Use the existing installation if it meets your needs${NC}"
        echo -e "${GREEN}2. Backup and remove existing installation before installing new version${NC}"
        echo -e "${GREEN}3. Use a fresh server/container for the new installation${NC}"
        echo -e "${GREEN}4. Use different users/paths if you must have multiple versions${NC}"
        echo ""
        
        read -p "Do you want to continue anyway? (yes/no): " conflict_confirm
        conflict_confirm=$(echo "$conflict_confirm" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$conflict_confirm" != "yes" && "$conflict_confirm" != "y" ]]; then
            echo -e "${GREEN}Installation cancelled. Good choice for system stability!${NC}"
            exit 0
        else
            echo -e "${YELLOW}Proceeding with installation despite existing installations...${NC}"
            echo -e "${RED}You've been warned about potential conflicts!${NC}"
        fi
    else
        echo -e "${GREEN}✓ No existing ERPNext installations found.${NC}"
    fi
}

detect_best_branch() {
    local repo_url="$1"
    local preferred_version="$2"
    local repo_name="$3"
    
    echo -e "${LIGHT_BLUE}🔍 Detecting available branches for $repo_name...${NC}" >&2
    
    local branches=$(git ls-remote --heads "$repo_url" 2>/dev/null | awk '{print $2}' | sed 's|refs/heads/||' | sort -V)
    
    if [[ -z "$branches" ]]; then
        echo -e "${RED}⚠ Could not fetch branches from $repo_url${NC}" >&2
        echo ""
        return 1
    fi
    
    local branch_priorities=()
    
    case "$repo_name" in
        "crm"|"helpdesk"|"builder"|"drive"|"gameplan")
            echo -e "${YELLOW}🎯 Using 'main' branch for Frappe $repo_name (recommended)${NC}" >&2
            if echo "$branches" | grep -q "^main$"; then
                echo -e "${GREEN}✅ Selected branch: main${NC}" >&2
                echo "main"
                return 0
            elif echo "$branches" | grep -q "^master$"; then
                echo -e "${YELLOW}⚠ 'main' not found, falling back to 'master'${NC}" >&2
                echo "master"
                return 0
            fi
            ;;
        "hrms"|"lms")
            echo -e "${YELLOW}🎯 Detecting best branch for Frappe $repo_name...${NC}" >&2
            ;;
    esac
    
    case "$preferred_version" in
        "version-16")
            branch_priorities=("version-16" "develop" "main" "master" "version-15" "version-14")
            ;;
        "version-15"|"develop")
            branch_priorities=("version-15" "develop" "main" "master" "version-14" "version-13")
            ;;
        "version-14")
            branch_priorities=("version-14" "main" "master" "develop" "version-15" "version-13")
            ;;
        "version-13")
            branch_priorities=("version-13" "main" "master" "version-14" "develop" "version-15")
            ;;
        *)
            branch_priorities=("main" "master" "develop")
            ;;
    esac
    
    for priority_branch in "${branch_priorities[@]}"; do
        if echo "$branches" | grep -q "^$priority_branch$"; then
            echo -e "${GREEN}✅ Selected branch: $priority_branch${NC}" >&2
            echo "$priority_branch"
            return 0
        fi
    done
    
    local fallback_branch=$(echo "$branches" | head -1)
    echo -e "${YELLOW}⚠ Using fallback branch: $fallback_branch${NC}" >&2
    echo "$fallback_branch"
    return 0
}

echo -e "${LIGHT_BLUE}Welcome to the ERPNext Installer...${NC}"
echo -e "\n"
sleep 3

echo -e "${YELLOW}Please enter the number of the corresponding ERPNext version you wish to install:${NC}"

versions=("Version 13" "Version 14" "Version 15" "Version 16" "Develop")
select version_choice in "${versions[@]}"; do
    case $REPLY in
        1) bench_version="version-13"; break;;
        2) bench_version="version-14"; break;;
        3) bench_version="version-15"; break;;
        4) bench_version="version-16"; break;;
        5) bench_version="develop";
           echo ""
           echo -e "${RED}⚠️  WARNING: DEVELOP VERSION ⚠️${NC}"
           echo ""
           echo -e "${YELLOW}The develop branch contains bleeding-edge code that:${NC}"
           echo -e "${RED}• Changes daily and may be unstable${NC}"
           echo -e "${RED}• Can cause data corruption or system crashes${NC}"
           echo -e "${RED}• Is NOT suitable for production or important data${NC}"
           echo -e "${RED}• Has limited community support${NC}"
           echo ""
           echo -e "${GREEN}Recommended for: Experienced developers testing new features${NC}"
           echo -e "${GREEN}Better alternatives: Version 16 (latest stable) or Version 15 (proven)${NC}"
           echo ""
           read -p "Do you understand the risks and want to continue? (yes/no): " develop_confirm
           develop_confirm=$(echo "$develop_confirm" | tr '[:upper:]' '[:lower:]')

           if [[ "$develop_confirm" != "yes" && "$develop_confirm" != "y" ]]; then
               echo -e "${GREEN}Good choice! Please select a stable version.${NC}"
               continue
           else
               echo -e "${YELLOW}Proceeding with develop branch installation...${NC}"
           fi
           break;;
        *) echo -e "${RED}Invalid option. Please select a valid version.${NC}";;
    esac
done

echo -e "${GREEN}You have selected $version_choice for installation.${NC}"
echo -e "${LIGHT_BLUE}Do you wish to continue? (yes/no)${NC}"
read -p "Response: " continue_install
continue_install=$(echo "$continue_install" | tr '[:upper:]' '[:lower:]')

while [[ "$continue_install" != "yes" && "$continue_install" != "y" && "$continue_install" != "no" && "$continue_install" != "n" ]]; do
    echo -e "${RED}Invalid response. Please answer with 'yes' or 'no'.${NC}"
    echo -e "${LIGHT_BLUE}Do you wish to continue with the installation of $version_choice? (yes/no)${NC}"
    read -p "Response: " continue_install
    continue_install=$(echo "$continue_install" | tr '[:upper:]' '[:lower:]')
done

if [[ "$continue_install" == "no" || "$continue_install" == "n" ]]; then
    echo -e "${RED}Installation aborted by user.${NC}"
    exit 0
else
    echo -e "${GREEN}Proceeding with the installation of $version_choice.${NC}"
fi
sleep 2

check_existing_installations

#
# ─── OS COMPATIBILITY FOR VERSION-15 OR DEVELOP ────────────────────────────────────────
#
if [[ "$bench_version" == "version-15" || "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
    if [[ "$(lsb_release -si)" != "Ubuntu" && "$(lsb_release -si)" != "Debian" ]]; then
        echo -e "${RED}Your Distro is not supported for Version 15/16/Develop.${NC}"
        exit 1
    elif [[ "$(lsb_release -si)" == "Ubuntu" && "$(lsb_release -rs)" < "22.04" ]]; then
        echo -e "${RED}Your Ubuntu version is below the minimum required to support Version 15/16/Develop.${NC}"
        exit 1
    elif [[ "$(lsb_release -si)" == "Debian" && "$(lsb_release -rs)" < "12" ]]; then
        echo -e "${RED}Your Debian version is below the minimum required to support Version 15/16/Develop.${NC}"
        exit 1
    fi
fi

#
# ─── OS COMPATIBILITY FOR OLDER VERSIONS (version-13, version-14) ───────────────────────
#
if [[ "$bench_version" != "version-15" && "$bench_version" != "version-16" && "$bench_version" != "develop" ]]; then
    if [[ "$(lsb_release -si)" != "Ubuntu" && "$(lsb_release -si)" != "Debian" ]]; then
        echo -e "${RED}Your Distro is not supported for $version_choice.${NC}"
        exit 1
    elif [[ "$(lsb_release -si)" == "Ubuntu" && "$(lsb_release -rs)" > "22.04" ]]; then
        echo -e "${RED}Your Ubuntu version is not supported for $version_choice.${NC}"
        echo -e "${YELLOW}ERPNext v13/v14 only support Ubuntu up to 22.04. Please use ERPNext v15 or v16 for Ubuntu 24.04.${NC}"
        exit 1
    elif [[ "$(lsb_release -si)" == "Debian" && "$(lsb_release -rs)" > "11" ]]; then
        echo -e "${YELLOW}Warning: Your Debian version is above the tested range for $version_choice, but we'll continue.${NC}"
        sleep 2
    fi
fi

check_os

cd "$(sudo -u $USER echo $HOME)"

#
# ─── PRE-INSTALLATION WIZARD ──────────────────────────────────────────────────────────
# Collect all user input upfront so the installation runs unattended afterwards.
#
echo -e "\n${LIGHT_BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${LIGHT_BLUE}║         Pre-Installation Configuration           ║${NC}"
echo -e "${LIGHT_BLUE}║  Answer the questions below then sit back and    ║${NC}"
echo -e "${LIGHT_BLUE}║  let the installer do the rest automatically.    ║${NC}"
echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════════════╝${NC}\n"

# 1. SQL root password
echo -e "${YELLOW}[1/8] SQL root password${NC}"
sqlpasswrd=$(ask_twice "SQL root password" "true")
echo -e "\n"

# 2. Bench folder name
echo -e "${YELLOW}[2/8] Bench folder name${NC}"
read -p "Bench folder name (default: frappe-bench): " bench_name
bench_name=$(echo "${bench_name:-frappe-bench}" | tr -d '\r' | xargs)
echo ""

# 3. Site name / FQDN
echo -e "${YELLOW}[3/8] Site name${NC}"
read -p "Site name / FQDN (e.g. erp.mycompany.com): " site_name
site_name=$(echo "$site_name" | tr -d '\r' | xargs)
echo ""

# 4. Administrator password
echo -e "${YELLOW}[4/8] Administrator password${NC}"
adminpasswrd=$(ask_twice "Administrator password" "true")
echo -e "\n"

# 5. Install ERPNext?
echo -e "${YELLOW}[5/8] Install ERPNext?${NC}"
read -p "Install ERPNext on this site? (yes/no): " erpnext_install
erpnext_install=$(echo "$erpnext_install" | tr '[:upper:]' '[:lower:]' | tr -d '\r' | xargs)
while [[ "$erpnext_install" != "yes" && "$erpnext_install" != "y" && "$erpnext_install" != "no" && "$erpnext_install" != "n" ]]; do
    echo -e "${RED}Please answer yes or no.${NC}"
    read -p "Install ERPNext? (yes/no): " erpnext_install
    erpnext_install=$(echo "$erpnext_install" | tr '[:upper:]' '[:lower:]' | tr -d '\r' | xargs)
done
echo ""

# 6. Run mode: Production or Development
echo -e "${YELLOW}[6/8] Run mode${NC}"
echo -e "${GREEN}  1) Production  ${NC}${YELLOW}(nginx + supervisor, for live servers)${NC}"
echo -e "${GREEN}  2) Development ${NC}${YELLOW}(bench start, for local development)${NC}"
read -p "Select option [1/2]: " install_mode
install_mode=$(echo "$install_mode" | tr -d '\r' | xargs)
while [[ "$install_mode" != "1" && "$install_mode" != "2" ]]; do
    echo -e "${RED}Please enter 1 or 2.${NC}"
    read -p "Select option [1/2]: " install_mode
    install_mode=$(echo "$install_mode" | tr -d '\r' | xargs)
done
echo ""

# 7. Additional apps? (production only)
extra_apps_install="no"
if [[ "$install_mode" == "1" ]]; then
    echo -e "${YELLOW}[7/8] Additional Frappe apps${NC}"
    read -p "Install additional Frappe apps after ERPNext? (yes/no): " extra_apps_install
    extra_apps_install=$(echo "$extra_apps_install" | tr '[:upper:]' '[:lower:]' | tr -d '\r' | xargs)
    echo ""
fi

# 8. SSL? (production only)
continue_ssl="no"
email_address=""
if [[ "$install_mode" == "1" ]]; then
    echo -e "${YELLOW}[8/8] SSL certificate${NC}"
    read -p "Install SSL certificate? (yes/no): " continue_ssl
    continue_ssl=$(echo "$continue_ssl" | tr '[:upper:]' '[:lower:]' | tr -d '\r' | xargs)
    if [[ "$continue_ssl" == "yes" || "$continue_ssl" == "y" ]]; then
        read -p "Email address for SSL certificate: " email_address
        email_address=$(echo "$email_address" | tr -d '\r' | xargs)
    fi
    echo ""
fi

echo -e "${GREEN}Configuration complete. Starting installation...${NC}"
echo -e "${LIGHT_BLUE}────────────────────────────────────────────────────${NC}\n"
sleep 2

#
# ─── SYSTEM PACKAGE UPDATES ────────────────────────────────────────────────────────────
#
echo -e "${YELLOW}Updating system packages...${NC}"
sleep 2
sudo apt update
sudo apt upgrade -y
echo -e "${GREEN}System packages updated.${NC}"
sleep 2

#
# ─── PRELIMINARY PACKAGE INSTALL ──────────────────────────────────────────────────────
#
echo -e "${YELLOW}Installing preliminary package requirements${NC}"
sleep 3
sudo apt install software-properties-common git curl whiptail cron -y

# Install net-tools, nano, and ping and file utilities if not already present
for pkg in net-tools nano iputils-ping tmux file; do
    if ! dpkg -s "$pkg" &>/dev/null 2>&1; then
        echo -e "${YELLOW}Installing $pkg...${NC}"
        sudo apt install "$pkg" -y
    else
        echo -e "${GREEN}$pkg already installed, skipping.${NC}"
    fi
done

#
# ─── PYTHON AND REDIS INSTALL ───────────────────────────────────────────────────────────
#
echo -e "${YELLOW}Installing python environment manager and other requirements...${NC}"
sleep 2

py_version=$(python3 --version 2>&1 | awk '{print $2}')
py_major=$(echo "$py_version" | cut -d '.' -f 1)
py_minor=$(echo "$py_version" | cut -d '.' -f 2)

if [[ -z "$py_version" ]] || [[ "$py_major" -lt 3 ]] || [[ "$py_major" -eq 3 && "$py_minor" -lt 10 ]]; then
    echo -e "${LIGHT_BLUE}It appears this instance does not meet the minimum Python version required for ERPNext 14 (Python3.10)...${NC}"
    sleep 2 
    echo -e "${YELLOW}Not to worry, we will sort it out for you${NC}"
    sleep 4
    echo -e "${YELLOW}Installing Python 3.10+...${NC}"
    sleep 2

    sudo apt -qq install build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev \
        libssl-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev -y && \
    wget https://www.python.org/ftp/python/3.10.11/Python-3.10.11.tgz && \
    tar -xf Python-3.10.11.tgz && \
    cd Python-3.10.11 && \
    ./configure --prefix=/usr/local --enable-optimizations --enable-shared LDFLAGS="-Wl,-rpath /usr/local/lib" && \
    make -j "$(nproc)" && \
    sudo make altinstall && \
    cd .. && \
    sudo rm -rf Python-3.10.11 && \
    sudo rm Python-3.10.11.tgz && \
    pip3.10 install --user --upgrade pip && \
    echo -e "${GREEN}Python3.10 installation successful!${NC}"
    sleep 2
fi

# ─── PYTHON 3.14 FOR FRAPPE v16 ───────────────────────────────────────────────
# Python 3.14 is installed ONLY for the bench virtualenv.
# The system python3 is left untouched to avoid breaking ansible and other tools.
if [[ "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
    py14_bin=$(command -v python3.14 2>/dev/null || true)
    if [[ -z "$py14_bin" ]]; then
        echo -e "${YELLOW}Frappe v16 requires Python 3.14. Installing via uv...${NC}"
        sleep 2
        curl -LsSf https://astral.sh/uv/install.sh | sh
        source "$HOME/.local/bin/env" 2>/dev/null || export PATH="$HOME/.local/bin:$PATH"
        uv python install 3.14
        echo -e "${GREEN}Python 3.14 installed via uv. System python3 unchanged.${NC}"
    else
        echo -e "${GREEN}Python 3.14 already available at $py14_bin. OK.${NC}"
    fi
fi

echo -e "\n"
echo -e "${YELLOW}Installing additional Python packages and Redis Server${NC}"
sleep 2
sudo apt install git python3-dev python3-setuptools python3-venv python3-pip redis-server -y

#
# ─── WKHTMLTOPDF INSTALL ───────────────────────────────────────────────────────────────
#
arch=$(uname -m)
case $arch in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *) echo -e "${RED}Unsupported architecture: $arch${NC}"; exit 1 ;;
esac

sudo apt install fontconfig libxrender1 xfonts-75dpi xfonts-base -y

wk_os_version=$(lsb_release -rs)
if [[ "$DISTRO" == "Ubuntu" && ( "$wk_os_version" == "24.04" || "$wk_os_version" == "26.04" ) ]]; then
    echo -e "${YELLOW}Ubuntu $wk_os_version detected: installing wkhtmltopdf 0.12.6.1-3 (jammy build)...${NC}"
    # wkhtmltopdf 0.12.6 requires libssl1.1 which is absent on Ubuntu 24.04+
    if [[ "$arch" == "amd64" ]]; then
        libssl_url="http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb"
    else
        libssl_url="http://ports.ubuntu.com/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_arm64.deb"
    fi
    wget -q "$libssl_url" -O libssl1.1_compat.deb && \
    sudo dpkg -i libssl1.1_compat.deb && \
    rm -f libssl1.1_compat.deb
    wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_"$arch".deb && \
    sudo dpkg -i wkhtmltox_0.12.6.1-3.jammy_"$arch".deb || sudo apt --fix-broken install -y && \
    sudo dpkg -i wkhtmltox_0.12.6.1-3.jammy_"$arch".deb && \
    sudo cp /usr/local/bin/wkhtmlto* /usr/bin/ && \
    sudo chmod a+x /usr/bin/wk* && \
    sudo rm -f wkhtmltox_0.12.6.1-3.jammy_"$arch".deb && \
    sudo apt install fontconfig xvfb libfontconfig xfonts-base xfonts-75dpi libxrender1 -y
else
    wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_"$arch".deb && \
    sudo dpkg -i wkhtmltox_0.12.6.1-3.jammy_"$arch".deb || true && \
    sudo cp /usr/local/bin/wkhtmlto* /usr/bin/ && \
    sudo chmod a+x /usr/bin/wk* && \
    sudo rm -f wkhtmltox_0.12.6.1-3.jammy_"$arch".deb && \
    sudo apt --fix-broken install -y && \
    sudo apt install fontconfig xvfb libfontconfig xfonts-base xfonts-75dpi libxrender1 -y
fi

echo -e "${GREEN}Done!${NC}"
sleep 1
echo -e "\n"

#
# ─── MARIADB + DEV LIBRARIES + PKG-CONFIG ─────────────────────────────────────────────
#
echo -e "${YELLOW}Now installing MariaDB and other necessary packages...${NC}"
sleep 2

if [[ "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
    echo -e "${YELLOW}Frappe v16 requires MariaDB 11.4+. Adding official MariaDB repository...${NC}"
    sleep 2

    ubuntu_codename=$(lsb_release -cs)
    supported_mariadb_codenames=("focal" "jammy" "noble")
    mariadb_codename=""
    for _c in "${supported_mariadb_codenames[@]}"; do
        if [[ "$ubuntu_codename" == "$_c" ]]; then
            mariadb_codename="$_c"
            break
        fi
    done

    if [[ -z "$mariadb_codename" ]]; then
        echo -e "${YELLOW}Ubuntu '$ubuntu_codename' not yet supported by MariaDB repo setup.${NC}"
        # Check if Ubuntu's own repos already ship MariaDB 11.4+
        _av=$(apt-cache policy mariadb-server 2>/dev/null | awk '/Candidate:/{print $2}' | grep -oE '[0-9]+\.[0-9]+' | head -1)
        _av_major=$(echo "$_av" | cut -d. -f1)
        _av_minor=$(echo "$_av" | cut -d. -f2)
        if [[ -n "$_av" ]] && { [[ "$_av_major" -gt 11 ]] || { [[ "$_av_major" -eq 11 ]] && [[ "${_av_minor:-0}" -ge 4 ]]; }; }; then
            echo -e "${GREEN}MariaDB $_av found in Ubuntu '$ubuntu_codename' repos — no external repo needed.${NC}"
        else
            echo -e "${YELLOW}Adding MariaDB 11.4 repo (noble packages) as fallback...${NC}"
            sudo apt install -y apt-transport-https curl gnupg
            sudo mkdir -p /etc/apt/keyrings
            curl -LsS 'https://mariadb.org/mariadb_release_signing_key.pgp' \
                | gpg --dearmor \
                | sudo tee /etc/apt/keyrings/mariadb.gpg > /dev/null
            sudo chmod a+r /etc/apt/keyrings/mariadb.gpg
            echo "deb [signed-by=/etc/apt/keyrings/mariadb.gpg] https://downloads.mariadb.com/MariaDB/mariadb-11.4/repo/ubuntu noble main" \
                | sudo tee /etc/apt/sources.list.d/mariadb.list
        fi
    else
        curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version="mariadb-11.4"
    fi

    sudo apt update
    sudo apt install mariadb-server mariadb-client -y
    echo -e "${YELLOW}Installing MariaDB development libraries (libmariadb-dev) for Frappe v16...${NC}"
    sleep 1
    sudo apt install pkg-config libmariadb-dev -y
else
    sudo apt install mariadb-server mariadb-client -y
    echo -e "${YELLOW}Installing MySQL/MariaDB development libraries and pkg-config...${NC}"
    sleep 1
    sudo apt install pkg-config default-libmysqlclient-dev -y
fi

echo -e "${GREEN}MariaDB and development packages have been installed successfully.${NC}"
sleep 2

MARKER_FILE=~/.mysql_configured.marker
if [ ! -f "$MARKER_FILE" ]; then
    echo -e "${YELLOW}Now we'll go ahead to apply MariaDB security settings...${NC}"
    sleep 2

    sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$sqlpasswrd';"
    sudo mysql -u root -p"$sqlpasswrd" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$sqlpasswrd';"
    sudo mysql -u root -p"$sqlpasswrd" -e "DELETE FROM mysql.user WHERE User='';"
    sudo mysql -u root -p"$sqlpasswrd" -e "DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    sudo mysql -u root -p"$sqlpasswrd" -e "FLUSH PRIVILEGES;"

    echo -e "${YELLOW}...And writing MariaDB charset config to /etc/mysql/mariadb.conf.d/99-frappe.cnf:${NC}"
    sleep 2

    sudo tee /etc/mysql/mariadb.conf.d/99-frappe.cnf > /dev/null <<'EOF'
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF

    sudo systemctl restart mariadb

    touch "$MARKER_FILE"
    echo -e "${GREEN}MariaDB settings done!${NC}"
    echo -e "\n"
    sleep 1
fi

#
# ─── NVM / NODE / YARN INSTALL ─────────────────────────────────────────────────────────
#
echo -e "${YELLOW}Now to install Node, npm and yarn${NC}"
sleep 2

os_version=$(lsb_release -rs)
if [[ "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
    # v16: install Node 24 system-wide via NodeSource (no NVM)
    # This ensures 'node' is available in PATH for all processes including bench start
    echo -e "${YELLOW}Installing Node 24 from NodeSource (system-wide)...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
    sudo apt install nodejs -y
    node_version="24"
    sudo npm install -g yarn@1.22.19
    echo -e "${GREEN}Node $(node --version) and Yarn $(yarn --version) installed system-wide.${NC}"
else
    # v13/v14/v15: use NVM as before
    curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash

    nvm_init='export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'

    grep -qxF 'export NVM_DIR="$HOME/.nvm"' ~/.profile 2>/dev/null || echo "$nvm_init" >> ~/.profile
    grep -qxF 'export NVM_DIR="$HOME/.nvm"' ~/.bashrc 2>/dev/null || echo "$nvm_init" >> ~/.bashrc

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

    if [[ "$bench_version" == "version-15" ]] || [[ "$DISTRO" == "Ubuntu" && "$os_version" == "24.04" ]]; then
        nvm install 20
        nvm alias default 20
        node_version="20"
    elif [[ "$bench_version" == "version-14" || "$bench_version" == "version-13" ]]; then
        nvm install 18
        nvm alias default 18
        node_version="18"
    else
        nvm install 16
        nvm alias default 16
        node_version="16"
    fi

    nvm use default
    npm install -g yarn@1.22.19
    echo -e "${GREEN}nvm and Node (v${node_version}) installed.${NC}"
    echo -e "${GREEN}Yarn v$(yarn --version) (Classic) installed globally.${NC}"

    # Symlink using real NVM bin path to avoid circular symlink issues
    NVM_BIN="$NVM_DIR/versions/node/$(nvm version)/bin"
    sudo ln -sf "$NVM_BIN/node" /usr/local/bin/node
    sudo ln -sf "$NVM_BIN/npm"  /usr/local/bin/npm
    sudo ln -sf "$NVM_BIN/yarn" /usr/local/bin/yarn
fi
sleep 2

if [[ -z "$py_version" ]] || [[ "$py_major" -lt 3 ]] || [[ "$py_major" -eq 3 && "$py_minor" -lt 10 ]]; then
    python3.10 -m venv "$USER"
    source "$USER/bin/activate"
    nvm use default
fi

#
# ─── BENCH INSTALL ───────────────────────────────────────────────────────────────────────
#
echo -e "${YELLOW}Now let's install bench${NC}"
sleep 2

if [[ "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
    # v16: use uv for faster, isolated bench install (recommended by Frappe docs)
    echo -e "${YELLOW}Installing/updating uv package manager...${NC}"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    source "$HOME/.local/bin/env" 2>/dev/null || export PATH="$HOME/.local/bin:$PATH"
    uv tool install frappe-bench --python python3.14 --force
    echo -e "${GREEN}frappe-bench installed via uv with Python 3.14.${NC}"
else
    externally_managed_file=$(find /usr/lib/python3.*/EXTERNALLY-MANAGED 2>/dev/null || true)
    if [[ -n "$externally_managed_file" ]]; then
        sudo python3 -m pip config --global set global.break-system-packages true
    fi
    sudo apt install python3-pip -y
    # --ignore-installed avoids conflicts with system packages (e.g. click, six)
    # that apt installed without a pip RECORD file and therefore cannot be uninstalled by pip
    sudo pip3 install --ignore-installed frappe-bench

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm use default
fi

echo -e "${YELLOW}Initialising bench in $bench_name folder.${NC}"
echo -e "${LIGHT_BLUE}If you get a restart failed, don't worry, we will resolve that later.${NC}"
if [[ "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
    bench init "$bench_name" --version "$bench_version" --python python3.14 --verbose
else
    bench init "$bench_name" --version "$bench_version" --verbose
fi
echo -e "${GREEN}Bench installation complete!${NC}"
sleep 1

#
# ─── NEW SITE CREATION ─────────────────────────────────────────────────────────────────
#
echo -e "${YELLOW}Now creating your Frappe site: ${GREEN}$site_name${NC}"
sleep 1
echo -e "${YELLOW}Now setting up your site. This might take a few minutes. Please wait...${NC}"
sleep 1

cd "$bench_name" && \
sudo chmod -R o+rx "$(echo $HOME)"

if [[ "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
    bench new-site "$site_name" \
      --db-root-username root \
      --db-root-password "$sqlpasswrd" \
      --admin-password "$adminpasswrd" \
      --no-mariadb-socket
else
    bench new-site "$site_name" \
      --db-root-username root \
      --db-root-password "$sqlpasswrd" \
      --admin-password "$adminpasswrd"
fi

redis_port_is_ready() {
    local port="$1"

    redis-cli -h 127.0.0.1 -p "$port" ping 2>/dev/null | grep -q PONG
}

start_temp_redis() {
    local name="$1"
    local port="$2"
    local config_file="config/redis_${name}.conf"

    if redis_port_is_ready "$port"; then
        echo -e "${GREEN}Redis $name already running on port $port.${NC}"
        return 0
    fi

    if [[ -f "$config_file" ]]; then
        redis-server "$config_file" --daemonize yes
    else
        redis-server --bind 127.0.0.1 --port "$port" --daemonize yes --dir "$PWD" --dbfilename "redis-${name}.rdb"
    fi

    for _ in {1..10}; do
        if redis_port_is_ready "$port"; then
            echo -e "${GREEN}Redis $name started on port $port.${NC}"
            return 0
        fi
        sleep 1
    done

    echo -e "${RED}Redis $name did not start on port $port.${NC}"
    exit 1
}

if [[ "$bench_version" == "version-15" || "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
    echo -e "${YELLOW}Starting Redis instances for $bench_version (queue, cache, and socketio)...${NC}"
    sleep 1
    bench setup redis
    start_temp_redis queue 11000
    start_temp_redis cache 12000
    start_temp_redis socketio 13000
    echo -e "${GREEN}Redis instances are ready on ports 11000, 12000, 13000.${NC}"
    sleep 1
fi

echo -e "${LIGHT_BLUE}ERPNext install: $erpnext_install${NC}"

case "$erpnext_install" in
    "yes"|"y")
    sleep 2
    bench get-app erpnext --branch "$bench_version" && \
    bench --site "$site_name" install-app erpnext
    echo -e "${YELLOW}Clearing cache...${NC}"
    bench --site "$site_name" clear-cache
    sleep 1
    ;;
esac

# Kill temporary Redis instances started for v15/v16/develop install-app
# bench start and bench setup production manage Redis on their own
if [[ "$bench_version" == "version-15" || "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
    echo -e "${YELLOW}Stopping temporary Redis instances...${NC}"
    sudo pkill -f "redis-server.*11000" 2>/dev/null || true
    sudo pkill -f "redis-server.*12000" 2>/dev/null || true
    sudo pkill -f "redis-server.*13000" 2>/dev/null || true
    echo -e "${GREEN}Temporary Redis instances stopped. Ports freed for bench.${NC}"
    sleep 1
fi

playbook_file=$(find /usr /root "$HOME" -path "*/bench/playbooks/roles/mariadb/tasks/main.yml" 2>/dev/null | head -1)
if [[ -n "$playbook_file" ]]; then
    echo -e "${YELLOW}Patching bench MariaDB playbook at $playbook_file...${NC}"
    sudo sed -i 's/- include: /- include_tasks: /g' "$playbook_file"
    echo -e "${GREEN}Playbook patched.${NC}"
else
    echo -e "${YELLOW}bench MariaDB playbook not found, skipping patch (may not be needed).${NC}"
fi

case "$install_mode" in
    "1") continue_prod="yes" ;;
    "2") continue_prod="no"  ;;
esac
echo -e "${LIGHT_BLUE}Run mode: $([ "$install_mode" == "1" ] && echo 'Production' || echo 'Development')${NC}"

case "$continue_prod" in
    "yes")
        echo -e "${YELLOW}Installing packages and dependencies for Production...${NC}"
        sleep 2

        sudo apt install supervisor nginx fail2ban -y
        sudo systemctl enable supervisor nginx
        sudo systemctl start supervisor nginx

        if [[ "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
            # v16: bench setup production uses ansible which breaks with Python 3.14.
            # Set up nginx and supervisor manually using bench-generated configs.
            echo -e "${YELLOW}Setting up production for Frappe v16 (manual config, no ansible)...${NC}"
            sleep 1

            # Generate configs
            bench setup socketio
            bench setup redis
            yes | bench setup supervisor --yes
            bench setup nginx

            # Link supervisor config
            sudo ln -sf "$(pwd)/config/supervisor.conf" /etc/supervisor/conf.d/frappe-bench.conf

            # Link nginx config
            # Replace 'main' log format (not defined in Ubuntu nginx) with 'combined'
            sed -i 's/ main;/ combined;/g' "$(pwd)/config/nginx.conf"
            sudo ln -sf "$(pwd)/config/nginx.conf" /etc/nginx/conf.d/frappe-bench.conf
            sudo nginx -t && sudo systemctl reload nginx

            # Fix supervisor ownership
            FILE="/etc/supervisor/supervisord.conf"
            SEARCH_PATTERN="chown=$USER:$USER"
            if grep -q "$SEARCH_PATTERN" "$FILE" 2>/dev/null; then
                sudo sed -i "/chown=.*/c $SEARCH_PATTERN" "$FILE"
            else
                sudo sed -i "5a $SEARCH_PATTERN" "$FILE"
            fi

            sudo supervisorctl reread
            sudo supervisorctl update
            sudo supervisorctl reload

        else
            # v13/v14/v15: use ansible-based bench setup production
            yes | sudo bench setup production "$USER"

            echo -e "${YELLOW}Applying necessary permissions to supervisor...${NC}"
            sleep 1

            FILE="/etc/supervisor/supervisord.conf"
            SEARCH_PATTERN="chown=$USER:$USER"
            if grep -q "$SEARCH_PATTERN" "$FILE" 2>/dev/null; then
                sudo sed -i "/chown=.*/c $SEARCH_PATTERN" "$FILE"
            else
                sudo sed -i "5a $SEARCH_PATTERN" "$FILE"
            fi

            sudo service supervisor restart
            yes | sudo bench setup production "$USER"

            # Fix nginx log format 'main' not defined in Ubuntu nginx
            sed -i 's/ main;/ combined;/g' "$(pwd)/config/nginx.conf" 2>/dev/null || true
            sudo nginx -t && sudo systemctl reload nginx

            if [[ "$bench_version" == "version-15" ]]; then
                echo -e "${YELLOW}Setting up Socketio, Redis and Supervisor for v15...${NC}"
                bench setup socketio
                yes | bench setup supervisor
                bench setup redis
                sudo supervisorctl reload
            fi
        fi

        echo -e "${YELLOW}Enabling Scheduler...${NC}"
        bench --site "$site_name" scheduler enable
        bench --site "$site_name" scheduler resume

        echo -e "${YELLOW}Restarting all services...${NC}"
        sudo chmod 755 "$(echo $HOME)"
        sudo systemctl restart redis-server
        sleep 2
        sudo supervisorctl restart all
        sleep 3

        printf "${GREEN}Production setup complete! "
        printf '\xF0\x9F\x8E\x86'
        printf "${NC}\n"
        sleep 3

        #
        # ─── ADDITIONAL APPS INSTALL SECTION ────────────────────────────────
        #
        case "$extra_apps_install" in
            "yes"|"y")
                echo ""
                echo -e "${YELLOW}⚠️  Additional Apps Installation${NC}"
                echo -e "${LIGHT_BLUE}Note: App compatibility may vary. Some apps might fail to install${NC}"
                echo -e "${LIGHT_BLUE}due to version mismatches or missing dependencies.${NC}"
                echo ""
                echo -e "${GREEN}Apps courtesy of awesome-frappe by Gavin D'Souza (@gavindsouza)${NC}"
                echo -e "${GREEN}Repository: https://github.com/gavindsouza/awesome-frappe${NC}"
                echo ""
                echo -e "${GREEN}Proceeding with additional apps installation...${NC}"
                    echo ""
                    
                    echo -e "${YELLOW}Fetching available apps from awesome-frappe repository...${NC}"
                tmp_dir=$(mktemp -d)
                
                if ! git clone https://github.com/gavindsouza/awesome-frappe.git "$tmp_dir" --depth 1 2>/dev/null; then
                    echo -e "${RED}Failed to clone awesome-frappe repository. Skipping additional apps installation.${NC}"
                    rm -rf "$tmp_dir"
                else
                    if [[ ! -f "$tmp_dir/README.md" ]]; then
                        echo -e "${RED}README.md not found in awesome-frappe repository. Skipping additional apps installation.${NC}"
                        rm -rf "$tmp_dir"
                    else
                        mapfile -t raw_entries < <(
                            {
                                grep -oE '\[([^]]+)\]\(https://github\.com/[^)]*\)' "$tmp_dir/README.md" 2>/dev/null || true
                                grep -oE '\[([^]]+)\]\(https://frappecloud\.com/marketplace/[^)]*\)' "$tmp_dir/README.md" 2>/dev/null || true
                                grep -oE '\[([^]]+)\]\(https://frappe\.io/[^)]*\)' "$tmp_dir/README.md" 2>/dev/null || true
                                
                                echo "[Frappe HR](https://github.com/frappe/hrms.git)"
                                echo "[Frappe LMS](https://github.com/frappe/lms.git)"
                                echo "[Frappe CRM](https://github.com/frappe/crm.git)"
                                echo "[Frappe Helpdesk](https://github.com/frappe/helpdesk.git)"
                                echo "[Frappe Builder](https://github.com/frappe/builder.git)"
                                echo "[Frappe Drive](https://github.com/frappe/drive.git)"
                                echo "[Frappe Gameplan](https://github.com/frappe/gameplan.git)"
                            } | sort -u
                        )

                        if [ "${#raw_entries[@]}" -eq 0 ]; then
                            echo -e "${RED}No GitHub repository links found in awesome-frappe README. Skipping.${NC}"
                            rm -rf "$tmp_dir"
                        else
                            declare -a display_names=()
                            declare -a repo_names=()
                            declare -a url_array=()
                            
                            if [[ "$bench_version" == "version-15" || "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
                                echo -e "${YELLOW}Checking app compatibility with $bench_version...${NC}"
                                echo -e "${LIGHT_BLUE}This may take a moment, please wait...${NC}"
                                
                                total_apps=${#raw_entries[@]}
                                current_app=0
                                compatible_count=0
                                
                                for entry in "${raw_entries[@]}"; do
                                    current_app=$((current_app + 1))
                                    
                                    echo -ne "\r${LIGHT_BLUE}Progress: $current_app/$total_apps apps checked...${NC}"
                                    
                                    display_name=$(echo "$entry" | sed -E 's/\[([^]]+)\]\(.*/\1/')
                                    
                                    url=$(echo "$entry" | sed -E 's/.*\(([^)]+)\).*/\1/')
                                    
                                    repo_url=""
                                    repo_name=""
                                    
                                    if [[ "$url" =~ ^https://github\.com/[^/]+/[^/]+/?$ ]]; then
                                        repo_url="$url"
                                        if [[ ! "$repo_url" =~ \.git$ ]]; then
                                            repo_url="${repo_url}.git"
                                        fi
                                        repo_name=$(basename "$repo_url" .git)
                                    elif [[ "$url" =~ ^https://frappecloud\.com/marketplace/ ]] || [[ "$url" =~ ^https://github\.com/frappe/ ]]; then
                                        case "$display_name" in
                                            "Frappe HR"|"HRMS")
                                                repo_url="https://github.com/frappe/hrms.git"
                                                repo_name="hrms"
                                                ;;
                                            "Frappe LMS")
                                                repo_url="https://github.com/frappe/lms.git"
                                                repo_name="lms"
                                                ;;
                                            "Frappe CRM")
                                                repo_url="https://github.com/frappe/crm.git"
                                                repo_name="crm"
                                                ;;
                                            "Frappe Helpdesk")
                                                repo_url="https://github.com/frappe/helpdesk.git"
                                                repo_name="helpdesk"
                                                ;;
                                            "Frappe Builder")
                                                repo_url="https://github.com/frappe/builder.git"
                                                repo_name="builder"
                                                ;;
                                            "Frappe Drive")
                                                repo_url="https://github.com/frappe/drive.git"
                                                repo_name="drive"
                                                ;;
                                            "Frappe Gameplan")
                                                repo_url="https://github.com/frappe/gameplan.git"
                                                repo_name="gameplan"
                                                ;;
                                            *)
                                                if [[ "$url" =~ ^https://github\.com/ ]]; then
                                                    repo_url="$url"
                                                    if [[ ! "$repo_url" =~ \.git$ ]]; then
                                                        repo_url="${repo_url}.git"
                                                    fi
                                                    repo_name=$(basename "$repo_url" .git)
                                                else
                                                    continue
                                                fi
                                                ;;
                                        esac
                                    else
                                        continue
                                    fi
                                    
                                    if [[ "$repo_name" == ".git" || "$repo_name" == "" ]]; then
                                        continue
                                    fi
                                    
                                    repo_check_dir=$(mktemp -d)
                                    
                                    if git clone "$repo_url" "$repo_check_dir" --depth 1 --quiet 2>/dev/null; then
                                        if [[ -f "$repo_check_dir/pyproject.toml" ]]; then
                                            display_names+=("$display_name")
                                            repo_names+=("$repo_name")
                                            url_array+=("$repo_url")
                                            compatible_count=$((compatible_count + 1))
                                        fi
                                    fi
                                    
                                    rm -rf "$repo_check_dir"
                                done
                                
                                echo -e "\r${GREEN}✓ Compatibility check complete: $compatible_count/$total_apps apps are compatible with $bench_version${NC}"
                                
                            else
                                echo -e "${YELLOW}Processing available apps for $bench_version...${NC}"
                                
                                for entry in "${raw_entries[@]}"; do
                                    display_name=$(echo "$entry" | sed -E 's/\[([^]]+)\]\(.*/\1/')
                                    
                                    url=$(echo "$entry" | sed -E 's/.*\(([^)]+)\).*/\1/')
                                    
                                    repo_url=""
                                    repo_name=""
                                    
                                    if [[ "$url" =~ ^https://github\.com/[^/]+/[^/]+/?$ ]]; then
                                        repo_url="$url"
                                        if [[ ! "$repo_url" =~ \.git$ ]]; then
                                            repo_url="${repo_url}.git"
                                        fi
                                        repo_name=$(basename "$repo_url" .git)
                                    elif [[ "$url" =~ ^https://frappecloud\.com/marketplace/ ]] || [[ "$url" =~ ^https://github\.com/frappe/ ]]; then
                                        case "$display_name" in
                                            "Frappe HR"|"HRMS")
                                                repo_url="https://github.com/frappe/hrms.git"
                                                repo_name="hrms"
                                                ;;
                                            "Frappe LMS")
                                                repo_url="https://github.com/frappe/lms.git"
                                                repo_name="lms"
                                                ;;
                                            "Frappe CRM")
                                                repo_url="https://github.com/frappe/crm.git"
                                                repo_name="crm"
                                                ;;
                                            "Frappe Helpdesk")
                                                repo_url="https://github.com/frappe/helpdesk.git"
                                                repo_name="helpdesk"
                                                ;;
                                            "Frappe Builder")
                                                repo_url="https://github.com/frappe/builder.git"
                                                repo_name="builder"
                                                ;;
                                            "Frappe Drive")
                                                repo_url="https://github.com/frappe/drive.git"
                                                repo_name="drive"
                                                ;;
                                            "Frappe Gameplan")
                                                repo_url="https://github.com/frappe/gameplan.git"
                                                repo_name="gameplan"
                                                ;;
                                            *)
                                                if [[ "$url" =~ ^https://github\.com/ ]]; then
                                                    repo_url="$url"
                                                    if [[ ! "$repo_url" =~ \.git$ ]]; then
                                                        repo_url="${repo_url}.git"
                                                    fi
                                                    repo_name=$(basename "$repo_url" .git)
                                                else
                                                    continue
                                                fi
                                                ;;
                                        esac
                                    else
                                        continue
                                    fi
                                    
                                    if [[ "$repo_name" == ".git" || "$repo_name" == "" ]]; then
                                        continue
                                    fi
                                    
                                    display_names+=("$display_name")
                                    repo_names+=("$repo_name")
                                    url_array+=("$repo_url")
                                done
                                
                                echo -e "${GREEN}✓ Found ${#display_names[@]} apps available for $bench_version${NC}"
                            fi

                            declare -a unique_display_names=()
                            declare -a unique_repo_names=()
                            declare -a unique_urls=()
                            declare -A seen_repos=()
                            
                            for i in "${!repo_names[@]}"; do
                                if [[ -z "${seen_repos[${repo_names[$i]}]}" ]]; then
                                    seen_repos["${repo_names[$i]}"]=1
                                    unique_display_names+=("${display_names[$i]}")
                                    unique_repo_names+=("${repo_names[$i]}")
                                    unique_urls+=("${url_array[$i]}")
                                fi
                            done

                            declare -a sorted_indices=()
                            readarray -t sorted_indices < <(
                                for i in "${!unique_display_names[@]}"; do
                                    echo "$i ${unique_display_names[$i]}"
                                done | sort -k2 | cut -d' ' -f1
                            )

                            declare -a final_display_names=()
                            declare -a final_repo_names=()
                            declare -a final_urls=()
                            
                            for i in "${sorted_indices[@]}"; do
                                final_display_names+=("${unique_display_names[$i]}")
                                final_repo_names+=("${unique_repo_names[$i]}")
                                final_urls+=("${unique_urls[$i]}")
                            done

                            display_names=("${final_display_names[@]}")
                            repo_names=("${final_repo_names[@]}")
                            url_array=("${final_urls[@]}")

                            if [ "${#display_names[@]}" -eq 0 ]; then
                                if [[ "$bench_version" == "version-15" || "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
                                    echo -e "${RED}No apps with pyproject.toml found that are compatible with $bench_version.${NC}"
                                    echo -e "${YELLOW}ERPNext v15/v16/develop requires apps to have pyproject.toml files.${NC}"
                                else
                                    echo -e "${RED}No valid Frappe apps found in awesome-frappe README.${NC}"
                                fi
                                rm -rf "$tmp_dir"
                            else
                                if [[ "$bench_version" == "version-15" || "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
                                    echo -e "${GREEN}Found ${#display_names[@]} compatible apps with pyproject.toml for $bench_version.${NC}"
                                else
                                    echo -e "${GREEN}Found ${#display_names[@]} available apps for $bench_version.${NC}"
                                fi

                                terminal_height=$(tput lines 2>/dev/null || echo 24)
                                terminal_width=$(tput cols 2>/dev/null || echo 80)
                                
                                max_dialog_height=$((terminal_height - 4))
                                max_dialog_width=$((terminal_width - 10))
                                
                                max_display_len=0
                                for name in "${display_names[@]}"; do
                                    if (( ${#name} > 50 )); then
                                        name="${name:0:47}..."
                                    fi
                                    if (( ${#name} > max_display_len )); then
                                        max_display_len=${#name}
                                    fi
                                done
                                
                                dialog_width=$((max_display_len + 25))
                                if (( dialog_width < 60 )); then
                                    dialog_width=60
                                elif (( dialog_width > max_dialog_width )); then
                                    dialog_width=$max_dialog_width
                                fi
                                
                                item_count=${#display_names[@]}
                                dialog_height=$((item_count + 8))
                                if (( dialog_height > max_dialog_height )); then
                                    dialog_height=$max_dialog_height
                                fi

                                OPTIONS=()
                                for i in "${!display_names[@]}"; do
                                    display_name="${display_names[$i]}"
                                    
                                    if (( ${#display_name} > 50 )); then
                                        display_name="${display_name:0:47}..."
                                    fi
                                    
                                    OPTIONS+=("$display_name" "" OFF)
                                done

                                CHOICES=$(whiptail --title "Additional Frappe Apps (${#display_names[@]} available)" \
                                    --checklist "Choose apps to install (Space=toggle, Enter=confirm):" \
                                    "$dialog_height" "$dialog_width" "$((dialog_height - 8))" \
                                    "${OPTIONS[@]}" 3>&1 1>&2 2>&3) || {
                                    echo -e "${RED}No apps selected or dialog cancelled. Skipping additional apps installation.${NC}"
                                    rm -rf "$tmp_dir"
                                }

                                if [ -z "$CHOICES" ]; then
                                    echo -e "${RED}No apps selected. Skipping additional apps installation.${NC}"
                                    rm -rf "$tmp_dir"
                                else
                                    eval "selected_display_names=($CHOICES)"

                                    echo -e "${GREEN}Selected ${#selected_display_names[@]} apps for installation.${NC}"

                                    installation_errors=()
                                    successful_installations=()
                                    
                                    for selected_display_name in "${selected_display_names[@]}"; do
                                        selected_repo=""
                                        selected_url=""
                                        
                                        for idx in "${!display_names[@]}"; do
                                            if [[ "${display_names[$idx]}" == "$selected_display_name" ]]; then
                                                selected_repo="${repo_names[$idx]}"
                                                selected_url="${url_array[$idx]}"
                                                break
                                            fi
                                        done

                                        if [[ -z "$selected_url" ]]; then
                                            echo -e "${RED}Could not find URL for \"$selected_display_name\". Skipping.${NC}"
                                            installation_errors+=("$selected_display_name: URL not found")
                                            continue
                                        fi

                                        echo -e "${YELLOW}Installing \"$selected_display_name\" ($selected_repo)...${NC}"
                                        echo -e "${LIGHT_BLUE}Repository: $selected_url${NC}"

                                        echo -e "${YELLOW}Step 1/2: Downloading app...${NC}"
                                        
                                        echo -e "${LIGHT_BLUE}🔄 Detecting optimal branch for $selected_repo...${NC}"
                                        best_branch=$(detect_best_branch "$selected_url" "$bench_version" "$selected_repo")
                                        
                                        if [[ -z "$best_branch" ]]; then
                                            echo -e "${RED}⚠ Could not detect any branches for $selected_repo. Skipping.${NC}"
                                            installation_errors+=("$selected_display_name: No branches detected")
                                            continue
                                        fi
                                        
                                        echo -e "${GREEN}📌 Will install using branch: $best_branch${NC}"
                                        echo ""
                                        
                                        download_success=false
                                        
                                        echo -e "${YELLOW}🔽 Downloading from branch '$best_branch'...${NC}"
                                        if bench get-app "$selected_url" --branch "$best_branch" --skip-assets 2>/tmp/bench_error_$.log; then
                                            download_success=true
                                            echo -e "${GREEN}✅ Successfully downloaded \"$selected_display_name\" from branch '$best_branch'.${NC}"
                                        else
                                            echo -e "${RED}❌ Failed to download from branch '$best_branch'.${NC}"
                                            if [[ -f /tmp/bench_error_$.log ]]; then
                                                echo -e "${LIGHT_BLUE}Error details:${NC}"
                                                tail -2 /tmp/bench_error_$.log
                                            fi
                                        fi
                                        
                                        if [ "$download_success" = true ]; then
                                            echo -e "${YELLOW}Step 2/2: Installing to site...${NC}"
                                            app_installed=false
                                            
                                            app_dir="apps/$selected_repo"
                                            setup_py_path="$app_dir/setup.py"
                                            
                                            if [[ -f "$setup_py_path" ]]; then
                                                extracted_app_name=$(extract_app_name_from_setup "$setup_py_path")
                                                
                                                if [[ -n "$extracted_app_name" ]]; then
                                                    echo -e "${LIGHT_BLUE}Found app name in setup.py: \"$extracted_app_name\"${NC}"
                                                    if bench --site "$site_name" install-app "$extracted_app_name" 2>/dev/null; then
                                                        echo -e "${GREEN}✓ Successfully installed using setup.py name.${NC}"
                                                        successful_installations+=("$selected_display_name (branch: $best_branch)")
                                                        app_installed=true
                                                    else
                                                        echo -e "${YELLOW}⚠ Setup.py name failed, trying alternatives...${NC}"
                                                    fi
                                                else
                                                    echo -e "${YELLOW}⚠ Could not extract name from setup.py, trying alternatives...${NC}"
                                                fi
                                            fi
                                            
                                            if [[ "$app_installed" == false ]]; then
                                                echo -e "${LIGHT_BLUE}Trying repo name: \"$selected_repo\"${NC}"
                                                if bench --site "$site_name" install-app "$selected_repo" 2>/dev/null; then
                                                    echo -e "${GREEN}✓ Successfully installed using repo name.${NC}"
                                                    successful_installations+=("$selected_display_name (branch: $best_branch)")
                                                    app_installed=true
                                                fi
                                            fi
                                            
                                            if [[ "$app_installed" == false ]]; then
                                                transformed_name=$(echo "$selected_repo" | sed -E 's/^(frappe[-_]?|erpnext[-_]?)//' | tr '-' '_' | tr '[:upper:]' '[:lower:]')
                                                
                                                if [[ "$transformed_name" != "$selected_repo" ]]; then
                                                    echo -e "${LIGHT_BLUE}Trying transformed name: \"$transformed_name\"${NC}"
                                                    if bench --site "$site_name" install-app "$transformed_name" 2>/dev/null; then
                                                        echo -e "${GREEN}✓ Successfully installed using transformed name.${NC}"
                                                        successful_installations+=("$selected_display_name (branch: $best_branch)")
                                                        app_installed=true
                                                    fi
                                                fi
                                            fi
                                            
                                            if [[ "$app_installed" == false ]]; then
                                                lowercase_name=$(echo "$selected_repo" | tr '[:upper:]' '[:lower:]')
                                                if [[ "$lowercase_name" != "$selected_repo" ]]; then
                                                    echo -e "${LIGHT_BLUE}Trying lowercase: \"$lowercase_name\"${NC}"
                                                    if bench --site "$site_name" install-app "$lowercase_name" 2>/dev/null; then
                                                        echo -e "${GREEN}✓ Successfully installed using lowercase name.${NC}"
                                                        successful_installations+=("$selected_display_name (branch: $best_branch)")
                                                        app_installed=true
                                                    fi
                                                fi
                                            fi
                                            
                                            if [[ "$app_installed" == false && -d "$app_dir" ]]; then
                                                for subdir in "$app_dir"/*/; do
                                                    if [[ -d "$subdir" && -f "$subdir/__init__.py" ]]; then
                                                        potential_app_name=$(basename "$subdir")
                                                        if [[ "$potential_app_name" != "tests" && "$potential_app_name" != "docs" && "$potential_app_name" != "__pycache__" ]]; then
                                                            echo -e "${LIGHT_BLUE}Trying directory name: \"$potential_app_name\"${NC}"
                                                            if bench --site "$site_name" install-app "$potential_app_name" 2>/dev/null; then
                                                                echo -e "${GREEN}✓ Successfully installed using directory name.${NC}"
                                                                successful_installations+=("$selected_display_name (branch: $best_branch)")
                                                                app_installed=true
                                                                break
                                                            fi
                                                        fi
                                                    fi
                                                done
                                            fi
                                            
                                            if [[ "$app_installed" == false ]]; then
                                                echo -e "${RED}✗ Failed to install \"$selected_display_name\" after trying all strategies.${NC}"
                                                echo -e "${YELLOW}This app may have compatibility issues with ERPNext $bench_version or missing dependencies.${NC}"
                                                installation_errors+=("$selected_display_name (branch: $best_branch): Installation failed (compatibility/dependency issues)")
                                            fi
                                            
                                            rm -f /tmp/bench_error_$.log
                                        else
                                            if [[ -d "apps/$selected_repo" ]]; then
                                                echo -e "${YELLOW}⚠ App was cloned but failed during pip install phase.${NC}"
                                                echo -e "${RED}✗ \"$selected_display_name\" has dependency/compatibility issues with ERPNext $bench_version.${NC}"
                                                
                                                if [[ -f /tmp/bench_error_$.log ]]; then
                                                    echo -e "${LIGHT_BLUE}Error details:${NC}"
                                                    tail -3 /tmp/bench_error_$.log | grep -E "(ERROR|Failed|returned non-zero)" || echo "Check app requirements and compatibility."
                                                fi
                                                
                                                installation_errors+=("$selected_display_name (branch: $best_branch): Dependency/compatibility issues")
                                            else
                                                echo -e "${RED}✗ Failed to clone \"$selected_display_name\" from repository.${NC}"
                                                installation_errors+=("$selected_display_name (branch: $best_branch): Git clone failed")
                                            fi
                                            
                                            rm -f /tmp/bench_error_$.log
                                        fi
                                        
                                        echo -e "\n${LIGHT_BLUE}────────────────────────────────────────${NC}\n"
                                    done

                                    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
                                    echo -e "${GREEN}║           Installation Summary       ║${NC}"
                                    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
                                    
                                    if [ "${#successful_installations[@]}" -gt 0 ]; then
                                        echo -e "${GREEN}✓ Successfully installed ${#successful_installations[@]} apps:${NC}"
                                        for app in "${successful_installations[@]}"; do
                                            echo -e "  ${GREEN}✓${NC} $app"
                                        done
                                        echo ""
                                    fi
                                    
                                    if [ "${#installation_errors[@]}" -gt 0 ]; then
                                        echo -e "${RED}✗ Failed to install ${#installation_errors[@]} apps:${NC}"
                                        for error in "${installation_errors[@]}"; do
                                            echo -e "  ${RED}✗${NC} $error"
                                        done
                                        echo ""
                                        echo -e "${YELLOW}Note: Some apps may not be compatible with ERPNext $bench_version${NC}"
                                        echo -e "${YELLOW}or may require specific dependencies that are not installed.${NC}"
                                    fi

                                    rm -rf "$tmp_dir"
                                    
                                    if [ "${#successful_installations[@]}" -gt 0 ]; then
                                        echo -e "${YELLOW}Restarting services to apply changes...${NC}"
                                        sudo supervisorctl restart all 2>/dev/null || true
                                        echo -e "${GREEN}Services restarted successfully.${NC}"
                                    fi
                                fi
                            fi
                        fi
                    fi
                fi
                ;;
            *)
                echo -e "${RED}Skipping additional apps installation.${NC}"
                ;;
        esac

        #
        # ─── SSL SECTION ────────────────────────────────────────────────────────────────
        #
        case "$continue_ssl" in
            "yes"|"y")
                echo -e "${YELLOW}Make sure your domain name is pointed to the IP of this instance and is reachable before you proceed.${NC}"
                sleep 3

                if ! command -v certbot >/dev/null 2>&1; then
                    echo -e "${YELLOW}Installing Certbot...${NC}"
                    sleep 1
                    if [ "$DISTRO" == "Debian" ]; then
                        echo -e "${YELLOW}Fixing openssl package on Debian...${NC}"
                        sleep 4
                        sudo pip3 uninstall cryptography -y
                        yes | sudo pip3 install pyopenssl==22.0.0 cryptography==36.0.0
                        echo -e "${GREEN}Package fixed${NC}"
                        sleep 2
                    fi

                    sudo apt install snapd -y && \
                    sudo snap install core && \
                    sudo snap refresh core && \
                    sudo snap install --classic certbot && \
                    sudo ln -s /snap/bin/certbot /usr/bin/certbot

                    echo -e "${GREEN}Certbot installed successfully.${NC}"
                else
                    echo -e "${GREEN}Certbot is already installed. Skipping installation.${NC}"
                    sleep 1
                fi

                echo -e "${YELLOW}Obtaining and installing SSL certificate...${NC}"
                sleep 2
                sudo certbot --nginx --non-interactive --agree-tos --email "$email_address" -d "$site_name"
                echo -e "${GREEN}SSL certificate installed successfully.${NC}"
                sleep 2
                ;;
            *)
                echo -e "${RED}Skipping SSL installation...${NC}"
                ;;
        esac

        if [[ -z "$py_version" ]] || [[ "$py_major" -lt 3 ]] || [[ "$py_major" -eq 3 && "$py_minor" -lt 10 ]]; then
            deactivate
        fi

        echo -e "${GREEN}--------------------------------------------------------------------------------"
        echo -e "Congratulations! You have successfully installed ERPNext $version_choice."
        echo -e "You can start using your new ERPNext installation by visiting https://$site_name"
        echo -e "(if you have enabled SSL and used a Fully Qualified Domain Name"
        echo -e "during installation) or http://$server_ip to begin."
        echo -e "Install additional apps as required. Visit https://docs.erpnext.com for Documentation."
        echo -e "Enjoy using ERPNext!"
        echo -e "--------------------------------------------------------------------------------${NC}"
        ;;
    *)

        echo -e "${YELLOW}Getting your site ready for development...${NC}"
        sleep 2
        source ~/.profile
        if [[ "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
            # Node 24 installed system-wide via NodeSource, no NVM needed
            echo -e "${GREEN}Node $(node --version) available system-wide for v16.${NC}"
        else
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            if [[ "$bench_version" == "version-15" ]]; then
                node_ver="20"
            elif [[ "$bench_version" == "version-14" || "$bench_version" == "version-13" ]]; then
                node_ver="18"
            else
                node_ver="16"
            fi
            nvm install "$node_ver"
            nvm alias default "$node_ver"
            nvm use "$node_ver"
            npm install -g yarn@1.22.19
            NVM_BIN="$NVM_DIR/versions/node/$(nvm version)/bin"
            sudo ln -sf "$NVM_BIN/node" /usr/local/bin/node
            sudo ln -sf "$NVM_BIN/npm"  /usr/local/bin/npm
            sudo ln -sf "$NVM_BIN/yarn" /usr/local/bin/yarn
        fi
        bench use "$site_name"
        if [[ "$bench_version" == "version-16" || "$bench_version" == "develop" ]]; then
            bench --site "$site_name" set-config developer_mode 1
            echo -e "${GREEN}Developer mode enabled.${NC}"
        fi
        bench --site "$site_name" clear-cache
        bench build
        echo -e "${GREEN}Done!${NC}"        
        bench set-config -g developer_mode 1
        sleep 5

        echo -e "${GREEN}-----------------------------------------------------------------------------------------------"
        echo -e "Congratulations! You have successfully installed Frappe and ERPNext $version_choice Development Environment."
        echo -e "Start your instance by running bench start to start your server and visiting http://$server_ip:8000"
        echo -e "Install additional apps as required. Visit https://frappeframework.com for Developer Documentation."
        echo -e "Enjoy development with Frappe!"
        echo -e "-----------------------------------------------------------------------------------------------${NC}"
        ;;
esac
