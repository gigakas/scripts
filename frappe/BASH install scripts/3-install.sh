#/bin/bash
clear
echo "######################################### Install Frappefw/ERPNext #############################################"
echo "##########################################          V 0.2           ############################################"
echo "##########################################         (GANP)           ############################################"
echo "################################################################################################################"

# Global variable to store the user input
user_input=""

request_input() {
    # Input type passed as argument to the function
    input_type=$1

    # Messages passed as arguments to the function
    welcome_message=$2
    error_message=$3
    success_message=$4
    # Define the array with the allowed values for number type version of fw supported
    versions=(13 14 15)
    while true; do
        echo "$welcome_message"
        read input

        case "$input_type" in
            ver13)
                if [[ "$input" =~ ^[0-9]+$ ]]; then
                    if [[ " ${versions[0]} " =~ " ${input} " ]] || [[ $input -eq " ${versions[0]} " ]]; then
                        echo "$success_message"
                        user_input="$input"
                        break
                    else
                        echo "$error_message"
                    fi
                fi
                ;;
            ver14)
                if [[ "$input" =~ ^[0-9]+$ ]]; then
                    if [[ " ${versions[1]} " =~ " ${input} " ]] || [[ $input -eq " ${versions[1]} " ]]; then
                        echo "$success_message"
                        user_input="$input"
                        break
                    else
                        echo "$error_message"
                    fi
                fi
                ;;   
            number)
                #remove version 13 from array
                unset 'versions[0]'
                if [[ "$input" =~ ^[0-9]+$ ]] && [[ " ${versions[@]} " =~ " ${input} " ]]; then
                    echo "$success_message"
                    user_input="$input"
                    break
                else
                    echo "$error_message"
                fi
                ;;
            domain)
                if [[ "$input" =~ ^[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+$ ]]; then
                    echo "$success_message"
                    user_input="$input"
                    break
                else
                    echo "$error_message"
                fi
                ;;
            text)
                if ! [[ -z "$input" ]]; then
                    echo "$success_message"
                    user_input="$input"
                    break
                else
                    echo "$error_message"
                fi
                ;;
            *)
                echo "Error: Unknown input type."
                exit 1
                ;;
        esac
    done 
}
base_install() {
    local ERPVERSION=$NEXTERPVERSION
    local DEBIAN_FLAG_PIP=$FLAG
    SILENCE_MODE="NEEDRESTART_MODE=a"

    sudo apt update -y
    sudo $SILENCE_MODE apt upgrade  -y
    sudo $SILENCE_MODE apt install sudo git curl cron net-tools iputils-ping tmux --no-install-recommends -y
    sudo $SILENCE_MODE apt install python3-dev python3-setuptools python3-pip python3-distutils python3-venv --no-install-recommends -y
    sudo $SILENCE_MODE apt install supervisor software-properties-common --no-install-recommends -y
    sudo $SILENCE_MODE apt install mariadb-server mariadb-client --no-install-recommends -y
    sudo $SILENCE_MODE apt install xvfb libfontconfig1 wkhtmltopdf libmariadb-dev nginx build-essential --no-install-recommends -y
    sudo curl -sL https://deb.nodesource.com/setup_18.x  | sudo bash -
    sudo $SILENCE_MODE apt install nodejs --no-install-recommends -y
    sudo npm install -g yarn
    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
    sudo $SILENCE_MODE apt install redis-server --no-install-recommends -y
    sudo systemctl enable --now redis-server
    #mysql config
    echo "[mysqld]" | sudo tee -a /etc/mysql/my.cnf
    echo "character-set-client-handshake = FALSE" | sudo tee -a /etc/mysql/my.cnf
    echo "character-set-server = utf8mb4" | sudo tee -a /etc/mysql/my.cnf
    echo "collation-server = utf8mb4_unicode_ci" | sudo tee -a /etc/mysql/my.cnf
    echo "[mysql]" | sudo tee -a /etc/mysql/my.cnf
    echo "default-character-set = utf8mb4" | sudo tee -a /etc/mysql/my.cnf
    echo "[group:$USERNAME]" | sudo tee -a /etc/supervisor/supervisord.conf
    sudo /etc/init.d/supervisor restart
    sudo systemctl restart mariadb
    echo "Configuring MySQL security"

    # useradd  -G sudo -p "$(openssl passwd -6 1)" -m -s /bin/bash frappe
    #mysql default configa
    #Switch to unix_socket authentication?
    unix_socket=y
    #Change the root password?
    change_root_pass=y
    #set password
    mysql_pass=$pass_mysql
    #Remove anonymous users? ?
    remove_anomymus_user=y
    #Disallow root login remotely?
    deny_remote_login=y
    #Remove test database and access to it?
    remove_testDB=y
    #Reload privilege tables now?
    reload_mysql=y
    printf "\n${unix_socket}\n${change_root_pass}\n${mysql_pass}\n${mysql_pass}\n${remove_anonymus_user}\n${deny_remote_login}\n${remove_testDB}\n${reload_mysql}" | sudo /usr/bin/mysql_secure_installation
    sudo mysql -uroot -pPASSWORD -Bse "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' IDENTIFIED BY '$mysql_pass' WITH GRANT OPTION;"
    echo "export PATH="/home/$USERNAME/.local/bin:\$PATH"" | sudo tee -a  /home/$USERNAME/.bashrc  
    export PATH="/home/frappe/.local/bin:$PATH" 
    source ~/.bashrc
    #install frappe
    pip install frappe-bench ansible $DEBIAN_FLAG_PIP #ubuntu doesn't use break-system package
    bench init --frappe-branch version-$ERPVERSION frappe-bench
    #sudo -i -u $USERNAME chmod -R o+rx /home/$USERNAME/frappe-bench/
    bench --version
    cd /home/$USERNAME/frappe-bench
    bench set-config -g redis_cache redis://127.0.0.1:6379
    bench set-config -g redis_queue redis://127.0.0.1:6379
    bench set-config -g redis_socketio redis://127.0.0.1:6379

    #install ERPNext
    echo "Ready to install ERP Next"
    read -p "Would you like install ERPNext (y/n)?" installERP
    if [ "$installERP" != "${installERP#[Yy]}" ] ;then
        bench new-site --db-name erpnext --db-root-password $pass_mysql --admin-password $pass_frappe  $SITE  
        bench get-app --branch version-$ERPVERSION erpnext --resolve-deps
        bench --site $SITE install-app erpnext
        read -p "Would you like compile production mode (y/n)?" answer
        if [ "$answer" != "${answer#[Yy]}" ] ;then
                sudo bench setup production $USERNAME
                bench --site $SITE enable-scheduler
                bench --site $SITE set-maintenance-mode off
                sudo -u $USERNAME chmod o+rx /home/$USERNAME
                sudo bench setup production $USERNAME
        else
                #dev mode
                read -p "Would you like start your server (y/n)?" runserver
                if [ "$runserver" != "${runserver#[Yy]}" ] ;then
                bench start
                fi
        fi
    else
        bench new-site --db-name frappecore --db-root-password $pass_mysql --admin-password $pass_frappe  $SITE 
        read -p "Would you like start your server (y/n)?" runserver
        if [ "$runserver" != "${runserver#[Yy]}" ] ;then
        bench start
        fi
    fi
}
################################################################################################################
## controller
################################################################################################################
. /etc/os-release
ID=$ID
VER=$VERSION_CODENAME
echo $ID
echo $VER
echo "##########################################################################################################"
USERNAME=$(whoami)

