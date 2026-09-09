#/bin/bash
#[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script, please use 'sudo su -' command to change root"; exit 1; }
#tmux new -s ERPShell
clear
echo "################# Install Frappefw/ERPNext ###############
##################          V 0.1           ###############
##################         (GANP)           ###############
###########################################################"

function read_vars() {
  local input
  local text=$message

  read -p "$text" input

  while [[ -z "$input" ]]; do
    read -p "Please ingress a correct value: " input
  done

  echo $input
}

function base_install(){

    local ERPVERSION=$NEXTERPVERSION
    local DEBIAN_FLAG_PIP=$FLAG
    
    sudo apt update -y
    sudo apt upgrade  -y
    sudo apt install sudo git curl --no-install-recommends -y
    sudo apt install python3-dev python3-setuptools python3-pip python3-distutils python3-venv --no-install-recommends -y
    sudo apt install supervisor software-properties-common --no-install-recommends -y
    sudo apt install mariadb-server mariadb-client --no-install-recommends -y
    sudo apt install xvfb libfontconfig1 wkhtmltopdf libmariadb-dev nginx build-essential --no-install-recommends -y
    sudo curl -sL https://deb.nodesource.com/setup_18.x | bash - #error with bahs - ubuntu
    sudo apt install nodejs --no-install-recommends -y #npm error ubuntu
    sudo apt install npm #install in ubuntu
    sudo npm install -g yarn
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg #error debian from |
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
    sudo apt install redis-server --no-install-recommends -y
    sudo systemctl enable --now redis-server
    #mysql config
    #echo "[mysqld]" >> /etc/mysql/my.cnf | tee 
    echo "[mysqld]" | sudo tee -a /etc/mysql/my.cnf
    #echo "character-set-client-handshake = FALSE" >> /etc/mysql/my.cnf
    echo "character-set-client-handshake = FALSE" | sudo tee -a /etc/mysql/my.cnf
    #echo "character-set-server = utf8mb4" >> /etc/mysql/my.cnf
    echo "character-set-server = utf8mb4" | sudo tee -a /etc/mysql/my.cnf
    #echo "collation-server = utf8mb4_unicode_ci" >> /etc/mysql/my.cnf
    echo "collation-server = utf8mb4_unicode_ci" | sudo tee -a /etc/mysql/my.cnf
    #echo "[mysql]" >> /etc/mysql/my.cnf >> /etc/mysql/my.cnf
    echo "[mysql]" | sudo tee -a /etc/mysql/my.cnf
    #echo "default-character-set = utf8mb4" >> /etc/mysql/my.cnf
    echo "default-character-set = utf8mb4" | sudo tee -a /etc/mysql/my.cnf
    sudo systemctl restart mariadb
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

    #createUser
    sudo useradd -p  "$(openssl passwd -6 $PASS)" -m -s /bin/bash $USERNAME
    sudo usermod -aG sudo $USERNAME
    #cd /home/$USERNAME
    #echo PATH=$PATH:$HOME/.local/bin  >> /home/$USERNAME/.bashrc
    echo "PATH=\$PATH:\$HOME/.local/bin" | sudo tee -a  /home/$USERNAME/.bashrc
    #install frappe
    pip install frappe-bench ansible $DEBIAN_FLAG_PIP #ubuntu doesnt use break-system package 
    sudo -i -u $USERNAME bench init --frappe-branch version-$ERPVERSION frappe-bench
    sudo -i -u $USERNAME chmod -R o+rx /home/$USERNAME/frappe-bench/
    sudo -i -u frappe bench --version
    cd /home/$USERNAME/frappe-bench
    sudo -u $USERNAME bench set-config -g redis_cache redis://127.0.0.1:6379
    sudo -u $USERNAME bench set-config -g redis_queue redis://127.0.0.1:6379
    sudo -u $USERNAME bench set-config -g redis_socketio redis://127.0.0.1:6379
    #install ERPNext
    echo "Ready to install ERP Next"
    read -p "Would you like install ERPNext (y/n)?" installERP
    if [ "$installERP" != "${installERP#[Yy]}" ] ;then
        #sudo -u $USERNAME 
        bench get-app --branch version-$ERPVERSION erpnext
        #sudo -u $USERNAME 
        bench new-site $SITE
        #sudo -u $USERNAME 
        bench --site $SITE install-app erpnext
        read -p "Would you like compile production mode (y/n)?" answer
        if [ "$answer" != "${answer#[Yy]}" ] ;then
                sudo bench setup production $USERNAME
                sudo -u $USERNAME bench --site $SITE enable-scheduler
                sudo -u $USERNAME bench --site $SITE set-maintenance-mode off
                sudo -u $USERNAME chmod o+rx /home/$USERNAME
                sudo bench setup production $USERNAME
        else
                #dev mode
                #sudo -u $USERNAME 
                sudo chmod -R o+rx /home/$USERNAME/frappe-bench/
                bench start
        fi
    else
        #sudo -u $USERNAME bench init demo_frappe_bench
        sudo -u $USERNAME bench new-site $SITE
        sudo -u $USERNAME bench start 
    fi
}
##################################################################
##################################################################
. /etc/os-release
ID=$ID
VER=$VERSION_CODENAME
echo $ID
echo $VER

message="Please ingress username to create linux user: "
USERNAME=$(read_vars $message)
clear
#echo $USERNAME

message="Please set the password to linux user created: "
PASS=$(read_vars $message)
#echo $PASS
clear
message="Please set the password to mysql: "
pass_mysql=$(read_vars $message)
#echo $pass_mysql
clear
message="Please ingress your domain name: "
SITE=$(read_vars $message)
echo $SITE
clear
 
if [ $ID == debian ]; then
        case "$VER" in
                bookworm)
                    message="Which version of FrappeFW would you like to install 13 or 14? "
                    NEXTERPVERSION=$(read_vars $message)

                    if [ "$NEXTERPVERSION" !=13 ] || [ "$NEXTERPVERSION" !=14 ]; then
                            NEXTERPVERSION=$(read_vars $message)
                    fi

                    FLAG="--break-system-packages"
                    base_install
                ;;
                bullseye)
                    message="Which version of ERP would you like to install 13 or 14? "
                    NEXTERPVERSION=$(read_vars $message)
                    if [ "$NEXTERPVERION" !=13 ] || [ "$NEXTERPVERSION" !=14 ]; then
                            NEXTERPVERSION=$(read_vars $message)
                    fi
                    FLAG="--break-system-packages"
                    base_install
                ;;
        esac
elif [ $ID == ubuntu ]; then
        case "$VER" in
                jammy)
                    message="Which version of FrappeFW would you like to install 13 or 14? "
                    NEXTERPVERSION=$(read_vars $message)
                    if [ "$NEXTERPVERSION" !=13 ] || [ "$NEXTERPVERSION" !=14 ]; then
                            NEXTERPVERSION=$(read_vars $message)
                    fi

                    base_install
                    

                ;;
        esac
else
        echo "Error to execute installer"
fi