#!/bin/sh

SCRIPT="$0"
DEVICE="$1"
WORKDIR="$(mktemp -d /tmp/qcom-bootloader.XXXXXX)"

cleanup() {
    rm -rf "${WORKDIR}"
}
trap cleanup EXIT INT TERM

CONFIG="$(dirname ${SCRIPT})/configs/${DEVICE}.toml"
if ! [ -f "${CONFIG}" ]; then
    echo "ERROR: No configuration for device type '${DEVICE}'!"
    exit 1
fi

bootimg_offsets() {
    local BOOTIMG="$1"

    local VERSION="$(echo "${BOOTIMG}" | jq -r 'if .version then .version else 0 end' -)"
    local KERNEL="$(echo "${BOOTIMG}" | jq -r '.kernel + .base' -)"
    local RAMDISK="$(echo "${BOOTIMG}" | jq -r '.ramdisk + .base' -)"
    local SECOND="$(echo "${BOOTIMG}" | jq -r '.second + .base' -)"
    local TAGS="$(echo "${BOOTIMG}" | jq -r '.tags + .base' -)"
    local PAGE_SIZE="$(echo "${BOOTIMG}" | jq -r '.pagesize' -)"
    local DTB="$(echo "${BOOTIMG}" | jq -r 'if .dtb then .dtb + .base else "" end' -)"

    local ARGS="--kernel_offset ${KERNEL} --ramdisk_offset ${RAMDISK}"
    ARGS="${ARGS} --second_offset ${SECOND} --tags_offset ${TAGS}"
    ARGS="${ARGS} --pagesize ${PAGE_SIZE}"

    if [ "${VERSION}" != "0" ]; then
        ARGS="${ARGS} --header_version ${VERSION}"
    fi

    if [ "${DTB}" ]; then
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
CANDIDATE_VERSION=""
CANDIDATE_PRIORITY=""

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

kernel_candidate_metadata() {
    candidate="$1"
    base="$(basename "${candidate}")"
    parent="$(basename "$(dirname "${candidate}")")"

    CANDIDATE_VERSION=""
    CANDIDATE_PRIORITY=""
    case "${base}" in
        vmlinuz-*)
            CANDIDATE_VERSION="${base#vmlinuz-}"
            CANDIDATE_PRIORITY=2
            ;;
        vmlinuz|Image)
            case "${parent}" in
                linux-image-*)
                    CANDIDATE_VERSION="${parent#linux-image-}"
                    ;;
                *)
                    return 1
                    ;;
            esac
            if [ "${base}" = "Image" ]; then
                CANDIDATE_PRIORITY=0
            else
                CANDIDATE_PRIORITY=1
            fi
            ;;
        *)
            return 1
            ;;
    esac

    [ -n "${CANDIDATE_VERSION}" ] && [ -n "${CANDIDATE_PRIORITY}" ]
}

consider_kernel_candidate() {
    candidate="$1"
    kernel_candidate_metadata "${candidate}" || return 1
    version="${CANDIDATE_VERSION}"
    kernel_candidate="/boot/vmlinuz-${version}"
    packaged_kernel_candidate="/usr/lib/linux-image-${version}/vmlinuz"
    raw_kernel_candidate="/usr/lib/linux-image-${version}/Image"
    ramdisk_candidate="/boot/initrd.img-${version}"
    if [ ! -f "${ramdisk_candidate}" ]; then
        ramdisk_candidate="/boot/initramfs-${version}.img"
    fi

    if [ -f "${raw_kernel_candidate}" ] && [ -f "${ramdisk_candidate}" ]; then
        KERNEL_IMAGE="${raw_kernel_candidate}"
        KERNEL_VERSION="${version}"
        RAMDISK_IMAGE="${ramdisk_candidate}"
        return 0
    fi
    if [ -f "${packaged_kernel_candidate}" ] && [ -f "${ramdisk_candidate}" ]; then
        KERNEL_IMAGE="${packaged_kernel_candidate}"
        KERNEL_VERSION="${version}"
        RAMDISK_IMAGE="${ramdisk_candidate}"
        return 0
    fi
    if [ -f "${kernel_candidate}" ] && [ -f "${ramdisk_candidate}" ]; then
        KERNEL_IMAGE="${kernel_candidate}"
        KERNEL_VERSION="${version}"
        RAMDISK_IMAGE="${ramdisk_candidate}"
        return 0
    fi
    return 1
}

