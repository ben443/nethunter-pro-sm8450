#!/bin/sh

set -eu

SCRIPT_NAME="$(basename "$0")"
MODE="auto"
CONFIRM_REPARTITION="no"
PARTED_BIN="${PARTED_BIN:-/external_sd/parted}"
DEVICE_DISK="${DEVICE_DISK:-}"
BOOT_PART="${BOOT_PART:-}"
FEDORA_P1_PART="${FEDORA_P1_PART:-}"
FEDORA_P2_PART="${FEDORA_P2_PART:-}"
FEDORA_ROOT_PART="${FEDORA_ROOT_PART:-}"

BOOT_IMG=""
FEDORA_P1_IMG=""
FEDORA_P2_IMG=""
FEDORA_ROOT_IMG=""

usage() {
    cat <<EOF
Usage:
  ${SCRIPT_NAME} [--partition-only|--flash-only] [options]

Options:
  --boot-img <path>         boot partition image (Project Mu / uniLoader boot.img)
  --fedora-p1-img <path>    Fedora ESP image (fat32, fedora_p1)
  --fedora-p2-img <path>    Fedora boot image (ext4, fedora_p2)
  --rootfs-img <path>       Fedora rootfs ext4 image (fedora_p3)
  --parted-bin <path>       Path to parted binary in TWRP (default: /external_sd/parted)
  --disk <path>             Block disk path (auto-detected from userdata, fallback /dev/block/sda)
  --boot-part <path>        Boot partition block path (auto-detected from by-name/boot)
  --partition-only          Only repartition userdata into fedora_p1/p2/p3 + userdata
  --flash-only              Only flash partitions (requires existing fedora partitions)
  --confirm-repartition yes Required to run destructive repartition step
  -h, --help                Show this help

Environment overrides:
  PARTED_BIN, DEVICE_DISK, BOOT_PART, FEDORA_P1_PART, FEDORA_P2_PART, FEDORA_ROOT_PART
EOF
}

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*"; }
err() { echo "ERROR: $*" >&2; exit 1; }

require_file() {
    [ -f "$1" ] || err "missing file: $1"
}

require_block() {
    [ -b "$1" ] || err "missing block device: $1"
}

partition_path() {
    disk="$1"
    number="$2"
    case "${disk}" in
        *[0-9]) printf '%s%s\n' "${disk}p" "${number}" ;;
        *) printf '%s%s\n' "${disk}" "${number}" ;;
    esac
}

find_by_name() {
    part_name="$1"
    for base in /dev/block/by-name /dev/block/platform/*/by-name; do
        [ -e "${base}/${part_name}" ] || continue
        resolved="$(readlink -f "${base}/${part_name}" 2>/dev/null || true)"
        if [ -n "${resolved}" ] && [ -e "${resolved}" ]; then
            printf '%s\n' "${resolved}"
            return 0
        fi
    done
    return 1
}

disk_from_partition() {
    part="$1"
    case "${part}" in
        *mmcblk*p[0-9]*|*nvme*n*p[0-9]*)
            printf '%s\n' "${part%p[0-9]*}"
            ;;
        */sd[a-z][0-9]*)
            printf '%s\n' "${part%[0-9]*}"
            ;;
        *)
            return 1
            ;;
    esac
}

fedora_layout_present() {
    table="$("${PARTED_BIN}" -ms "${DEVICE_DISK}" print)"
    echo "${table}" | grep -q ':fedora_p1:' &&
    echo "${table}" | grep -q ':fedora_p2:' &&
    echo "${table}" | grep -q ':fedora_p3:'
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --boot-img) BOOT_IMG="$2"; shift 2 ;;
            --fedora-p1-img) FEDORA_P1_IMG="$2"; shift 2 ;;
            --fedora-p2-img) FEDORA_P2_IMG="$2"; shift 2 ;;
            --rootfs-img) FEDORA_ROOT_IMG="$2"; shift 2 ;;
            --parted-bin) PARTED_BIN="$2"; shift 2 ;;
            --disk) DEVICE_DISK="$2"; shift 2 ;;
            --boot-part) BOOT_PART="$2"; shift 2 ;;
            --partition-only) MODE="partition-only"; shift ;;
            --flash-only) MODE="flash-only"; shift ;;
            --confirm-repartition) CONFIRM_REPARTITION="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) err "unknown argument: $1" ;;
        esac
    done
}

