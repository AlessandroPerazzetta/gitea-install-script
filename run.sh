#!/bin/bash
# Gitea is written in Go and distributed as a binary package 
# that runs across all platforms and architectures 
# that Go supports – Linux, macOS, and Windows.
#
# This script automate installation of Gitea, mariadb, nginx, certs

function is_root {
  if [[ $EUID -ne 0 ]]; then
     echo "This script must be run as root or using sudo"
     exit 1
  fi
}

# Function to display colored prompt
function print_style() {
    if [ "$2" == "info" ] ; then
        COLOR="96m";
    elif [ "$2" == "success" ] ; then
        COLOR="92m";
    elif [ "$2" == "warning" ] ; then
        COLOR="93m";
    elif [ "$2" == "danger" ] ; then
        COLOR="91m";
    else #default color
        COLOR="0m";
    fi

    STARTCOLOR="\e[$COLOR";
    ENDCOLOR="\e[0m";

    printf "$STARTCOLOR%b$ENDCOLOR" "$1";
}

# Function to display the confirmation prompt
function ask_confirm() {
    while true; do
        read -p "Do you want to proceed? (YES/NO/CANCEL) " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            [Cc]* ) exit;;
            * ) echo "Please answer YES, NO, or CANCEL.";;
        esac
    done
}


is_root

clear
print_style "Update System and Install git\n" "info"
apt -y update
apt -y install git vim bash-completion curl wget

print_style "Add git user account for Gitea\n" "info"
adduser \
   --system \
   --shell /bin/bash \
   --gecos 'Git Version Control' \
   --group \
   --disabled-password \
   --home /home/git \
   git

print_style "Install MariaDB database server\n" "info"
if ask_confirm; then
    apt -y install mariadb-server
    mysql_secure_installation


    print_style "\nInsert gitea database password:\n" "danger"
    read GITEA_DB_PWD

    mysql -u root -p -e "CREATE DATABASE gitea;"
    mysql -u root -p -e "GRANT ALL PRIVILEGES ON gitea.* TO 'gitea'@'localhost' IDENTIFIED BY '${GITEA_DB_PWD}';"
    mysql -u root -p -e "FLUSH PRIVILEGES;"
fi

print_style "Install Gitea\n" "info"
cd /tmp/
curl -s  https://api.github.com/repos/go-gitea/gitea/releases/latest |grep browser_download_url  |  cut -d '"' -f 4  | grep '\linux-amd64$' | wget -i -
chmod +x gitea-*-linux-amd64
mv gitea-*-linux-amd64 /usr/local/bin/gitea
gitea --version
sleep 5

mkdir -p /etc/gitea /var/lib/gitea/{custom,data,indexers,public,log}
chown git:git /var/lib/gitea/{data,indexers,log}
chmod 750 /var/lib/gitea/{data,indexers,log}
chown root:git /etc/gitea
chmod 770 /etc/gitea

print_style "Configure Systemd for Gitea\n" "info"
cat <<-EOF > /etc/systemd/system/gitea.service
[Unit]
Description=Gitea (Git with a cup of tea)
After=syslog.target
After=network.target
After=mysql.service

[Service]
LimitMEMLOCK=infinity
LimitNOFILE=65535
RestartSec=2s
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/gitea/
ExecStart=/usr/local/bin/gitea web -c /etc/gitea/app.ini
Restart=always
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=/var/lib/gitea

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now gitea
systemctl status gitea

print_style "Install Nginx\n" "info"
if ask_confirm; then
    print_style "\nInsert gitea hostname:\n" "danger"
    read GITEA_HOSTNAME

    print_style "Configure Nginx proxy\n" "info"
    apt -y install nginx
    cat <<-EOF > /etc/nginx/conf.d/gitea.conf
server {
    listen 80;
    server_name ${GITEA_HOSTNAME};

    location / {
        proxy_pass http://localhost:3000;
    }
}
EOF
    systemctl restart nginx

    print_style "Install Letsencrypt certs\n" "info"
    if ask_confirm; then
        print_style "Insert email for certs notifications: " "danger"
        read CERTBOT_MAIL

        print_style "Install letsencrypt certs for Gitea\n" "info"
        apt install certbot python3-certbot-nginx

        certbot --nginx --agree-tos --redirect --hsts --staple-ocsp --email ${CERTBOT_MAIL} -d ${GITEA_HOSTNAME}

        crontab -l > root_cron
        echo "30 2 * * * /usr/bin/certbot renew --quiet" >> root_cron
        crontab root_cron
        rm -rf root_cron

        openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048
        openssl dhparam -out /etc/ssl/certs/dhparam.pem 4096
        
        print_style "\n\nAdd SSL config to Nginx vhost config like this:\n" "info"
        print_style "\t ssl_certificate /path/to/signed_cert_plus_intermediates;\n" "info"
        print_style "\t ssl_certificate_key /path/to/private_key;\n" "info"
        print_style "\t ssl_session_timeout 1d;\n" "info"
        print_style "\t ssl_session_cache shared:MozSSL:10m;  # approximately 40000 sessions\n" "info"
        print_style "\t ssl_session_tickets off;\n" "info"
        print_style "\t ssl_dhparam /etc/ssl/certs/dhparam.pem;\n" "info"
        print_style "\t ssl_protocols TLSv1.2 TLSv1.3;\n" "info"
        print_style "\t ssl_ciphers [long string of ciphers here];\n" "info"
        print_style "\t ssl_prefer_server_ciphers off;\n" "info"
        print_style "\t add_header Strict-Transport-Security "max-age=63072000" always;\n" "info"
        print_style "\t ssl_stapling on;\n" "info"
        print_style "\t ssl_stapling_verify on;\n" "info"
        print_style "\t ssl_trusted_certificate /path/to/root_CA_cert_plus_intermediates;\n" "info"
    fi
fi

print_style "\nGitea installation finished\n" "success"
print_style "Access Gitea web interface on http[s]://${GITEA_HOSTNAME} and finish configuration" "info"