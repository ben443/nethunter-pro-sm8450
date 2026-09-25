#!/bin/sh

set -eu

DTB_NAME="sm8250-samsung-r8q.dtb"
SHARED_DTB="/usr/lib/linux-image-qcom/qcom/${DTB_NAME}"
LINK_TARGET="../../linux-image-qcom/qcom/${DTB_NAME}"
FOUND_VERSIONED=

if [ ! -f "${SHARED_DTB}" ]; then
    echo "WARN: bundled r8q DTB not found at ${SHARED_DTB}; skipping DTB linkage"
    exit 0
fi

for image_dir in /usr/lib/linux-image-*; do
    [ -d "${image_dir}" ] || continue
    [ "${image_dir}" = "/usr/lib/linux-image-qcom" ] && continue
    mkdir -p "${image_dir}/qcom"
    ln -sf "${LINK_TARGET}" "${image_dir}/qcom/${DTB_NAME}"
    FOUND_VERSIONED=1
done

if [ -z "${FOUND_VERSIONED}" ]; then
    echo "WARN: no installed linux-image directories found for r8q DTB linkage"
fi
