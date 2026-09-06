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

WORKDIR="$(mktemp -d /tmp/uniloader-sm8450.XXXXXX)"
cleanup() {
    rm -rf "${WORKDIR}"
}
trap cleanup EXIT INT TERM

if [ -e /vmlinuz ]; then
    KERNEL_IMAGE="$(readlink -f /vmlinuz)"
else
    KERNEL_IMAGE="$(find /boot -maxdepth 1 -type f -name 'vmlinuz-*' | sort | tail -1)"
fi
if [ -z "${KERNEL_IMAGE}" ] || [ ! -f "${KERNEL_IMAGE}" ]; then
    echo "ERROR: unable to detect installed kernel image"
    exit 1
fi
KERNEL_VERSION="${KERNEL_IMAGE##*/vmlinuz-}"
RAMDISK_IMAGE="/boot/initrd.img-${KERNEL_VERSION}"
DTB_IMAGE="/usr/lib/linux-image-${KERNEL_VERSION}/qcom/sm8450-galaxy-tab-s8-5g.dtb"

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

echo "${BOARD_SHA256}  ${WORKDIR}/uniLoader/${BOARD_FILE}" | sha256sum -c -
echo "${DEFCONFIG_SHA256}  ${WORKDIR}/uniLoader/${DEFCONFIG_FILE}" | sha256sum -c -

grep -q "SAMSUNG_GTS8PWIFI" "${WORKDIR}/uniLoader/board/Kconfig" || cat >> "${WORKDIR}/uniLoader/board/Kconfig" <<'EOF'
config SAMSUNG_GTS8PWIFI
	bool "Samsung Galaxy Tab S8 WiFi board support"
	help
	  Enable support for Samsung Galaxy Tab S8 WiFi (gts8pwifi) in uniLoader.
EOF

grep -q "board-gts8pwifi.o" "${WORKDIR}/uniLoader/board/Makefile" || \
    echo 'lib-$(CONFIG_SAMSUNG_GTS8PWIFI) += samsung/board-gts8pwifi.o' >> "${WORKDIR}/uniLoader/board/Makefile"

mkdir -p "${WORKDIR}/uniLoader/blob"
if gzip -t "${KERNEL_IMAGE}" >/dev/null 2>&1; then
    gunzip -c "${KERNEL_IMAGE}" > "${WORKDIR}/uniLoader/blob/Image"
else
    cp "${KERNEL_IMAGE}" "${WORKDIR}/uniLoader/blob/Image"
fi
cp "${DTB_IMAGE}" "${WORKDIR}/uniLoader/blob/dtb"
cp "${RAMDISK_IMAGE}" "${WORKDIR}/uniLoader/blob/ramdisk"

make -C "${WORKDIR}/uniLoader" ARCH=aarch64 gts8pwifi_defconfig
make -C "${WORKDIR}/uniLoader" ARCH=aarch64

install -Dm755 "${WORKDIR}/uniLoader/uniLoader" /usr/sbin/uniLoader
ln -sf /usr/sbin/uniLoader /usr/sbin/uniloader
