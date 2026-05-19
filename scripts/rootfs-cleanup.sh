#!/usr/bin/env sh

## REF: https://gitlab.com/kalilinux/build-scripts/kali-vm/-/blob/main/scripts/finish-install.sh
configure_apt_sources_list() {
    echo "INFO: setting up APT data source kali.sources"

    rm -f /etc/apt/sources.list
    cat  >/etc/apt/sources.list.d/kali.sources <<END
# See https://www.kali.org/docs/general-use/kali-apt-sources/
Types: deb
URIs: http://http.kali.org/kali/
Suites: kali-rolling
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/kali-archive-keyring.gpg
END

    apt-get update
}
configure_apt_sources_list

# Remove apt packages which are no longer unnecessary and delete
# downloaded packages
apt -y autoremove --purge
apt clean

# Remove machine ID so it gets generated on first boot
rm -vf /var/lib/dbus/machine-id
echo uninitialized > /etc/machine-id

# FIXME: these are automatically installed on first boot, and block
# the system startup for over 1 minute! Find out why this happens and
# avoid this nasty hack
rm -vf /lib/systemd/system/wpa_supplicant@.service \
       /lib/systemd/system/wpa_supplicant-wired@.service \
       /lib/systemd/system/wpa_supplicant-nl80211@.service
