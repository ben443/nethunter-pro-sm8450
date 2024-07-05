#!/bin/sh

DEBIAN_SUITE=$1
SUITE=$2

# Add debian-security for stable releases; note that only the main component is supported
if [ "${DEBIAN_SUITE}" = "bullseye" ] || [ "${DEBIAN_SUITE}" = "bookworm" ] || [ "${DEBIAN_SUITE}" = "trixie" ]; then
    echo "deb http://security.debian.org/ ${DEBIAN_SUITE}-security main" >> /etc/apt/sources.list
else
    case "${DEBIAN_SUITE}" in
        kali-*)
            echo "deb http://http.kali.org/kali ${DEBIAN_SUITE} ${SUITE}" > /etc/apt/sources.list
            ;;
    esac
fi

# Set the proper suite in our sources file
sed -i "s/Suites: .*/Suites: ${SUITE}/" /etc/apt/sources.list.d/mobian.sources

# Prefer certain packages from Mobian, rather than Kali
cat > /etc/apt/preferences.d/10-mobian-priority << EOF
Package: u-boot-menu*
Pin: release o=Mobian
Pin-Priority: 700

Package: alsa-ucm-conf
Pin: release o=Mobian
Pin-Priority: 700

Package: libqrtr1
Pin: release o=Mobian
Pin-Priority: 700

Package: protection-domain-mapper
Pin: release o=Mobian
Pin-Priority: 700

Package: qrtr-tools
Pin: release o=Mobian
Pin-Priority: 700
EOF

# Prefer Kali packages by default
cat > /etc/apt/preferences.d/00-kali-priority << EOF
Package: *
Pin: release o=Kali
Pin-Priority: 600
EOF
