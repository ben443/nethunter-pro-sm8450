#!/bin/sh

SCRIPT="$0"
DEVICE="$1"
WORKDIR="$(mktemp -d /tmp/qcom-bootloader.XXXXXX)"
EMPTY_RAMDISK="${WORKDIR}/empty-ramdisk"

cleanup() {
    rm -rf "${WORKDIR}"
}
trap cleanup EXIT INT TERM

CONFIG="$(dirname ${SCRIPT})/configs/${DEVICE}.toml"
if ! [ -f "${CONFIG}" ]; then
    echo "ERROR: No configuration for device type '${DEVICE}'!"
    exit 1
fi
MKBOOTIMG_KERNEL_SOURCE=$(tomlq -r 'if .bootimg.kernel_source then .bootimg.kernel_source else "kernel" end' "${CONFIG}")
UNILOADER_VERSION_FILE="/usr/share/uniloader-sm8450/kernel-version"

bootimg_offsets() {
    local BOOTIMG="$1"
    local INCLUDE_DTB="${2:-1}"

    local BASE="$(echo "${BOOTIMG}" | jq -r 'if .base then .base else 0 end' -)"
    local VERSION="$(echo "${BOOTIMG}" | jq -r 'if .version then .version else 0 end' -)"
    local KERNEL="$(echo "${BOOTIMG}" | jq -r '.kernel' -)"
    local RAMDISK="$(echo "${BOOTIMG}" | jq -r '.ramdisk' -)"
    local SECOND="$(echo "${BOOTIMG}" | jq -r '.second' -)"
    local TAGS="$(echo "${BOOTIMG}" | jq -r '.tags' -)"
    local PAGE_SIZE="$(echo "${BOOTIMG}" | jq -r '.pagesize' -)"
    local DTB="$(echo "${BOOTIMG}" | jq -r 'if .dtb then .dtb else "" end' -)"

    local ARGS="--base ${BASE} --kernel_offset ${KERNEL} --ramdisk_offset ${RAMDISK}"
    ARGS="${ARGS} --second_offset ${SECOND} --tags_offset ${TAGS}"
    ARGS="${ARGS} --pagesize ${PAGE_SIZE}"

    if [ "${VERSION}" != "0" ]; then
        ARGS="${ARGS} --header_version ${VERSION}"
    fi

    if [ "${INCLUDE_DTB}" = "1" ] && [ "${DTB}" ]; then
        ARGS="${ARGS} --dtb_offset ${DTB}"
    fi

    echo "${ARGS}"
}

ROOTPART="UUID=$(findmnt -n -o UUID /)"
if [ "${ROOTPART}" = "UUID=" ]; then
    # This means we're using an encrypted rootfs
    ROOTPART="/dev/mapper/root"
fi
KERNEL_IMAGE=""
KERNEL_VERSION=""
RAMDISK_IMAGE=""

resolve_vmlinuz_path() {
    path="/vmlinuz"
    if command -v readlink >/dev/null 2>&1; then
        resolved="$(readlink -f "${path}" 2>/dev/null || true)"
        if [ -n "${resolved}" ]; then
            printf '%s\n' "${resolved}"
            return
        fi
        if [ -L "${path}" ]; then
            link_target="$(readlink "${path}" 2>/dev/null || true)"
            if [ -n "${link_target}" ]; then
                case "${link_target}" in
                    /*) printf '%s\n' "${link_target}" ;;
                    *) printf '%s\n' "$(dirname "${path}")/${link_target}" ;;
                esac
                return
            fi
        fi
    fi
    printf '%s\n' "${path}"
}

consider_kernel_candidate() {
    candidate="$1"
    version="$(kernel_candidate_version "${candidate}")" || return 1

    ramdisk_candidate="/boot/initrd.img-${version}"
    if [ ! -f "${ramdisk_candidate}" ]; then
        ramdisk_candidate="/boot/initramfs-${version}.img"
    fi

    if [ -f "${candidate}" ] && [ -f "${ramdisk_candidate}" ]; then
        KERNEL_IMAGE="${candidate}"
        KERNEL_VERSION="${version}"
        RAMDISK_IMAGE="${ramdisk_candidate}"
        return 0
    fi
    return 1
}

kernel_candidate_version() {
    candidate="$1"
    base="$(basename "${candidate}")"
    case "${base}" in
        vmlinuz-*)
            printf '%s\n' "${base#vmlinuz-}"
            return 0
            ;;
        vmlinuz|Image)
            parent="$(basename "$(dirname "${candidate}")")"
            case "${parent}" in
                linux-image-*)
                    printf '%s\n' "${parent#linux-image-}"
                    return 0
                    ;;
            esac
            ;;
    esac
    return 1
}

kernel_candidate_priority() {
    candidate="$1"
    case "${candidate}" in
        /usr/lib/linux-image-*/Image)
            printf '0\n'
            ;;
        /usr/lib/linux-image-*/vmlinuz)
            printf '1\n'
            ;;
        *)
            printf '2\n'
            ;;
    esac
}

