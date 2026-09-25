#!/bin/sh

set -eu

RESUME_CONF="/etc/initramfs-tools/conf.d/resume"
BACKUP="$(mktemp)"
HAD_RESUME=0
UPDATED=0
TAB="$(printf '\t')"
PACKAGE_LINES="$(dpkg-query -W -f='${Package}\t${Version}\n' 2>/dev/null || true)"

cleanup() {
    if [ "${HAD_RESUME}" -eq 1 ]; then
        mv "${BACKUP}" "${RESUME_CONF}"
    else
        rm -f "${RESUME_CONF}" "${BACKUP}"
    fi
}
trap cleanup EXIT INT TERM

if [ -f "${RESUME_CONF}" ]; then
    cp "${RESUME_CONF}" "${BACKUP}"
    HAD_RESUME=1
fi

while IFS="${TAB}" read -r package version; do
    [ -n "${package}" ] || continue
    case "${package}" in
        linux-image-*) ;;
        *) continue ;;
    esac
    case "${version}" in
        *-r8q*) ;;
        *) continue ;;
    esac
    echo "RESUME=none" > "${RESUME_CONF}"
    update-initramfs -u -k "${package#linux-image-}"
    UPDATED=1
done <<EOF
${PACKAGE_LINES}
EOF

if [ "${UPDATED}" -eq 0 ]; then
    echo "ERROR: no installed r8q linux-image package found for initramfs update" >&2
    exit 1
fi
