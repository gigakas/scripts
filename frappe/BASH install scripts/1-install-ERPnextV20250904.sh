#/bin/bash
clear
echo "#################################### Install FrappeFW/ERPNext #################################
##########################################          V 0.5           #################################
##########################################    (GANP forest GANP :) )#################################
#####################################################################################################"

# Global variable to store the user's input
user_input=""

request_input() {
    # Input type passed as argument to the function
    input_type=$1

    # Messages passed as arguments to the function
    welcome_message=$2
    error_message=$3
    success_message=$4

    # Define the array with the allowed values for number type version of fw supported
    values=(13 14 15)

    while true; do
        echo "$welcome_message"
        read input

        case "$input_type" in
            ver13)
                if [[ "$input" =~ ^[0-9]+$ ]]; then
                    if [[ " ${values[0]} " =~ " ${input} " ]] || [[ $input -eq " ${values[0]} " ]]; then
                        echo "$success_message"
                        user_input="$input"
                        break
                    else
                        echo "$error_message"
                    fi
                fi
                ;;
            ver14_15)
                if [[ "$input" =~ ^[0-9]+$ ]]; then
                    if [[ " ${values[1]} " =~ " ${input} " ]] || [[ " ${values[2]} " =~ " ${input} " ]] ||  [[ $input -eq " ${values[1]} " ]] || [[ $input -eq "${values[2]}" ]]; then
                        echo "$success_message"
                        user_input="$input"
                        break
                    else
                        echo "$error_message"
                    fi
                fi
                ;;
            ver15)
                if [[ "$input" =~ ^[0-9]+$ ]]; then
                    if [[ " ${values[2]} " =~ " ${input} " ]] || [[ $input -eq " ${values[2]} " ]]; then
                        echo "$success_message"
                        user_input="$input"
                        break
                    else
                        echo "$error_message"
                    fi
                fi
                ;;    
            number)
                if [[ "$input" =~ ^[0-9]+$ ]] && [[ " ${values[@]} " =~ " ${input} " ]]; then
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
## install version 13-14-15 depends the version
base_install() {
    local ERPVERSION=$NEXTERPVERSION
    local DEBIAN_FLAG_PIP=$FLAG
    local NODE_MAJOR=$NODE_VERSION
    SILENCE_MODE="NEEDRESTART_MODE=a"

    sudo apt update -y
    sudo $SILENCE_MODE apt upgrade  -y
    echo "########################################################"
    echo "Installing dependencies"
    echo "########################################################"
    sudo $SILENCE_MODE apt install sudo git curl cron net-tools iputils-ping tmux --no-install-recommends -y
    sudo $SILENCE_MODE apt install python3-dev python3-setuptools python3-pip python3-distutils python3-venv --no-install-recommends -y
    sudo $SILENCE_MODE apt install supervisor software-properties-common --no-install-recommends -y
    sudo $SILENCE_MODE apt install mariadb-server mariadb-client --no-install-recommends -y
    sudo $SILENCE_MODE apt install xvfb libfontconfig1 wkhtmltopdf libmariadb-dev nginx build-essential --no-install-recommends -y
    echo "########################################################"
    echo "Installing nodejs and yarn"
    echo "########################################################"
    sudo apt install -y ca-certificates curl gnupg
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
    sudo apt update
    sudo apt install nodejs -y

    sudo npm install -g yarn
    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
    sudo $SILENCE_MODE apt install redis-server --no-install-recommends -y
    sudo systemctl enable --now redis-server


    echo "########################################################"
    echo "Config mariadb"
    echo "########################################################"
    echo "[mysqld]" | sudo tee -a /etc/mysql/my.cnf
    echo "character-set-client-handshake = FALSE" | sudo tee -a /etc/mysql/my.cnf
    echo "character-set-server = utf8mb4" | sudo tee -a /etc/mysql/my.cnf
    echo "collation-server = utf8mb4_unicode_ci" | sudo tee -a /etc/mysql/my.cnf
    echo "[mysql]" | sudo tee -a /etc/mysql/my.cnf
    echo "default-character-set = utf8mb4" | sudo tee -a /etc/mysql/my.cnf

    #config supervisor
    echo "[group:$USERNAME]" | sudo tee -a /etc/supervisor/supervisord.conf

    #restart mariadb
    sudo /etc/init.d/supervisor restart

    sudo systemctl restart mariadb
    echo "Configuring MySQL security"
    
    #Mysql secure installation configuration
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
    
    #define routes supervisor
    echo "export PATH="/home/$USERNAME/.local/bin:\$PATH"" | sudo tee -a  /home/$USERNAME/.bashrc  
    export PATH="/home/frappe/.local/bin:$PATH" 
    source ~/.bashrc

    echo "########################################################"
    echo "Installing frappe"
    echo "########################################################"
    pip install frappe-bench ansible $DEBIAN_FLAG_PIP #ubuntu doesn't use break-system package
    bench init --frappe-branch version-$ERPVERSION frappe-bench        
    bench --version
    cd /home/$USERNAME/frappe-bench
    bench set-config -g redis_cache redis://127.0.0.1:6379
    bench set-config -g redis_queue redis://127.0.0.1:6379
    bench set-config -g redis_socketio redis://127.0.0.1:6379

    echo "########################################################"
    echo "Ready to install ERP Next"
    echo "########################################################"    
    read -p "Would you like install ERPNext (y/n)?" installERP
    if [ "$installERP" != "${installERP#[Yy]}" ] ;then
        bench new-site --db-name erpnext --db-root-password $pass_mysql --admin-password $pass_frappe  $SITE  
        bench get-app --branch version-$ERPVERSION erpnext --resolve-deps
        bench --site $SITE install-app erpnext
        bench --site $SITE enable-scheduler
        bench --site $SITE set-config developer_mode 1

        echo "########################################################"
        echo "Ready to install ERP Next"
        echo "########################################################"            
        read -p "Would you like compile production mode (y/n)?" answer
        if [ "$answer" != "${answer#[Yy]}" ] ;then
        sudo -u $USERNAME chmod o+rx /home/$USERNAME
                sudo ln -sf /home/frappe/.local/share/pipx/venvs/frappe-bench/bin/bench /usr/local/bin/bench
                sudo apt install nginx -y
                sudo apt-get install fail2ban -y
                sudo systemctl enable --now fail2ban
                sudo systemctl status fail2ban
                cd ~/frappe-bench
                bench --site $SITE enable-scheduler
                bench --site $SITE set-maintenance-mode off
                bench setup nginx
                sudo bench setup production $USERNAME
                sudo supervisorctl restart all                
                bench restart
                bench --site $SITE set-config developer_mode 0
                sudo -u $USERNAME chmod o+rx /home/$USERNAME
                sudo bench setup production $USERNAME
                
        else
                #run ERPNext
                read -p "Would you like start your server (y/n)?" runserver
                if [ "$runserver" != "${runserver#[Yy]}" ] ;then
                bench start
                fi
        fi
    else
        bench new-site --db-name frappecore --db-root-password $pass_mysql --admin-password $pass_frappe  $SITE
        bench --site $SITE enable-scheduler
        bench --site $SITE set-config developer_mode 1
        read -p "Would you like start your server (y/n)?" runserver
        if [ "$runserver" != "${runserver#[Yy]}" ] ;then
        bench start
        fi
    fi
}
################################################################################################################
## installer for ubuntu 24-04
install_ubuntu24_04() {
    local ERPVERSION=$NEXTERPVERSION
    local DEBIAN_FLAG_PIP=$FLAG
    local NODE_MAJOR=$NODE_VERSION
    
    sudo apt update -y
    sudo apt upgrade  -y
    sudo apt install nano -y
    sudo apt install net-tools -y
    sudo apt install cron -y
    sudo apt install iputils-ping -y
    sudo apt install tmux -y
    sudo apt install git -y 

    echo "########################################################"
    echo "Installing dependencies"
    echo "########################################################"    

    #use python3.1x+ to future updates
    #this block install phyton 3.12 if is required
    sudo apt install python3-dev -y
    sudo apt install python3-setuptools -y
    sudo apt install python3-pip -y
    sudo apt install python3.12-venv -y 

    sudo apt install software-properties-common -y
    sudo apt install supervisor
    sudo apt install mariadb-server -y
    sudo systemctl status mariadb -y

    echo "########################################################"
    echo "Config mariadb"
    echo "########################################################"
    echo "[mysqld]" | sudo tee -a /etc/mysql/my.cnf
    echo "character-set-client-handshake = FALSE" | sudo tee -a /etc/mysql/my.cnf
    echo "character-set-server = utf8mb4" | sudo tee -a /etc/mysql/my.cnf
    echo "collation-server = utf8mb4_unicode_ci" | sudo tee -a /etc/mysql/my.cnf
    echo "[mysql]" | sudo tee -a /etc/mysql/my.cnf
    echo "default-character-set = utf8mb4" | sudo tee -a /etc/mysql/my.cnf

    #config supervisor rights
    echo "[group:$USERNAME]" | sudo tee -a /etc/supervisor/supervisord.conf    
    sudo /etc/init.d/supervisor restart -y

    sudo systemctl restart mariadb -y
    echo "Configuring MySQL security"

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
    
    #define rutes supervisor
    echo "export PATH="/home/$USERNAME/.local/bin:\$PATH"" | sudo tee -a  /home/$USERNAME/.bashrc  
    export PATH="/home/frappe/.local/bin:$PATH" 
    source ~/.bashrc

    echo "########################################################"
    echo "Installing node"
    echo "########################################################"
    sudo apt install libmysqlclient-dev -y
    sudo service mysql restart -y
    sudo apt install redis-server -y
    sudo apt install curl -y
    curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash
    source ~/.profile
    nvm install 20

    sudo apt install npm -y
    sudo npm install -g yarn -y
    sudo apt install xvfb libfontconfig wkhtmltopdf -y

    echo "########################################################"
    echo "Installing ansible"
    echo "########################################################"
    sudo -H pip3 install ansible --break-system-packages

    echo "########################################################"
    echo "Installing frappe"
    echo "########################################################"
    sudo -H pip3 install frappe-bench --break-system-packages
    bench --version
    bench init frappe-bench --frappe-branch version-$ERPVERSION        
    cd /home/$USERNAME/frappe-bench
    bench set-config -g redis_cache redis://127.0.0.1:6379
    bench set-config -g redis_queue redis://127.0.0.1:6379
    bench set-config -g redis_socketio redis://127.0.0.1:6379

    #install ERPNext
    echo "########################################################"
    echo "Ready to install ERP Next"
    echo "########################################################"  
    read -p "Would you like install ERPNext (y/n)?" installERP
    if [ "$installERP" != "${installERP#[Yy]}" ] ;then
        bench new-site --db-name erpnext --db-root-password $pass_mysql --admin-password $pass_frappe  $SITE  
        bench get-app --branch version-$ERPVERSION erpnext --resolve-deps
        bench --site $SITE install-app erpnext
        bench --site $SITE enable-scheduler
        bench --site $SITE set-config developer_mode 1
        read -p "Would you like compile production mode (y/n)?" answer
        if [ "$answer" != "${answer#[Yy]}" ] ;then
                sudo -u $USERNAME chmod o+rx /home/$USERNAME
                bench --site $SITE enable-scheduler
                bench --site $SITE set-maintenance-mode off
                sudo apt install nginx -y
                sudo apt-get install fail2ban -y
                bench setup nginx
                sudo bench setup production $USERNAME
                sudo supervisorctl restart all                
                bench restart
                bench --site $SITE set-config developer_mode 0
                sudo bench setup production $USERNAME
        else
                #run ERPNext
                read -p "Would you like start your server (y/n)?" runserver
                if [ "$runserver" != "${runserver#[Yy]}" ] ;then
                bench use $SITE
                bench start
                fi
        fi
    else
        bench new-site --db-name frappecore --db-root-password $pass_mysql --admin-password $pass_frappe  $SITE
        bench --site $SITE enable-scheduler
        bench --site $SITE set-config developer_mode 1
          read -p "Would you like compile production mode (y/n)?" answer
        if [ "$answer" != "${answer#[Yy]}" ] ;then
                sudo -u $USERNAME chmod o+rx /home/$USERNAME
                bench --site $SITE enable-scheduler
                bench --site $SITE set-maintenance-mode off
                sudo apt install nginx -y
                sudo apt-get install fail2ban -y
                bench setup nginx
                sudo bench setup production $USERNAME
                sudo supervisorctl restart all                
                bench restart
                bench --site $SITE set-config developer_mode 0
                sudo bench setup production $USERNAME
        else
                #run ERPNext
                read -p "Would you like start your server (y/n)?" runserver
                if [ "$runserver" != "${runserver#[Yy]}" ] ;then
                bench use $SITE
                bench start
                fi
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

# evaluate which version of linux is installed
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
                    #NEXTERPVERSION=14
                    NODE_VERSION=20
                    FLAG="--break-system-packages"
                    base_install
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
                    NODE_VERSION=18
                    FLAG="--break-system-packages"
                    base_install
                ;;
                *)
                echo "Error: Unknown input type."
             
                exit 1
                ;;
        esac
