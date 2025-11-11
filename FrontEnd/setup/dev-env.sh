#!/bin/bash


set -euo pipefail

# Fix DNS first
systemctl stop systemd-resolved || true
systemctl disable systemd-resolved || true
systemctl mask systemd-resolved || true
chattr -i /etc/resolv.conf 2>/dev/null || true
rm -f /etc/resolv.conf
printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > /etc/resolv.conf
chattr +i /etc/resolv.conf

# Set environment variables
echo 'export DISPLAY=:0' >> /etc/environment
echo 'export XDG_CURRENT_DESKTOP=GNOME' >> /etc/environment
echo 'export XDG_SESSION_TYPE=x11' >> /etc/environment

# Set LightDM as default BEFORE installing packages
mkdir -p /etc/X11
echo '/usr/sbin/lightdm' > /etc/X11/default-display-manager

# Update packages
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# Install individual desktop packages (maximum control, no bloat)
apt-get install -y -qq \
      xorg \
      gnome-session \
      gnome-shell \
      gnome-terminal \
      nautilus \
      gnome-settings-daemon \
      gnome-control-center \
      lightdm \
      lightdm-gtk-greeter \
      ubuntu-session \
      xdg-desktop-portal-gnome

    # CRITICAL: Stop GDM3 immediately after installation
    # It auto-starts when installed and will steal the display
systemctl stop gdm3 || true
systemctl disable gdm3 || true
systemctl mask gdm3 || true

    # Verify session file exists before configuring auto-login
if [ ! -f /usr/share/xsessions/ubuntu.desktop ]; then
     echo "❌ Ubuntu session file not found!"
     ls -la /usr/share/xsessions/
     exit 1
fi

    # Configure auto-login
usermod -a -G nopasswdlogin vagrant

mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf << 'EOF'
[Seat:*]
autologin-user=vagrant
autologin-user-timeout=0
autologin-session=ubuntu
greeter-show-manual-login=false
allow-guest=false
EOF

# Explicitly create the display-manager.service symlink
ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service

# Enable LightDM
systemctl enable lightdm

# Verify the symlink was created
if [ ! -L /etc/systemd/system/display-manager.service ]; then
    echo "❌ Failed to create display-manager.service symlink"
    exit 1
fi

# Start LightDM immediately
systemctl start lightdm

# Verify it started successfully
if ! systemctl is-active --quiet lightdm; then
     echo "❌ LightDM failed to start"
     journalctl -u lightdm -n 20
     exit 1
fi

# Mark essential packages as manually installed (after installation)
apt-mark manual gnome-session gnome-session-bin gnome-session-common lightdm lightdm-gtk-greeter ubuntu-session xdg-desktop-portal-gnome

# Verify it worked
protected_count=$(apt-mark showmanual | grep -E "(gnome-session|ubuntu-session|xdg-desktop-portal|lightdm)" | wc -l)
if [ "$protected_count" -lt 7 ]; then
    echo "❌ MARKING FAILED! Only $protected_count/7 packages marked as manual"
    exit 1
fi

echo "✅ Desktop environment ready!"