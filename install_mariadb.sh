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

# Install phpMyAdmin from Debian repository without interactive prompts
print_status "Installing phpMyAdmin from repository..."

# Pre-configure phpMyAdmin to avoid any prompts
print_status "Pre-configuring phpMyAdmin installation..."
debconf-set-selections <<EOF
phpmyadmin phpmyadmin/reconfigure-webserver multiselect none
phpmyadmin phpmyadmin/dbconfig-install boolean false
phpmyadmin phpmyadmin/app-password-confirm password 
phpmyadmin phpmyadmin/mysql/admin-pass password 
phpmyadmin phpmyadmin/password-confirm password 
phpmyadmin phpmyadmin/setup-password password 
phpmyadmin phpmyadmin/mysql/app-pass password 
EOF

# Install phpMyAdmin non-interactively
print_status "Installing phpMyAdmin package..."
DEBIAN_FRONTEND=noninteractive apt-get install -y phpmyadmin

# Create phpMyAdmin configuration file if it doesn't exist properly
if [ ! -f /etc/phpmyadmin/config.inc.php ] || ! grep -q "blowfish_secret" /etc/phpmyadmin/config.inc.php; then
    print_status "Configuring phpMyAdmin..."
    
    # Make sure directories exist
    mkdir -p /etc/phpmyadmin
    
    # Copy sample config if needed
    if [ -f /usr/share/phpmyadmin/config.sample.inc.php ] && [ ! -f /etc/phpmyadmin/config.inc.php ]; then
        cp /usr/share/phpmyadmin/config.sample.inc.php /etc/phpmyadmin/config.inc.php
    fi
    
    # Generate a 32-character blowfish secret
    BLOWFISH_SECRET=$(openssl rand -hex 16)
    print_status "Generated a 32-character blowfish secret for cookie encryption"
    
    # Update the configuration
    if grep -q "blowfish_secret" /etc/phpmyadmin/config.inc.php; then
        sed -i "s#\\\$cfg\['blowfish_secret'\] = .*#\\\$cfg\['blowfish_secret'\] = '$BLOWFISH_SECRET';#" /etc/phpmyadmin/config.inc.php
    else
        echo "\$cfg['blowfish_secret'] = '$BLOWFISH_SECRET';" >> /etc/phpmyadmin/config.inc.php
    fi
fi

# Configure Nginx for phpMyAdmin
print_status "Configuring Nginx for phpMyAdmin..."

# Create the web server document root if it doesn't exist
mkdir -p /var/www/html

# Create a symbolic link from phpMyAdmin to the web server's document root
print_status "Creating symbolic link for phpMyAdmin..."
ln -sf /usr/share/phpmyadmin /var/www/html/phpmyadmin

# Set the correct permissions
chown -R www-data:www-data /var/www/html/phpmyadmin
chmod -R 755 /usr/share/phpmyadmin

# Create a Nginx configuration file using the default site
cat > /etc/nginx/sites-available/default << 'EOL'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html;
    index index.php index.html index.htm;
    
    server_name _;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    location /phpmyadmin {
        index index.php index.html index.htm;
        location ~ ^/phpmyadmin/(.+\.php)$ {
            try_files $uri =404;
            root /var/www/html;
            fastcgi_pass unix:/run/php/php8.2-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            include fastcgi_params;
        }
        
        location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
            root /var/www/html;
        }
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

# Remove any previous phpMyAdmin configuration to avoid conflicts
if [ -f /etc/nginx/sites-enabled/phpmyadmin ]; then
    rm -f /etc/nginx/sites-enabled/phpmyadmin
fi

# Make sure the default site is enabled
if [ ! -f /etc/nginx/sites-enabled/default ]; then
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
fi

# Test Nginx configuration
print_status "Testing Nginx configuration..."
nginx -t

# Restart Nginx
print_status "Restarting Nginx..."
systemctl restart nginx

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
