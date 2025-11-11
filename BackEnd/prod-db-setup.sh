#!/bin/bash

# This script takes a clean Ubuntu Server 24.04 LTS image and installs and configures
# everything needed to deploy a production-ready PostgreSQL server.

set -euo pipefail

# --- AESTHETICS ---

GREEN='\033[0;32m'
ELEPHANT='\xF0\x9F\x90\x98'
NC='\033[0m'

# --- HELPER FUNCTIONS ---

log() {
    echo -e "${GREEN}${ELEPHANT} $1${NC}"
}

# --- SECURITY FUNCTIONS ---

configure_firewall() {
    log "Configuring the firewall with ufw..."
    sudo apt-get install -y ufw
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw allow 5432/tcp  # PostgreSQL port
    echo "y" | sudo ufw enable
}

harden_ssh() {
    log "Hardening SSH configuration..."
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    sudo tee /etc/ssh/sshd_config > /dev/null <<EOF
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
UsePrivilegeSeparation yes
KeyRegenerationInterval 3600
ServerKeyBits 1024
SyslogFacility AUTH
LogLevel INFO
LoginGraceTime 120
PermitRootLogin prohibit-password
StrictModes yes
RSAAuthentication yes
PubkeyAuthentication yes
IgnoreRhosts yes
RhostsRSAAuthentication no
HostbasedAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
PasswordAuthentication no
PermitUserEnvironment no
X11Forwarding no
X11DisplayOffset 10
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
UsePAM yes
MaxAuthTries 6
AllowUsers root postgres
EOF
    sudo systemctl restart ssh.service
}

setup_fail2ban() {
    log "Installing and configuring fail2ban..."
    sudo apt-get install -y fail2ban
    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    sudo sed -i 's/bantime  = 10m/bantime  = 1h/' /etc/fail2ban/jail.local
    sudo sed -i 's/findtime  = 10m/findtime  = 30m/' /etc/fail2ban/jail.local
    sudo sed -i 's/maxretry = 5/maxretry = 3/' /etc/fail2ban/jail.local
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
}

# --- POSTGRESQL FUNCTIONS ---

install_postgresql() {
    log "Installing PostgreSQL..."
    sudo apt-get install -y postgresql postgresql-contrib
}

configure_postgresql() {
    log "Configuring PostgreSQL for remote access..."
    
    # Allow PostgreSQL to listen on all interfaces
    sudo -u postgres psql -c "ALTER SYSTEM SET listen_addresses TO '*';"
    
    # Find the correct PostgreSQL configuration directory
    PG_VERSION=$(ls /etc/postgresql)
    PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
    
    # Backup the original pg_hba.conf file
    sudo cp "${PG_CONF_DIR}/pg_hba.conf" "${PG_CONF_DIR}/pg_hba.conf.bak"
    
    # Add rules to pg_hba.conf to allow connections
    sudo tee -a "${PG_CONF_DIR}/pg_hba.conf" > /dev/null <<EOF
# Allow connections from the private network (adjust as needed)
host    all             all             10.0.0.0/24            scram-sha-256
# Allow connections from all IP addresses (use with caution, consider removing in production)
# host    all             all             0.0.0.0/0               scram-sha-256
# host    all             all             ::/0                    scram-sha-256
EOF
    
    sudo systemctl restart postgresql
}

# --- MAIN SCRIPT ---

# Update and upgrade packages
log "Updating and upgrading packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

# Install essential packages
log "Installing required packages..."
sudo apt-get install -y git build-essential libssl-dev libreadline-dev zlib1g-dev

# Install and configure PostgreSQL
install_postgresql
configure_postgresql

# Configure security
configure_firewall
harden_ssh
setup_fail2ban

# Set hostname
sudo hostnamectl set-hostname ubuntu-postgresql-production

# --- CLEANUP AND FINALIZATION ---

# Clean up
log "Cleaning up..."
sudo apt-get autoremove -y
sudo apt-get clean

# Delete command history
history -c

log "Ubuntu 24.04 LTS machine initial setup for PostgreSQL completed successfully."
log "IMPORTANT: Please follow the post-installation instructions for securing your PostgreSQL server."

# --- POST-INSTALLATION INSTRUCTIONS ---

cat << EOF
POST-INSTALLATION INSTRUCTIONS:
1. Set a strong password for the postgres user:
   set +o history
   sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'your_strong_password';"
   set -o history
2. Create additional database users and databases as needed:
   sudo -u postgres createuser --interactive
   sudo -u postgres createdb mydb
3. Configure PostgreSQL for better performance based on your server's resources:
   Edit /etc/postgresql/*/main/postgresql.conf and adjust settings like max_connections,
   shared_buffers, effective_cache_size, etc.
4. Set up regular backups for your databases.
5. Consider setting up replication for high availability if needed.
6. Monitor your PostgreSQL logs regularly:
   tail -f /var/log/postgresql/postgresql-*-main.log
7. Remember, password authentication has been disabled for SSH.
   Always use SSH keys to log into the server.
8. Consider additional security measures like setting up a VPN or using SSL for PostgreSQL connections.
9. Update your system. Make sure to do this regularly for maintenance and security reasons:
   sudo apt update && sudo apt upgrade
10. Reboot the server:
    sudo reboot
EOF