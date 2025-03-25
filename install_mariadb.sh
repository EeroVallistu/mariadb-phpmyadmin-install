#!/bin/bash

# Script to install MariaDB and phpMyAdmin on Debian 12 with Nginx
# Author: EeroVallistu
# Usage: sudo bash install_mariadb_phpmyadmin.sh

# Exit on any error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Default settings
NETWORK_ACCESS=false

# Function to print status messages
print_status() {
    echo -e "${GREEN}[+] $1${NC}"
}

# Function to print error messages
print_error() {
    echo -e "${RED}[!] $1${NC}"
}

# Function to print warning messages
print_warning() {
    echo -e "${YELLOW}[*] $1${NC}"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root. Try 'sudo bash $0'"
    exit 1
fi

# Check if we're on Debian 12
if [ ! -f /etc/debian_version ] || ! grep -q '^12' /etc/debian_version; then
    print_warning "This script is designed for Debian 12. Your system may not be compatible."
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Ask user if they want network access
print_status "Configuration options:"
print_status "1. Local installation (recommended, more secure)"
print_status "2. Network installation (allows connections from other machines)"
read -p "Select an option [1]: " INSTALL_TYPE
INSTALL_TYPE=${INSTALL_TYPE:-1}

if [ "$INSTALL_TYPE" == "2" ]; then
    NETWORK_ACCESS=true
    print_status "Network installation selected."
else
    print_status "Local installation selected."
fi

# Update the system
print_status "Updating system packages..."
apt update && apt upgrade -y

# Install MariaDB
print_status "Installing MariaDB Server..."
apt install -y mariadb-server mariadb-client

# Start MariaDB service
print_status "Starting MariaDB service..."
systemctl start mariadb
systemctl enable mariadb

# Configure MariaDB for network access if requested
if [ "$NETWORK_ACCESS" = true ]; then
    print_status "Configuring MariaDB for network access..."
    
    # Backup the original config
    cp /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf.bak
    
    # Update bind-address to allow connections from any IP
    sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf
    
    # Install UFW firewall if not already installed
    if ! command -v ufw &> /dev/null; then
        print_status "Installing UFW firewall..."
        apt install -y ufw
    fi
    
    # Configure firewall to allow MariaDB and HTTP traffic
    print_status "Configuring firewall to allow MariaDB (3306) and HTTP (80) traffic..."
    ufw allow 3306/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp  # Also allow HTTPS
    
    # Enable UFW if it's not already enabled
    if ! ufw status | grep -q "Status: active"; then
        print_warning "Enabling UFW firewall. This might disconnect your SSH session if SSH is not allowed."
        print_warning "Make sure SSH access is allowed before proceeding."
        read -p "Continue enabling UFW? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ufw allow 22/tcp
            ufw --force enable
        else
            print_warning "UFW not enabled. You may need to configure firewall manually."
        fi
    fi
    
    # Create a MariaDB user for remote access
    print_status "Creating a database user for remote access..."
    read -p "Enter username for remote database access: " DB_USER
    read -sp "Enter password for $DB_USER: " DB_PASS
    echo
    
    mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON *.* TO '$DB_USER'@'%' WITH GRANT OPTION;"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Restart MariaDB to apply changes
    print_status "Restarting MariaDB service..."
    systemctl restart mariadb
fi

# Secure MariaDB installation
print_status "Securing MariaDB installation..."
print_warning "You'll be prompted to set a root password and answer security questions."
mysql_secure_installation

# Install Nginx and PHP
print_status "Installing Nginx and PHP..."
apt install -y nginx php-fpm php-mysql php-mbstring php-zip php-gd php-json php-curl

# Enable and start PHP-FPM
print_status "Enabling PHP-FPM..."
systemctl enable php8.2-fpm
systemctl start php8.2-fpm

# Install phpMyAdmin manually instead of using the package manager
print_status "Installing phpMyAdmin manually..."

# Install curl if it's not already installed
if ! command -v curl &> /dev/null; then
    print_status "Installing curl..."
    apt install -y curl
fi

# Create directory for phpMyAdmin
mkdir -p /usr/share/phpmyadmin

# Use a fixed version instead of trying to detect the latest version
# This avoids issues with parsing the website
PHPMYADMIN_VERSION="5.2.1"
print_status "Downloading phpMyAdmin $PHPMYADMIN_VERSION..."

# Download and extract phpMyAdmin
wget -O /tmp/phpmyadmin.zip "https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VERSION}/phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.zip"
apt install -y unzip
unzip -q /tmp/phpmyadmin.zip -d /tmp
cp -a /tmp/phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages/* /usr/share/phpmyadmin/
rm -rf /tmp/phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages /tmp/phpmyadmin.zip

# Set permissions
chown -R www-data:www-data /usr/share/phpmyadmin

# Create phpMyAdmin configuration file
print_status "Configuring phpMyAdmin..."
cp /usr/share/phpmyadmin/config.sample.inc.php /usr/share/phpmyadmin/config.inc.php

# Generate a random blowfish secret
BLOWFISH_SECRET=$(openssl rand -base64 32)
sed -i "s/\$cfg\['blowfish_secret'\] = ''/\$cfg\['blowfish_secret'\] = '$BLOWFISH_SECRET'/" /usr/share/phpmyadmin/config.inc.php

# Configure Nginx for phpMyAdmin
print_status "Configuring Nginx for phpMyAdmin..."

# Create a Nginx configuration file for phpMyAdmin
cat > /etc/nginx/conf.d/phpmyadmin.conf << 'EOL'
server {
    listen 80;
    listen [::]:80;
    
    root /usr/share/phpmyadmin;
    index index.php index.html index.htm;
    
    # If you want to use a specific server name, uncomment and modify the next line
    # server_name phpmyadmin.example.com;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOL

# Test Nginx configuration
nginx -t

# Restart Nginx
print_status "Restarting Nginx..."
systemctl restart nginx
systemctl enable nginx

# Final status
print_status "Installation completed successfully!"
print_status "MariaDB is installed and running."

if [ "$NETWORK_ACCESS" = true ]; then
    HOST_IP=$(hostname -I | awk '{print $1}')
    print_status "MariaDB is configured for network access at: $HOST_IP:3306"
    print_status "Database user '$DB_USER' can be used for remote connections."
    print_status "phpMyAdmin is available at http://$HOST_IP/phpmyadmin"
    print_warning "Make sure your server's IP address is static to avoid connection issues."
else
    print_status "MariaDB is configured for local access only."
    print_status "phpMyAdmin is available at http://localhost/phpmyadmin"
    print_warning "To enable network access later, edit /etc/mysql/mariadb.conf.d/50-server.cnf and change bind-address to 0.0.0.0"
fi

print_warning "Remember to keep your system updated regularly with: sudo apt update && sudo apt upgrade"

exit 0
