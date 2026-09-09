#/bin/bash
    read -p "witch version of frappe do you want to install? " version
    ERPVERSION=verion
    #DEBIAN_FLAG_PIP=$FLAG
    SILENCE_MODE="NEEDRESTART_MODE=a"
    USERNAME=$(whoami)

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