list_kernel_candidates() {
    for candidate in /boot/vmlinuz-* /usr/lib/linux-image-*/vmlinuz /usr/lib/linux-image-*/Image; do
        [ -f "${candidate}" ] || continue
        version="$(kernel_candidate_version "${candidate}")" || continue
        priority="$(kernel_candidate_priority "${candidate}")"
        printf '%s\t%s\t%s\n' "${version}" "${priority}" "${candidate}"
    done | sort -t '	' -k1,1Vr -k2,2n | awk -F '	' '!seen[$3]++ { print $3 }'
}

consider_kernel_version() {
    version="$1"
    [ -n "${version}" ] || return 1
    for candidate in \
        "/usr/lib/linux-image-${version}/Image" \
        "/usr/lib/linux-image-${version}/vmlinuz" \
        "/boot/vmlinuz-${version}"
    do
        if consider_kernel_candidate "${candidate}"; then
            return 0
        fi
    done
    return 1
}

prefer_uniloader_kernel_version() {
    [ "${MKBOOTIMG_KERNEL_SOURCE}" = "uniloader" ] || return 1
    [ -r "${UNILOADER_VERSION_FILE}" ] || return 1
    version="$(sed -n '1p' "${UNILOADER_VERSION_FILE}" 2>/dev/null || true)"
    consider_kernel_version "${version}"
}

