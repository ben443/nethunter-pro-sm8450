#!/bin/sh

set -eu

UL_REPO="https://github.com/ivoszbg/uniLoader.git"
UL_COMMIT="43770a04327532407194ddd3f9f35770daa01c70"
PORT_REPO_REF="c663da1b06c8e660a1dee107cfa26511080a8819"
PORT_BASE_URL="https://raw.githubusercontent.com/aaronsb/sm-x800-linux/${PORT_REPO_REF}/pmaports-overlay/uniloader-port"
BOARD_FILE="board/samsung/board-gts8pwifi.c"
BOARD_SHA256="f8a94f908f8a46a4e7cb6a39811d462afe06289993359fd7542a290de14c6de7"
DEFCONFIG_FILE="configs/gts8pwifi_defconfig"
DEFCONFIG_SHA256="23c622f0a93017c82de673fcfc2c01315f06ab74317a8bd56cfd04dc47fcdc66"
REGISTRATION_FILE="REGISTRATION.txt"
REGISTRATION_SHA256="52656f6b21b38488afcae99b1ca818b57eac4d1f974dc61c35287d659eddc0cd"

WORKDIR="$(mktemp -d /tmp/uniloader-sm8450.XXXXXX)"
cleanup() {
    rm -rf "${WORKDIR}"
}
trap cleanup EXIT INT TERM

BUILD_ARCH="$(dpkg --print-architecture)"
if [ "${BUILD_ARCH}" = "arm64" ]; then
    CROSS_COMPILE_PREFIX=""
else
    CROSS_COMPILE_PREFIX="aarch64-linux-gnu-"
    if ! command -v "${CROSS_COMPILE_PREFIX}gcc" >/dev/null 2>&1; then
        echo "ERROR: missing cross-compiler ${CROSS_COMPILE_PREFIX}gcc for ${BUILD_ARCH} build"
        exit 1
    fi
fi

KERNEL_IMAGE=""
KERNEL_VERSION=""
RAMDISK_IMAGE=""
DTB_IMAGE=""

consider_candidate() {
    candidate="$1"
    base="$(basename "${candidate}")"
    case "${base}" in
        vmlinuz-*)
            version="${base#vmlinuz-}"
            ;;
        *)
            return 1
            ;;
    esac

    ramdisk_candidate="/boot/initrd.img-${version}"
    if [ ! -f "${ramdisk_candidate}" ]; then
        ramdisk_candidate="/boot/initramfs-${version}.img"
    fi
    dtb_candidate="/usr/lib/linux-image-${version}/qcom/sm8450-samsung-gts8pwifi.dtb"

    if [ -f "${candidate}" ] && [ -f "${ramdisk_candidate}" ] && [ -f "${dtb_candidate}" ]; then
        KERNEL_IMAGE="${candidate}"
        KERNEL_VERSION="${version}"
        RAMDISK_IMAGE="${ramdisk_candidate}"
        DTB_IMAGE="${dtb_candidate}"
        return 0
    fi
    return 1
}

if [ -e /vmlinuz ]; then
    consider_candidate "$(readlink -f /vmlinuz)" || true
fi
if [ -z "${KERNEL_IMAGE}" ]; then
    find /boot -maxdepth 1 -type f -name 'vmlinuz-*' | sort -Vr > "${WORKDIR}/kernel-candidates.txt"
    while IFS= read -r candidate; do
        if consider_candidate "${candidate}"; then
            break
        fi
    done < "${WORKDIR}/kernel-candidates.txt"
fi

if [ -z "${KERNEL_IMAGE}" ] || [ -z "${KERNEL_VERSION}" ]; then
    echo "ERROR: unable to locate matching kernel, ramdisk, and DTB artifacts for sm8450"
    exit 1
fi
RAW_KERNEL_IMAGE="/usr/lib/linux-image-${KERNEL_VERSION}/Image"

