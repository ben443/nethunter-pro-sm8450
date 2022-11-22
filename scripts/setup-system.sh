#!/bin/sh

# Setup hostname
echo "$1" > /etc/hostname

# Change plymouth default theme
plymouth-set-default-theme kali

# Enable phog greeter if package is installed
if [ -f /usr/bin/phog ]; then
    systemctl enable greetd.service
fi

# Enable essential services
systemctl enable bluetooth.service

# systemd-firstboot requires user input, which isn't possible
# on mobile devices
systemctl mask systemd-firstboot.service