#evaluate ubuntu version code name  to install the right dependences        
elif [ $ID == ubuntu ]; then
        case "$VER" in
                noble)
                    request_input "ver15" \
                    "Please enter which version of Frappe FW do you want install (supported 15) :" \
                    "Error: The input is not a valid . Please try again." \
                    ""
                    NEXTERPVERSION=$user_input
                    #echo $NEXTERPVERSION
                    #NEXTERPVERSION=14
                    NODE_VERSION=20
                    install_ubuntu24_04                  
                ;;
                jammy)
                    request_input "ver14_15" \
                    "Please enter which version of Frappe FW do you want install (supported 14 - 15) :" \
                    "Error: The input is not a valid . Please try again." \
                    ""
                    NEXTERPVERSION=$user_input
                    #echo $NEXTERPVERSION
                    #NEXTERPVERSION=14
                    NODE_VERSION=20
                    base_install                  
                ;;
                focal)
                    # request_input "ver13" \
                    # "Please enter which version of Frappe FW do you want install (supported 13/14/) :" \
                    # "Error: The input is not a valid . Please try again." \
                    # ""
                    # NEXTERPVERSION=$user_input
                    NEXTERPVERSION=13
                    NODE_VERSION=18
                    base_install
                ;;
                *)
                echo "Error: Unknown input type."
                exit 1
                ;;
        esac
else
        echo "Error to execute installer"
fi
