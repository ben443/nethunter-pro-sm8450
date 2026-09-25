#!/bin/sh

set -eu

DTB_NAME="sm8250-samsung-r8q.dtb"
SHARED_DTB="/usr/lib/linux-image-qcom/qcom/${DTB_NAME}"
LINK_TARGET="${SHARED_DTB}"
FOUND_VERSIONED=
TAB="$(printf '\t')"
PACKAGE_LINES="$(dpkg-query -W -f='${Package}\t${Version}\n' 'linux-image-*' 2>/dev/null || true)"

if [ ! -f "${SHARED_DTB}" ]; then
    echo "WARN: bundled r8q DTB not found at ${SHARED_DTB}; skipping DTB linkage"
    exit 0
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
    image_dir="/usr/lib/${package}"
    mkdir -p "${image_dir}/qcom"
    ln -sf "${LINK_TARGET}" "${image_dir}/qcom/${DTB_NAME}"
    FOUND_VERSIONED=1
done <<EOF
${PACKAGE_LINES}
EOF

if [ -z "${FOUND_VERSIONED}" ]; then
    echo "WARN: no installed r8q linux-image packages found for DTB linkage"
fi
