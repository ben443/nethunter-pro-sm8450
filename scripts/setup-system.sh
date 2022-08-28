#!/bin/sh

# Setup hostname
echo "$1" > /etc/hostname

# Change plymouth default theme
plymouth-set-default-theme kali

# Enable essential services
systemctl enable bluetooth.service

# systemd-firstboot requires user input, which isn't possible
# on mobile devices
systemctl mask systemd-firstboot.service