resolve_uniloader_path() {
    for candidate in /usr/sbin/uniLoader /usr/sbin/uniloader; do
        if [ -x "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    if command -v uniLoader >/dev/null 2>&1; then
        command -v uniLoader
        return 0
    fi
    if command -v uniloader >/dev/null 2>&1; then
        command -v uniloader
        return 0
    fi
    return 1
}

if [ -z "${KERNEL_IMAGE}" ]; then
    prefer_uniloader_kernel_version || true
fi
if [ -z "${KERNEL_IMAGE}" ] && [ -e /vmlinuz ]; then
    consider_kernel_candidate "$(resolve_vmlinuz_path)" || true
fi
if [ -z "${KERNEL_IMAGE}" ]; then
    list_kernel_candidates > "${WORKDIR}/kernel-candidates.txt"
    while IFS= read -r candidate; do
        if consider_kernel_candidate "${candidate}"; then
            break
        fi
    done < "${WORKDIR}/kernel-candidates.txt"
fi
if [ -z "${KERNEL_IMAGE}" ] || [ -z "${KERNEL_VERSION}" ] || [ -z "${RAMDISK_IMAGE}" ]; then
    echo "WARN: unable to locate matching kernel and ramdisk artifacts for ${DEVICE}; skipping boot image generation"
    exit 0
fi

# Parse config for generic parameters for the current SoC
SOC=$(tomlq -r "if .chipset then .chipset else \"${DEVICE}\" end" "${CONFIG}")
for i in $(seq 0 $(tomlq -r '.device | length - 1' "${CONFIG}")); do
    # Parse device-specific parameters
    VENDOR=$(tomlq -r ".device[$i].vendor" "${CONFIG}")
    MODEL=$(tomlq -r ".device[$i].model" "${CONFIG}")
    VARIANT=$(tomlq -r "if .device[$i].variant then .device[$i].variant else \"\" end" "${CONFIG}")
    DEVICE_SOC=$(tomlq -r "if .device[$i].chipset then .device[$i].chipset else \"${SOC}\" end" "${CONFIG}")
    DTB_VENDOR=$(tomlq -r "if .device[$i].dtb_vendor then .device[$i].dtb_vendor else \"${VENDOR}\" end" "${CONFIG}")
    DTB_MODEL=$(tomlq -r "if .device[$i].dtb_model then .device[$i].dtb_model else \"${MODEL}\" end" "${CONFIG}")
    DTB_VARIANT=$(tomlq -r "if .device[$i].dtb_variant then .device[$i].dtb_variant else \"${VARIANT}\" end" "${CONFIG}")
    APPEND=$(tomlq -r "if .device[$i].append then .device[$i].append else \"\" end" "${CONFIG}")
    # Extract device-specific bootimg parameters in JSON format for processing by `bootimg_offsets()`
    DEVICE_BOOTIMG=$(tomlq -r "if .device[$i].bootimg then .device[$i].bootimg else \"\" end" "${CONFIG}")
    BOOTIMG_KERNEL_SOURCE=$(tomlq -r "if .device[$i].bootimg.kernel_source then .device[$i].bootimg.kernel_source else \"${MKBOOTIMG_KERNEL_SOURCE}\" end" "${CONFIG}")

    CMDLINE="mobile.qcomsoc=qcom/${DEVICE_SOC} mobile.vendor=${VENDOR} mobile.model=${MODEL}"
    if [ "${VARIANT}" ]; then
        CMDLINE="${CMDLINE} mobile.variant=${VARIANT}"
        FULLMODEL="${MODEL}-${VARIANT}"
    else
        FULLMODEL="${MODEL}"
    fi
    if [ "${DTB_VARIANT}" ]; then
        DTB_FULLMODEL="${DTB_MODEL}-${DTB_VARIANT}"
    else
        DTB_FULLMODEL="${DTB_MODEL}"
    fi
    DTB_FILE="/usr/lib/linux-image-${KERNEL_VERSION}/qcom/${DEVICE_SOC}-${DTB_VENDOR}-${DTB_FULLMODEL}.dtb"

    LOGLEVEL="quiet"
    # Include additional cmdline args if specified
    if [ "${APPEND}" ]; then
        CMDLINE="${CMDLINE} ${APPEND}"
        if echo "${APPEND}" | grep -q "console="; then
            LOGLEVEL="loglevel=7"
        fi
    fi

    INCLUDE_DTB=1
    if [ "${BOOTIMG_KERNEL_SOURCE}" = "uniloader" ]; then
        INCLUDE_DTB=0
    fi
    if [ "${DEVICE_BOOTIMG}" ]; then
        BOOTIMG_ARGS="$(bootimg_offsets "${DEVICE_BOOTIMG}" "${INCLUDE_DTB}")"
    else
        BOOTIMG_ARGS="$(bootimg_offsets "$(tomlq -r '.bootimg' "${CONFIG}")" "${INCLUDE_DTB}")"
    fi

    KERNEL_ARG="${KERNEL_IMAGE}"
    RAMDISK_ARG="${RAMDISK_IMAGE}"
    BOOTIMG_CMDLINE="mobile.root=${ROOTPART} ${CMDLINE} init=/sbin/init ro ${LOGLEVEL} splash"
    if [ "${BOOTIMG_KERNEL_SOURCE}" = "uniloader" ]; then
        if ! KERNEL_ARG="$(resolve_uniloader_path)"; then
            echo "WARN: unable to locate an installed uniLoader payload for ${FULLMODEL}; skipping boot image generation"
            continue
        fi
        : > "${EMPTY_RAMDISK}"
        RAMDISK_ARG="${EMPTY_RAMDISK}"
    elif echo "${BOOTIMG_ARGS}" | grep -q "dtb_offset"; then
        if ! [ -f "${DTB_FILE}" ]; then
            echo "WARN: unable to locate DTB artifact for ${FULLMODEL}; skipping boot image generation"
            continue
        fi
        BOOTIMG_ARGS="${BOOTIMG_ARGS} --dtb ${DTB_FILE}"
        KERNEL_DTB="${WORKDIR}/kernel-dtb-${FULLMODEL}"
        cat "${KERNEL_IMAGE}" "${DTB_FILE}" > "${KERNEL_DTB}"
        KERNEL_ARG="${KERNEL_DTB}"
    fi

    echo "Creating boot image for ${FULLMODEL}..."

    # Create the bootimg as it's the only format recognized by the Android bootloader
    mkbootimg -o /bootimg-${FULLMODEL} ${BOOTIMG_ARGS} \
        --kernel "${KERNEL_ARG}" --ramdisk "${RAMDISK_ARG}" \
        --cmdline "${BOOTIMG_CMDLINE}"
done
