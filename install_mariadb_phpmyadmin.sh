#!/bin/bash

# Function to print status messages
print_status() {
    echo -e "\e[1;32m$1\e[0m"
}

# Function to print error messages
print_error() {
    echo -e "\e[1;31m$1\e[0m"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

# Check if running on Debian 12
if ! grep -q "Debian GNU/Linux 12" /etc/os-release; then
    print_error "This script is designed for Debian 12 (Bookworm)"
    exit 1
fi

# Update package list
print_status "Updating package list..."
apt update

# Install necessary packages
print_status "Installing necessary packages..."
apt install -y mariadb-server nginx php-fpm php-mysql

# Ask for installation type
print_status "Select installation type:"
echo "1) Local installation (localhost only)"
echo "2) Network installation (accessible from other machines)"
read -p "Enter your choice (1 or 2): " install_type

# Configure MariaDB
print_status "Configuring MariaDB..."
if [ "$install_type" -eq 1 ]; then
    # Local installation
    sed -i "s/^bind-address.*/bind-address = 127.0.0.1/" /etc/mysql/mariadb.conf.d/50-server.cnf
else
    # Network installation
    sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/mariadb.conf.d/50-server.cnf
fi
systemctl restart mariadb

# Secure MariaDB installation
print_status "Securing MariaDB installation..."
mysql_secure_installation

# Configure Nginx
print_status "Configuring Nginx..."
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.php index.html index.htm;

    server_name _;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
systemctl restart nginx

# Install phpMyAdmin
print_status "Installing phpMyAdmin..."

# Pre-configure phpMyAdmin to skip web server configuration prompt
# Since we're using Nginx which is not an option in the prompt, we'll select "no configuration"
print_status "Setting up phpMyAdmin to skip web server configuration..."
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect none" | debconf-set-selections
echo "phpmyadmin phpmyadmin/dbconfig-install boolean false" | debconf-set-selections

# Install phpMyAdmin package
apt install -y phpmyadmin

# Configure Nginx for phpMyAdmin
print_status "Configuring Nginx for phpMyAdmin..."
cat > /etc/nginx/conf.d/phpmyadmin.conf <<EOF
server {
    listen 80;
    server_name _;

    root /usr/share/phpmyadmin;
    index index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ ^/phpmyadmin/(doc|sql|setup)/ {
        deny all;
    }

    location ~ /phpmyadmin/(.+\.php)\$ {
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
        include snippets/fastcgi-php.conf;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
systemctl restart nginx

print_status "Installation and configuration complete!"