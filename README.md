# MariaDB and phpMyAdmin Installation Script

A bash script for automated installation and configuration of MariaDB and phpMyAdmin on Debian 12, using Nginx as the web server.

## Features

- Automated installation of MariaDB, Nginx, PHP, and phpMyAdmin
- Interactive configuration process
- Option to configure for local-only or network access
- Automatic security hardening
- User-friendly output with color-coded messages

## Requirements

- Debian 12 (Bookworm)
- Root or sudo privileges
- Internet connection for package installation

## Installation

1. Clone or download this repository:
   ```bash
   git clone https://github.com/yourusername/mariadb-php-install.git
   cd mariadb-php-install
   ```

2. Make the script executable:
   ```bash
   chmod +x install_mariadb_phpmyadmin.sh
   ```

3. Run the script with root privileges:
   ```bash
   sudo ./install_mariadb_phpmyadmin.sh
   ```

## Usage

When you run the script, it will:

1. Check if you're running Debian 12
2. Ask if you want a local or network installation
3. Install and configure MariaDB
4. Install and configure Nginx and PHP
5. Install and configure phpMyAdmin
6. Apply security settings
7. Provide connection information

## Configuration Options

### Local Installation (Option 1)
- MariaDB will only accept connections from localhost
- phpMyAdmin will be accessible at http://localhost/phpmyadmin
- Most secure option, recommended for development environments

### Network Installation (Option 2)
- MariaDB will accept connections from other machines on your network
- phpMyAdmin will be accessible at http://your-server-ip/phpmyadmin
- Firewall rules will be configured to allow access
- A dedicated database user will be created for remote connections
- Useful for shared development or small production environments

## Accessing phpMyAdmin

- **Local installation**: Visit http://localhost/phpmyadmin
- **Network installation**: Visit http://your-server-ip/phpmyadmin

Log in with your MariaDB username and password.

## Troubleshooting

### phpMyAdmin Not Accessible
- Check if Nginx is running: `systemctl status nginx`
- Verify configuration: `nginx -t`
- Restart Nginx: `systemctl restart nginx`

### Cannot Connect to MariaDB Remotely
- Check if MariaDB is running: `systemctl status mariadb`
- Verify firewall settings: `ufw status`
- Check bind-address in MariaDB config: `/etc/mysql/mariadb.conf.d/50-server.cnf`
- Verify user has appropriate permissions: `SHOW GRANTS FOR 'username'@'%';`

## Security Considerations

- For production environments, consider:
  - Adding SSL/TLS encryption
  - Implementing more restrictive firewall rules
  - Regular security updates
  - Database backups

## License

[Specify your license here]
