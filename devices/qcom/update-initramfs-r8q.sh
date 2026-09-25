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

for modules_dir in /lib/modules/*; do
    [ -d "${modules_dir}" ] || continue
    version="$(basename "${modules_dir}")"
    [ -f "/boot/vmlinuz-${version}" ] || continue
    echo "RESUME=none" > "${RESUME_CONF}"
    update-initramfs -u -k "${version}"
    UPDATED=1
done

if [ "${UPDATED}" -eq 0 ]; then
    echo "ERROR: no installed kernel version with matching /boot/vmlinuz entry found for initramfs update" >&2
    exit 1
fi