for file in "${KERNEL_IMAGE}" "${RAMDISK_IMAGE}" "${DTB_IMAGE}"; do
    if [ ! -f "${file}" ]; then
        echo "ERROR: missing required input for uniLoader build: ${file}"
        exit 1
    fi
done

git init -q "${WORKDIR}/uniLoader"
git -C "${WORKDIR}/uniLoader" remote add origin "${UL_REPO}"
git -C "${WORKDIR}/uniLoader" fetch -q --depth 1 origin "${UL_COMMIT}"
git -C "${WORKDIR}/uniLoader" checkout -q FETCH_HEAD

mkdir -p "${WORKDIR}/uniLoader/board/samsung" "${WORKDIR}/uniLoader/configs"
wget -q -O "${WORKDIR}/uniLoader/${BOARD_FILE}" "${PORT_BASE_URL}/${BOARD_FILE}"
wget -q -O "${WORKDIR}/uniLoader/${DEFCONFIG_FILE}" "${PORT_BASE_URL}/${DEFCONFIG_FILE}"
wget -q -O "${WORKDIR}/${REGISTRATION_FILE}" "${PORT_BASE_URL}/${REGISTRATION_FILE}"

echo "${BOARD_SHA256}  ${WORKDIR}/uniLoader/${BOARD_FILE}" | sha256sum -c -
echo "${DEFCONFIG_SHA256}  ${WORKDIR}/uniLoader/${DEFCONFIG_FILE}" | sha256sum -c -
echo "${REGISTRATION_SHA256}  ${WORKDIR}/${REGISTRATION_FILE}" | sha256sum -c -

PARSED_LINE=""
PARSED_TEXT=""
parse_registration_entry() {
    target_file="$1"
    entry="$(grep "^reference/uniLoader/${target_file}:[0-9][0-9]*:" "${WORKDIR}/${REGISTRATION_FILE}" || true)"
    count="$(printf '%s\n' "${entry}" | sed '/^$/d' | awk 'END { print NR }')"
    if [ "${count}" -ne 1 ]; then
        echo "ERROR: expected exactly one registration entry for ${target_file}"
        exit 1
    fi
    PARSED_LINE="$(printf '%s\n' "${entry}" | cut -d: -f2)"
    PARSED_TEXT="$(printf '%s\n' "${entry}" | cut -d: -f3-)"
}

parse_registration_entry "board/Makefile"
MAKEFILE_REG_LINE="${PARSED_LINE}"
MAKEFILE_REG_TEXT="${PARSED_TEXT}"
parse_registration_entry "board/Kconfig"
KCONFIG_REG_LINE="${PARSED_LINE}"
KCONFIG_REG_TEXT="${PARSED_TEXT}"
for required in "${MAKEFILE_REG_LINE}" "${MAKEFILE_REG_TEXT}" "${KCONFIG_REG_LINE}" "${KCONFIG_REG_TEXT}"; do
    if [ -z "${required}" ]; then
        echo "ERROR: invalid registration metadata for gts8pwifi board integration"
        exit 1
    fi
done

if ! grep -Eq '^[[:space:]]*config[[:space:]]+SAMSUNG_GTS8PWIFI$' "${WORKDIR}/uniLoader/board/Kconfig"; then
    awk -v line="${KCONFIG_REG_LINE}" -v reg_text="${KCONFIG_REG_TEXT}" '
        BEGIN { inserted=0 }
        NR==line && inserted==0 {
            print reg_text
            print "\t\tbool \"Support for Samsung Galaxy Tab S8 WiFi\""
            print "\t\tdefault n"
            print "\t\tdepends on SM8450"
            print "\t\thelp"
            print "\t\t  Say Y if you want to include support for Samsung Galaxy Tab S8 WiFi"
            inserted=1
        }
        { print }
        END { if (inserted==0) exit 1 }
    ' "${WORKDIR}/uniLoader/board/Kconfig" > "${WORKDIR}/uniLoader/board/Kconfig.tmp" || {
        echo "ERROR: failed to insert SAMSUNG_GTS8PWIFI into board/Kconfig"
        exit 1
    }
    mv "${WORKDIR}/uniLoader/board/Kconfig.tmp" "${WORKDIR}/uniLoader/board/Kconfig"
