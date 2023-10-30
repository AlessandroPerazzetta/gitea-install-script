# Gitea install script

Gitead installation script (deb based)

# Requirements:

- Debian 10/11/12 or Debian based

# Notes:

This script automatically update and install Gitea (binary from site), MariaDB, Nginx and Letsencrypt

# Usage:

Run as root:

`bash <(wget -qO- https://raw.githubusercontent.com/AlessandroPerazzetta/gitea-install-script/main/run.sh)`



Run as sudo user:

`sudo su -c "bash <(wget -qO- https://raw.githubusercontent.com/AlessandroPerazzetta/gitea-install-script/main/run.sh)" root`