resolve_paths() {
    require_file "${PARTED_BIN}"
    [ -x "${PARTED_BIN}" ] || err "parted binary is not executable: ${PARTED_BIN}"

    if [ -z "${BOOT_PART}" ]; then
        BOOT_PART="$(find_by_name boot || true)"
    fi
    [ -n "${BOOT_PART}" ] || BOOT_PART="/dev/block/sda25"
    require_block "${BOOT_PART}"

    userdata_part="$(find_by_name userdata || true)"
    if [ -n "${userdata_part}" ]; then
        autodisk="$(disk_from_partition "${userdata_part}" || true)"
    else
        autodisk=""
    fi
    if [ -z "${DEVICE_DISK}" ]; then
        DEVICE_DISK="${autodisk:-/dev/block/sda}"
    fi
    require_block "${DEVICE_DISK}"

    userdata_num="$("${PARTED_BIN}" -ms "${DEVICE_DISK}" print | awk -F: '$6=="userdata"{print $1; exit}')"
    [ -n "${userdata_num}" ] || err "unable to locate userdata partition number on ${DEVICE_DISK}"
    case "${userdata_num}" in
        ''|*[!0-9]*) err "invalid userdata partition number: ${userdata_num}" ;;
    esac

    p1_num="${userdata_num}"
    p2_num=$((userdata_num + 1))
    p3_num=$((userdata_num + 2))

    [ -n "${FEDORA_P1_PART}" ] || FEDORA_P1_PART="$(partition_path "${DEVICE_DISK}" "${p1_num}")"
    [ -n "${FEDORA_P2_PART}" ] || FEDORA_P2_PART="$(partition_path "${DEVICE_DISK}" "${p2_num}")"
    [ -n "${FEDORA_ROOT_PART}" ] || FEDORA_ROOT_PART="$(partition_path "${DEVICE_DISK}" "${p3_num}")"
}

run_repartition() {
    [ "${CONFIRM_REPARTITION}" = "yes" ] || err "--confirm-repartition yes is required for partition changes"
    if fedora_layout_present; then
        warn "fedora_p1/p2/p3 already detected on ${DEVICE_DISK}; skipping repartition"
        return 0
    fi

    userdata_num="$("${PARTED_BIN}" -ms "${DEVICE_DISK}" print | awk -F: '$6=="userdata"{print $1; exit}')"
    [ -n "${userdata_num}" ] || err "unable to find userdata before repartition"
    p1_num="${userdata_num}"

    info "Repartitioning ${DEVICE_DISK} (destructive): replacing userdata with fedora_p1/fedora_p2/fedora_p3/userdata"
    "${PARTED_BIN}" -s "${DEVICE_DISK}" rm "${userdata_num}"
    "${PARTED_BIN}" -s "${DEVICE_DISK}" mkpart fedora_p1 fat32 14.0GB 16.5GB
    "${PARTED_BIN}" -s "${DEVICE_DISK}" mkpart fedora_p2 ext4 16.5GB 18.0GB
    "${PARTED_BIN}" -s "${DEVICE_DISK}" mkpart fedora_p3 ext4 18.0GB 40.0GB
    "${PARTED_BIN}" -s "${DEVICE_DISK}" mkpart userdata ext4 40.0GB 127.0GB
    "${PARTED_BIN}" -s "${DEVICE_DISK}" set "${p1_num}" esp on
    sync

    info "Partitioning complete."
    info "Reboot back into recovery now, then run this script again with --flash-only."
}

run_flash() {
    require_file "${BOOT_IMG}"
    require_file "${FEDORA_P1_IMG}"
    require_file "${FEDORA_P2_IMG}"
    require_file "${FEDORA_ROOT_IMG}"
    require_block "${FEDORA_P1_PART}"
    require_block "${FEDORA_P2_PART}"
    require_block "${FEDORA_ROOT_PART}"

    info "Flashing boot image to ${BOOT_PART}"
    dd if="${BOOT_IMG}" of="${BOOT_PART}" bs=4M conv=fsync

    info "Flashing Fedora ESP to ${FEDORA_P1_PART}"
    dd if="${FEDORA_P1_IMG}" of="${FEDORA_P1_PART}" bs=4M conv=fsync

    info "Flashing Fedora boot partition to ${FEDORA_P2_PART}"
    dd if="${FEDORA_P2_IMG}" of="${FEDORA_P2_PART}" bs=4M conv=fsync

    info "Flashing Fedora rootfs to ${FEDORA_ROOT_PART}"
    dd if="${FEDORA_ROOT_IMG}" of="${FEDORA_ROOT_PART}" bs=4M conv=fsync

    sync
    info "Flashing complete. Reboot system from TWRP when ready."
}

parse_args "$@"
resolve_paths

info "Detected disk: ${DEVICE_DISK}"
info "Detected boot partition: ${BOOT_PART}"
info "Fedora partitions: ${FEDORA_P1_PART}, ${FEDORA_P2_PART}, ${FEDORA_ROOT_PART}"

case "${MODE}" in
    partition-only)
        run_repartition
        ;;
    flash-only)
        run_flash
        ;;
    auto)
        if fedora_layout_present; then
            run_flash
        else
            run_repartition
        fi
        ;;
    *)
        err "invalid mode: ${MODE}"
        ;;
esac