fi

if ! grep -Eq '^lib-\$\(CONFIG_SAMSUNG_GTS8PWIFI\)[[:space:]]+\+=[[:space:]]+samsung/board-gts8pwifi\.o$' "${WORKDIR}/uniLoader/board/Makefile"; then
    awk -v line="${MAKEFILE_REG_LINE}" -v reg_text="${MAKEFILE_REG_TEXT}" '
        BEGIN { inserted=0 }
        NR==line && inserted==0 {
            print reg_text
            inserted=1
        }
        { print }
        END { if (inserted==0) exit 1 }
    ' "${WORKDIR}/uniLoader/board/Makefile" > "${WORKDIR}/uniLoader/board/Makefile.tmp" || {
        echo "ERROR: failed to insert board-gts8pwifi.o into board/Makefile"
        exit 1
    }
    mv "${WORKDIR}/uniLoader/board/Makefile.tmp" "${WORKDIR}/uniLoader/board/Makefile"
fi

mkdir -p "${WORKDIR}/uniLoader/blob"
if [ -f "${RAW_KERNEL_IMAGE}" ]; then
    cp "${RAW_KERNEL_IMAGE}" "${WORKDIR}/uniLoader/blob/Image"
else
    KERNEL_FILE_TYPE="$(file -b "${KERNEL_IMAGE}" 2>/dev/null || true)"
    case "${KERNEL_FILE_TYPE}" in
        *"gzip compressed"*)
            gunzip -c "${KERNEL_IMAGE}" > "${WORKDIR}/uniLoader/blob/Image"
            ;;
        *"XZ compressed"*)
            xzcat "${KERNEL_IMAGE}" > "${WORKDIR}/uniLoader/blob/Image"
            ;;
        *"Zstandard compressed"*)
            zstd -dc "${KERNEL_IMAGE}" > "${WORKDIR}/uniLoader/blob/Image"
            ;;
        *"PE32+"*"executable"*)
            OBJCOPY_BIN="${CROSS_COMPILE_PREFIX}objcopy"
            if ! command -v "${OBJCOPY_BIN}" >/dev/null 2>&1; then
                echo "ERROR: missing ${OBJCOPY_BIN} to extract EFI-wrapped kernel payload"
                exit 1
            fi
            "${OBJCOPY_BIN}" --dump-section .linux="${WORKDIR}/uniLoader/blob/Image" "${KERNEL_IMAGE}"
            if [ ! -s "${WORKDIR}/uniLoader/blob/Image" ]; then
                echo "ERROR: failed to extract EFI-wrapped kernel payload from ${KERNEL_IMAGE}"
                exit 1
            fi
            ;;
        *"Linux kernel ARM64 boot executable Image"*)
            cp "${KERNEL_IMAGE}" "${WORKDIR}/uniLoader/blob/Image"
            ;;
        *)
            echo "ERROR: unsupported kernel payload format for ${KERNEL_IMAGE}: ${KERNEL_FILE_TYPE}"
            exit 1
            ;;
    esac
fi
if [ ! -s "${WORKDIR}/uniLoader/blob/Image" ]; then
    echo "ERROR: generated kernel payload is empty or unreadable"
    exit 1
fi
cp "${DTB_IMAGE}" "${WORKDIR}/uniLoader/blob/dtb"
cp "${RAMDISK_IMAGE}" "${WORKDIR}/uniLoader/blob/ramdisk"

JOBS="$(nproc)"
make -C "${WORKDIR}/uniLoader" ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE_PREFIX}" gts8pwifi_defconfig
make -C "${WORKDIR}/uniLoader" -j"${JOBS}" ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE_PREFIX}"

install -Dm755 "${WORKDIR}/uniLoader/uniLoader" /usr/sbin/uniLoader
ln -sf /usr/sbin/uniLoader /usr/sbin/uniloader