resolve_dtb_path() {
    local dtb_name="$1"
    for candidate in \
        "/usr/lib/linux-image-${KERNEL_VERSION}/qcom/${dtb_name}" \
        "/usr/lib/linux-image-qcom/qcom/${dtb_name}"
    do
        if [ -f "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

if [ -e /vmlinuz ]; then
    consider_kernel_candidate "$(resolve_vmlinuz_path)" || true
fi
if [ -z "${KERNEL_IMAGE}" ]; then
    tab="$(printf '\t')"
    for candidate in /boot/vmlinuz-* /usr/lib/linux-image-*/vmlinuz /usr/lib/linux-image-*/Image; do
        [ -f "${candidate}" ] || continue
        if kernel_candidate_metadata "${candidate}"; then
            printf '%s%s%s%s%s\n' "${CANDIDATE_VERSION}" "${tab}" "${CANDIDATE_PRIORITY}" "${tab}" "${candidate}"
        fi
    done | sort -t "${tab}" -k1,1Vr -k2,2n | cut -f3- > "${WORKDIR}/kernel-candidates.txt"
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
SOC=$(tomlq -r "if .chipset then .chipset else \"${DEVICE}\" end" ${CONFIG})
MKBOOTIMG_ARGS="$(bootimg_offsets "$(tomlq -r '.bootimg' ${CONFIG})")"

for i in $(seq 0 $(tomlq -r '.device | length - 1' ${CONFIG})); do
    # Parse device-specific parameters
    VENDOR=$(tomlq -r ".device[$i].vendor" ${CONFIG})
    MODEL=$(tomlq -r ".device[$i].model" ${CONFIG})
    VARIANT=$(tomlq -r "if .device[$i].variant then .device[$i].variant else \"\" end" ${CONFIG})
    DEVICE_SOC=$(tomlq -r "if .device[$i].chipset then .device[$i].chipset else \"${SOC}\" end" ${CONFIG})
    DTB_VENDOR=$(tomlq -r "if .device[$i].dtb_vendor then .device[$i].dtb_vendor else \"${VENDOR}\" end" ${CONFIG})
    DTB_MODEL=$(tomlq -r "if .device[$i].dtb_model then .device[$i].dtb_model else \"${MODEL}\" end" ${CONFIG})
    DTB_VARIANT=$(tomlq -r "if .device[$i].dtb_variant then .device[$i].dtb_variant else \"${VARIANT}\" end" ${CONFIG})
    APPEND=$(tomlq -r "if .device[$i].append then .device[$i].append else \"\" end" ${CONFIG})
    # Extract device-specific bootimg parameters in JSON format for processing by `bootimg_offsets()`
    DEVICE_BOOTIMG=$(tomlq -r "if .device[$i].bootimg then .device[$i].bootimg else \"\" end" ${CONFIG})

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
    DTB_NAME="${DEVICE_SOC}-${DTB_VENDOR}-${DTB_FULLMODEL}.dtb"

    LOGLEVEL="quiet"
    # Include additional cmdline args if specified
    if [ "${APPEND}" ]; then
        CMDLINE="${CMDLINE} ${APPEND}"
        if echo "${APPEND}" | grep -q "console="; then
            LOGLEVEL="loglevel=7"
        fi
    fi

    if [ "${DEVICE_BOOTIMG}" ]; then
        BOOTIMG_ARGS="$(bootimg_offsets "${DEVICE_BOOTIMG}")"
    else
        BOOTIMG_ARGS="${MKBOOTIMG_ARGS}"
    fi

    KERNEL_ARG="${KERNEL_IMAGE}"
    if echo "${BOOTIMG_ARGS}" | grep -q "dtb_offset"; then
        if ! DTB_FILE="$(resolve_dtb_path "${DTB_NAME}")"; then
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
        --kernel "${KERNEL_ARG}" --ramdisk "${RAMDISK_IMAGE}" \
        --cmdline "mobile.root=${ROOTPART} ${CMDLINE} init=/sbin/init ro ${LOGLEVEL} splash"
done