request_input "domain" \
"Please enter a domain name of your site:" \
"Error: The input is not a valid text domain. Please try again." \
"The text string is correct."
SITE=$user_input
echo $SITE
request_input "text" \
"Please enter a password for mysql (letters, numbers and spaces are allowed):" \
"Error: The input is not a valid text string. Please try again." \
""
pass_mysql=$user_input
request_input "text" \
"Please enter a password for administrator frappe user (letters, numbers and spaces are allowed):" \
"Error: The input is not a valid text string. Please try again." \
""
pass_frappe=$user_input
clear

if [ $ID == debian ]; then
        case "$VER" in
                bookworm)
                    clear
                    GROUPNAME=sudo
                    if id -nG "$USERNAME" | grep -qw "$GROUPNAME"; then
                        echo "User $USERNAME is part of group $GROUPNAME"
                    else
                    echo "##################################################"
                    echo "User $USERNAME is NOT part of group $GROUPNAME"
                    echo "Consider execute these instructions as root user first."
                    echo "1. You must  first  create user named frappe"
                    echo "2. apt install sudo"
                    echo "3. cp /usr/sbin/usermod /usr/bin/"
                    echo "4. usermod -aG sudo frappe"
                    echo "5. login as frappe user"
                    echo "6. execute this script again"
                    echo "##################################################"
                    exit 0
                    fi
                    # request_input "ver14" \
                    # "Please enter which version of Frappe FW do you want install (supported 14) :" \
                    # "Error: The input is not a valid. Please try again." \
                    # ""
                    # NEXTERPVERSION=$user_input
                    NEXTERPVERSION=14
                    FLAG="--break-system-packages"
                    base_install
                    sudo exec bash
                ;;
                bullseye)
                    clear
                    GROUPNAME=sudo
                    if id -nG "$USERNAME" | grep -qw "$GROUPNAME"; then
                        echo "User $USERNAME is part of group $GROUPNAME"
                    else
                    echo "##################################################"
                    echo "User $USERNAME is NOT part of group $GROUPNAME"
                    echo "Consider execute these instructions as root user first."
                    echo "1. You must  first  create user named frappe"
                    echo "2. apt install sudo"
                    echo "3. cp /usr/sbin/usermod /usr/bin/"
                    echo "4. usermod -aG sudo frappe"
                    echo "5. login as frappe user"
                    echo "6. execute this script again"
                    echo "##################################################"
                    exit 0
                    fi
                    apt install sudo
                    # request_input "ver13" \
                    # "Please enter which version of Frappe FW do you want install (supported 13/) :" \
                    # "Error: The input is not a valid. Please try again." \
                    # ""
                    # NEXTERPVERSION=$user_input
                     NEXTERPVERSION=13
                    FLAG="--break-system-packages"
                    base_install
                    sudo exec bash
                ;;
                *)
                echo "Error: Unknown input type."
                exit 1
                ;;
        esac
elif [ $ID == ubuntu ]; then
        case "$VER" in
                jammy)
                    request_input "number" \
                    "Please enter which version of Frappe FW do you want install (supported 14/15) :" \
                    "Error: The input is not a valid . Please try again." \
                    ""
                    NEXTERPVERSION=$user_input
                    #NEXTERPVERSION=14
                    base_install 
                    sudo exec bash                 
                ;;
                focal)
                    # request_input "ver13" \
                    # "Please enter which version of Frappe FW do you want install (supported 13/14/) :" \
                    # "Error: The input is not a valid . Please try again." \
                    # ""
                    # NEXTERPVERSION=$user_input
                    NEXTERPVERSION=13
                    base_install
                    sudo exec bash
                ;;
                *)
                echo "Error: Unknown input type."
                exit 1
                ;;
        esac
else
        echo "Error to execute installer"
fi