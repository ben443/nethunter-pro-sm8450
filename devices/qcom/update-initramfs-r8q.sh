#!/bin/sh

set -eu

RESUME_CONF="/etc/initramfs-tools/conf.d/resume"
BACKUP=""
HAD_RESUME=0
UPDATED=0

cleanup() {
    if [ "${HAD_RESUME}" -eq 1 ]; then
        mv "${BACKUP}" "${RESUME_CONF}"
    else
        rm -f "${RESUME_CONF}" "${BACKUP}"
    fi
}
trap cleanup EXIT

if [ -f "${RESUME_CONF}" ]; then
    BACKUP="$(mktemp)"
    cp "${RESUME_CONF}" "${BACKUP}"
    HAD_RESUME=1
fi

echo "RESUME=none" > "${RESUME_CONF}"

for kernel_image in /boot/vmlinuz-*; do
    [ -f "${kernel_image}" ] || continue
    version="${kernel_image#/boot/vmlinuz-}"
    case "${version}" in
        *.gz|*.xz|*.zst|*.lz4|*.bz2)
            version="${version%.*}"
            ;;
    esac
    [ -d "/lib/modules/${version}" ] || [ -d "/usr/lib/linux-image-${version}" ] || continue
    update-initramfs -u -k "${version}"
    UPDATED=1
done

if [ "${UPDATED}" -eq 0 ]; then
    echo "WARN: no installed r8q kernel artifacts found for initramfs update; leaving existing initramfs untouched"
fi
