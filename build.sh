#!/usr/bin/env bash
#
# $ ./$0
# $ ./$0 --device pinephone
# $ ./$0 -b kali-dev -d pinetab -D plasma-mobile
# $ ./$0 -b kali-last-snapshot -d rootfs
# $ ./$0 -r ./output/rootfs-last_snapshot-amd64.tar.xz -d librem5
# $ ./$0 -d librem5 -- --memory 4G --scratchsize 16G
# $ ./$0 -d amd64 -- --debug-shell
# $ BUILD_MIRROR=http://kali.download/kali ./$0
# $ http_proxy= ./$0
# $ DEBUG=1 ./$0
#
# REF:
#   - https://gitlab.com/kalilinux/build-scripts/kali-vm
#   - https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-pro
#   - https://salsa.debian.org/Mobian-team/mobian-recipes
#

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Environment
#

set -euEo pipefail
trap 'echo "ERROR: ${BASH_SOURCE[0]}:${LINENO} (status ${?})" >&2' ERR
trap 'cleanup_perms' EXIT
trap 'cleanup_ps; cleanup_fs' INT TERM

cd "$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Variables
#

## Defaults
DEFAULT_USERPASS="kali:1234"   # DEFAULT_USERPASS needs to come before DEFAULT_CRYPT_PASS
DEFAULT_ARCH="amd64"
DEFAULT_BRANCH="kali-rolling"
DEFAULT_BUILD_MIRROR="http://http.kali.org/kali"
DEFAULT_CRYPT_PASS="${DEFAULT_USERPASS#*:}"
DEFAULT_CRYPT_ROOT="false"
DEFAULT_DESKTOP="phosh"
DEFAULT_DEVICE="amd64"
DEFAULT_FILESYSTEM="ext4"
DEFAULT_KALI_HOSTNAME="kali"
DEFAULT_MEMORY="2G"   # 2G is working fine, until doing LUKS (then 6G)
DEFAULT_MINIRAMFS="false"
DEFAULT_OUT_DIR="${PWD}/output"
DEFAULT_PACKAGES=
DEFAULT_PARTITION_TABLE="gpt"
DEFAULT_SCRATCHSIZE="8G"
DEFAULT_SIZE="8"
DEFAULT_SSH="false"
DEFAULT_ZIP="false"
DEFAULT_ZRAM="false"

ARCH="${ARCH:-}"
ARGS=()
BRANCH="${BRANCH:-$DEFAULT_BRANCH}"
BUILD_MIRROR="${BUILD_MIRROR:-$DEFAULT_BUILD_MIRROR}"
CRYPT_PASS="${CRYPT_PASS:-$DEFAULT_CRYPT_PASS}"
CRYPT_ROOT="${CRYPT_ROOT:-$DEFAULT_CRYPT_ROOT}"
DEBUG="${DEBUG:-}"
DESKTOP="${DESKTOP:-$DEFAULT_DESKTOP}"
DEVICE="${DEVICE:-$DEFAULT_DEVICE}"
FAMILY=
FILESYSTEM="${FILESYSTEM:-$DEFAULT_FILESYSTEM}"
HOST_ARCH=$( dpkg --print-architecture )    # Alt: $( uname -m )
KALI_HOSTNAME="${KALI_HOSTNAME:-$DEFAULT_KALI_HOSTNAME}"
MEMORY="${MEMORY:-$DEFAULT_MEMORY}"
MINIRAMFS="${MINIRAMFS:-$DEFAULT_MINIRAMFS}"
MOBIAN_SUITE="forky"   # REF: http://repo.mobian.org/dists/${MOBIAN_SUITE}
OUT_DIR="${OUT_DIR:-$DEFAULT_OUT_DIR}"
OUT_FILENAME=
PACKAGES="${PACKAGES:-$DEFAULT_PACKAGES}"
PARTITION_TABLE="${PARTITION_TABLE:-$DEFAULT_PARTITION_TABLE}"
PASSWORD=
PLATFORM="image"
PROJECT="NetHunter Pro"
PROMPT="$"
ROOTFS=
SCRATCHSIZE="${SCRATCHSIZE:-$DEFAULT_SCRATCHSIZE}"
SIZE="${SIZE:-$DEFAULT_SIZE}"
SSH="${SSH:-$DEFAULT_SSH}"
USERNAME=
USERPASS="${USERPASS:-$DEFAULT_USERPASS}"
VERSION=   # default_version()
ZIP="${ZIP:-$DEFAULT_ZIP}"
ZRAM="${ZRAM:-$DEFAULT_ZRAM}"

## Apt caching proxies to auto-detect
KNOWN_CACHING_PROXIES="\
3142 apt-cacher-ng
8000 squid-deb-proxy"
DETECTED_CACHING_PROXY=

## Supported values
SUPPORTED_ARCHITECTURES="amd64 arm64"
SUPPORTED_BRANCHES="kali-rolling kali-dev kali-last-snapshot"
SUPPORTED_DESKTOPS="phosh plasma-mobile"
SUPPORTED_DEVICES="amd64 pinephone pinetab sunxi pinephonepro pinetab2 rockchip librem5 sdm845 sdm670 sm6350 sc7280 sm7150 rootfs"
SUPPORTED_FILESYSTEMS="ext4 btrfs f2fs"
SUPPORTED_PARTITION_TABLES="gpt mbr"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Functions
#

## display_help - print usage info and exit
display_help() {
  cat <<EOF
Usage: $( basename "${0}" ) [OPTIONS] [-- <debos options>]

Build a Kali ${PROJECT} ${PLATFORM}.

Build options:
  -a, --arch ARCH              Build a ${PLATFORM} for this architecture (default: $( b "${DEFAULT_ARCH}" ))
                               Supported: ${SUPPORTED_ARCHITECTURES}
  -b, --branch BRANCH          Kali branch used to build the ${PLATFORM} (default: $( b "${DEFAULT_BRANCH}" ))
                               Supported: ${SUPPORTED_BRANCHES}
  -d, --device DEVICE          Variant of ${PLATFORM} to build, see below for details (default: $( b "${DEFAULT_DEVICE}" ))
                               Supported: ${SUPPORTED_DEVICES}
  -m, --mirror URL             Mirror used to build the ${PLATFORM} (default: $( b "${DEFAULT_BUILD_MIRROR}" ))
  -r, --rootfs ROOTFS          Rootfs to use to build the ${PLATFORM} (default: $( b none ))
  -s, --size SIZE              Size of the disk image in GB (default: $( b "${DEFAULT_SIZE}" ))
  -x, --version VERSION        What to name the ${PLATFORM} release as (default: $( b "$( default_version )" ))
  -z, --zip                    Zip ${PLATFORM} and metadata files after the build
  -h, --help                   Show this help and exit

Customization options:
  -D, --desktop DESKTOP        Desktop environment installed in the ${PLATFORM} (default: $( b "${DEFAULT_DESKTOP}" ))
                               Supported: ${SUPPORTED_DESKTOPS}
  -f, --filesystem FORMAT      Filesystem to use (default: $( b "${DEFAULT_FILESYSTEM}" ))
                               Supported: ${SUPPORTED_FILESYSTEMS}
  -c, --crypt-root             Enables LUKS2 full-disk encryption on the root partition
  -R, --crypt-password PASS    Passphrase used for crypt-root's LUKS encryption (default: $( b "${DEFAULT_CRYPT_PASS}" ))
  -p, --partition-table VALUE  Partition table to use (default: $( b "${DEFAULT_PARTITION_TABLE}" ))
                               Supported: ${SUPPORTED_PARTITION_TABLES}
  -M, --miniramfs              Generates a stripped-down initramfs for devices which have a size restriction
  -H, --hostname HOSTNAME      Set system host name (default: $( b "${DEFAULT_KALI_HOSTNAME}" ))
  -P, --packages PKGS          Install extra packages (comma/space separated list)
  -S, --ssh                    Configure SSH (default: $( b "${DEFAULT_SSH}" ))
  -U, --userpass USERPASS      Username and password, separated by a colon (default: $( b "${DEFAULT_USERPASS}" ))
  -Z, --zram                   Mounts /tmp and /var/tmp on compressed RAM-backed zram devices instead of flash storage

Apt caching proxy:
  Auto-detected: localhost:3142 (apt-cacher-ng), localhost:8000 (squid-deb-proxy).
  If detected and http_proxy is not set, http_proxy is exported automatically.

Supported environment variables:
  http_proxy  HTTP proxy URL, see README.md for details
  DEBUG       Print extra debug output
  Any --flag value can be pre-set via the env var of the same name (e.g. BUILD_MIRROR, ARCH)

Most useful debos options:
  --artifactdir DIR   Set artifact directory (default: $( b "${DEFAULT_OUT_DIR}" ))
  --memory SIZE       Memory to build VM, e.g. 4G or 4096M (default: $( b "${DEFAULT_MEMORY}" ))
  --scratchsize SIZE  Scratch disk to build VM, e.g. 45G (default: $( b "${DEFAULT_SCRATCHSIZE}" ))
  --verbose           Make output more detailed
  --debug-shell       Get a shell on the VM
  --help, -h          See all debos options

Examples:
  $( basename "${0}" )
  $( basename "${0}" ) --device pinephone
  $( basename "${0}" ) -b kali-dev -d pinetab -D plasma-mobile
  $( basename "${0}" ) -b kali-last-snapshot -d rootfs
  $( basename "${0}" ) -r ./output/rootfs-last_snapshot-amd64.tar.xz -d librem5
  $( basename "${0}" ) -d librem5 -- --memory 4G --scratchsize 16G
  $( basename "${0}" ) -d amd64 -- --debug-shell
EOF
  exit 0
}

## b <text> - bold-wrap text if writing to a TTY, else pass through
if [ -t 1 ] && [ -t 2 ]; then
  b() { tput bold; echo -n "${*}"; tput sgr0; }
else
  b() { echo -n "${*}"; }
fi

## vrun <cmd> [args] - log timestamped command, then execute it
##   Using pipes with vrun() doesn't work too well
vrun()  { { echo -n "[$( date -u +'%H:%M:%S' )] ${PROJECT// /}:~${PROMPT} "; b "${*}"; echo; } 1>&2; "${@}" & child_pid=${!}; wait "${child_pid}"; }

## point <text> - print a bullet-prefixed line
point() { echo " * ${*}"; }
## warn <msg> - print WARNING-prefixed message to stderr
warn()  { echo "WARNING: ${*}" 1>&2; }
## fail <msg> - print ERROR-prefixed message to stderr and exit 1
fail()  { echo "ERROR: ${*}" 1>&2; exit 1; }
## debug <msg> - print DEBUG-prefixed message to stderr
debug()  { [ -n "${DEBUG}" ] && echo "DEBUG: ${*}" 1>&2; return 0; }

## require_arg <flag> <value> - fail if value is empty
require_arg() {
  [ -n "${2:-}" ] || fail "Option ${1} requires an argument";
}

## fail_invalid <flag> <value> [extra...] - fail with "Invalid value 'X' for option Y (...)"
fail_invalid() {
  local _msg="Invalid value '${2}' for option ${1}"

  shift 2
  [ "${#}" -gt 0 ] \
    && _msg="${_msg} (${*})"
  fail "${_msg}"
}

## in_list <word> <list> - return 0 if word matches any item, else 1
in_list() {
  case " ${2} " in
    *" ${1} "*) return 0 ;;
    *) return 1 ;;
  esac
}

## kali_message <title> - wrap piped lines in a kali-themed box with bold title
kali_message() {
  local _line=

  echo   "┏━━($( b "$*" ))"
  while IFS= read -r _line; do
    echo "┃ ${_line}"
  done
  echo   "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

## default_version - return BRANCH minus "kali-" prefix (e.g. "last_snapshot" from "kali-last-snapshot")
default_version() {
  local _version="${BRANCH#kali-}"
  #[ -n "${CI_COMMIT_SHORT_SHA:-}" ] \
  #  && _version="${_version}_${CI_COMMIT_SHORT_SHA}"
  echo "${_version//-/_}";
}

## is_cross_build - return 0 if HOST_ARCH and ARCH require cross-architecture builds, else 1
is_cross_build() {
  [ "${HOST_ARCH}" != "${ARCH}" ]
}

## cleanup_ps - kill vrun() processes
cleanup_ps() {
  if [ -n "${child_pid:-}" ]; then
    pkill -TERM -P "${child_pid}" 2>/dev/null || true
    kill -TERM "${child_pid}"     2>/dev/null || true
  fi
}

## cleanup_perms - chown ${OUT_DIR} back to non-root who ran ./build*.sh (matters more if ran with root)
cleanup_perms() {
  local _uid="${HOST_UID:-${SUDO_UID:-}}"
  local _gid="${HOST_GID:-${SUDO_GID:-${_uid}}}"

  [ -n "${_uid}" ]      || return 0
  [ -d "${OUT_DIR:-}" ] || return 0
  chown -R "${_uid}:${_gid}" "${OUT_DIR}/" || true   # Skipping $ chown -v [...]     ...too noisy
}

## detect_container - return engine name if running in a container, else empty
detect_container() {
  local _engine=

  if [ -e /.dockerenv ]; then
    echo "docker"
    return
  fi

  if [ -e /run/.containerenv ]; then
    _engine=$( grep -oE '^engine="?[^"]*"?' /run/.containerenv 2>/dev/null \
                  | sed -E 's/^engine="?([^"]*)"?/\1/' \
                  | head -1 \
                || true )
    echo "${_engine:-podman}"
    return
  fi

  if [ -r /proc/1/environ ]; then
    _engine=$( tr '\0' '\n' < /proc/1/environ 2>/dev/null \
                  | sed -n 's/^container=//p' \
                  | head -1 )
    if [ -n "${_engine}" ]; then
      echo "${_engine}"
      return
    fi
  fi

  if [ -r /proc/1/cgroup ]; then
    _engine=$( grep -oE '(docker|containerd|podman|lxc|kubepods)' /proc/1/cgroup 2>/dev/null \
                  | head -1 \
                || true )
    if [ -n "${_engine}" ]; then
      echo "${_engine}"
      return
    fi
  fi

  return 0
}

## detect_apt_caching_proxy - return "PORT NAME" of a local apt-caching proxy, or empty
detect_apt_caching_proxy() {
  local _port=
  local _proxy=

  ## Use APT's configured proxy if set
  if [ -x /usr/bin/apt-config ]; then
    _proxy=$( apt-config dump --format '%v%n' Acquire::http::Proxy )
    _proxy="${_proxy%/}"
    [[ "${_proxy}" == *:*:* ]] && _port="${_proxy##*:}"
    if [[ "${_port}" =~ ^[0-9]+$ ]]; then
      echo "${_port} apt-config"
      return
    fi
  fi

  ## Attempt to detect well-known http caching proxies on localhost
  ##   See bash(1) section "REDIRECTION". This is not bullet-proof.
  while read -r _port _proxy; do
    ( : </dev/tcp/localhost/"${_port}" ) 2>/dev/null \
      || continue
    echo "${_port} ${_proxy}"
    return
  done <<< "${KNOWN_CACHING_PROXIES}"
}

## create_image <debos_args> - main magic
create_image() {
  local _cmd_args=(
    "${@}"
    -t suite:"${MOBIAN_SUITE}"        # suite needs to come before debian_suite
    -t nonfree:true
    -t contrib:true
    -t architecture:"${ARCH}"
    -t family:"${FAMILY}"
    -t device:"${DEVICE}"
    -t partitiontable:"${PARTITION_TABLE}"
    -t filesystem:"${FILESYSTEM}"
    -t image:"${OUT_FILENAME}"
    -t rootfs:"${ROOTFS}"
    -t debian_suite:"${BRANCH}"
    -t username:"${USERNAME}"
    -t password:"${PASSWORD}"
    -t environment:"${DESKTOP}"
    -t hostname:"${KALI_HOSTNAME}"
    -t mirror:"${BUILD_MIRROR}"
    -t packages:"${PACKAGES}"
  )
  [ -n "${DEBUG}" ] && _cmd_args+=(--verbose)

  ## Image:
  ##   - ./rootfs.yaml       : Builds the base OS filesystem via debootstrap
  ##   - ./image.yaml        : Takes that rootfs and turns it into an actual bootable device image
  ## Installer (isn't supported with Kali NetHunter Pro currently):
  ##   - ./rootfs.yaml       : Builds the base OS filesystem via debootstrap
  ##   - ./rootfs-device.yaml: Takes the output from ./rootfs.yaml, re-packages it with device-specific additions
  ##   - ./installfs.yaml    : Creates another rootfs for installer via debootstrap
  ##   - ./installer.yaml    : Build "Installer": Unpacks ./installfs.yaml, overlay ./rootfs-device.yaml
  if [ -n "${ROOTFS}" ] && [ -f "${OUT_DIR}/${ROOTFS}" ]; then
    point "Found rootfs to re-use: $( b "${OUT_DIR}/${ROOTFS}" )"
  else
    #echo "Building rootfs" | kali_message "Kali ${PROJECT} ${PLATFORM}"
    vrun debos "${_cmd_args[@]}" rootfs.yaml
  fi

  if [ "${DEVICE}" != "rootfs" ]; then
    #echo "Building image" | kali_message "Kali ${PROJECT} ${PLATFORM}"
    vrun debos "${_cmd_args[@]}" image.yaml
  fi
}

## check_os - check the host
check_os() {
  if grep -q -e "^ID=debian" -e "^ID_LIKE=debian" /usr/lib/os-release; then
    # shellcheck disable=SC1091
    debug "OS: $( . /usr/lib/os-release && echo "${NAME}" "${VERSION}" )"
  elif [ -e /etc/debian_version ]; then
    debug "OS: $( cat /etc/debian_version )"
  else
    fail "Non Debian-based OS"
  fi
}

## valid_hostname <name> - check name is letters/digits/hyphens, no leading/trailing hyphen
valid_hostname() {
  # See hostname(7) and netcfg/netcfg-common.c from debian-installer
  local _name="${1}"

  [[ "${_name}" =~ ^[A-Za-z0-9-]+$ ]] \
    || return 1

  ## Alt: [[ "${_name}" =~ ^-|-$ ]]
  [[ "${_name}" == -* || "${_name}" == *- ]] \
    && return 1

  return 0
}

## cleanup_fs - rm temp files
cleanup_fs() {
  rm -f "${PWD}"/fake-scratch.img.*
}

## fail_mismatch <opt1> <opt2> [extra...] - fail with "Option mismatch, X cannot be used together with Y [...]"
fail_mismatch() {
  local _msg="Option mismatch, ${1} cannot be used together with ${2}"

  shift 2
  [ "${#}" -gt 0 ] \
    && _msg="${_msg} (${*})"
  fail "${_msg}"
}

## parse_size <input> [default_unit] - normalize a size to "<digits><unit>"
parse_size() {
  local _input="${1}"
  local _default_unit="${2:-G}"

  if [[ "${_input}" =~ ^([0-9]+)([KMGTkmgt][Bb]?)?$ ]]; then
    local _digits="${BASH_REMATCH[1]}"
    local _unit="${BASH_REMATCH[2]:-$_default_unit}"

    echo "${_digits}${_unit^^}"
  else
    return 1
  fi
}

## valid_username <name> - check username is valid
valid_username() {
  local _name="${1}"
  [[ "${_name}" =~ ^[a-z_][a-z0-9_-]*$ ]]
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Parse & validate arguments
#

## What's left on the command-line after `--` is forwarded verbatim to debos
_debos_args=()
while [ "${#}" -gt 0 ]; do
  ## "Fix" any user-input
  case "${1}" in
    ## Boolean flags, behave if the user just toggled
    ##  --help is a little overkill...
    --crypt-root=*|--miniramfs=*|--help=*|--ssh=*|--zip=*|--zram=*)
        set -- "${1%%=*}" "${@:2}" ;;
    ## Pre-normalize, drop "=".
    ##   E.g.: "--foo=bar" -> "--foo bar"
    --*=*)
        set -- "${1%%=*}" "${1#*=}" "${@:2}" ;;
  esac

  case "${1}" in
    -a|--arch)             require_arg "${1}" "${2:-}"; ARCH="${2}";                 shift 2 ;;
    -b|--branch)           require_arg "${1}" "${2:-}"; BRANCH="${2}";               shift 2 ;;
    -c|--crypt-root)       CRYPT_ROOT=true;                                          shift ;;
    -D|--desktop)          require_arg "${1}" "${2:-}"; DESKTOP="${2}";              shift 2 ;;
    -d|--device)           require_arg "${1}" "${2:-}"; DEVICE="${2}";               shift 2 ;;
    -f|--filesystem)       require_arg "${1}" "${2:-}"; FILESYSTEM="${2}";           shift 2 ;;
    -h|--help)             display_help ;;
    -H|--hostname)         require_arg "${1}" "${2:-}"; KALI_HOSTNAME="${2}";        shift 2 ;;
    -M|--miniramfs)        MINIRAMFS=true;                                           shift ;;
    -m|--mirror)           require_arg "${1}" "${2:-}"; BUILD_MIRROR="${2}";         shift 2 ;;
    -P|--packages)         require_arg "${1}" "${2:-}"; PACKAGES="${PACKAGES} ${2}"; shift 2 ;;
    -p|--partition-table)  require_arg "${1}" "${2:-}"; PARTITION_TABLE="${2}";      shift 2 ;;
    -R|--crypt-password)   require_arg "${1}" "${2:-}"; CRYPT_PASS="${2}";           shift 2 ;;
    -r|--rootfs)           require_arg "${1}" "${2:-}"; ROOTFS="${2}";               shift 2 ;;
    -s|--size)             require_arg "${1}" "${2:-}"; SIZE="${2}";                 shift 2 ;;
    -S|--ssh)              SSH=true;                                                 shift ;;
    -U|--userpass)         require_arg "${1}" "${2:-}"; USERPASS="${2}";             shift 2 ;;
    -x|--version)          require_arg "${1}" "${2:-}"; VERSION="${2}";              shift 2 ;;
    -z|--zip)              ZIP=true;                                                 shift ;;
    -Z|--zram)             ZRAM=true;                                                shift ;;
    --)                    shift; _debos_args=("${@}"); break ;;
    *)                     fail "Unknown option: ${1}" ;;
  esac
done
set -- "${_debos_args[@]}"
unset _debos_args

## Link/sync ${OUT_DIR} with debos's --artifactdir
## Method #1 - issue is, doesn't like spaces
#ARTIFACTDIR_ARG=$( echo "${@}" | grep -o -- "--artifactdir[= ][^ ]\+" || : )
#if [ -n "${ARTIFACTDIR_ARG}" ]; then
#  OUT_DIR="${ARTIFACTDIR_ARG##*[= ]}"   # Alt: OUT_DIR="$( echo "${ARTIFACTDIR_ARG}" | sed "s/^.*[= ]//" )"
#  point "Using --artifactdir from debos args: $( b "${OUT_DIR}" )"
#else
#  set -- "${@}" --artifactdir="${OUT_DIR}"
#fi
## Method #2
_args=( "${@}" )
_found=
for (( _i=0; _i < ${#_args[@]}; _i++ )); do
  case "${_args[_i]}" in
    --artifactdir=*) _found="${_args[_i]#*=}" ;;
    --artifactdir)   _found="${_args[_i+1]:-}" ;;
  esac
done
if [ -n "${_found}" ]; then
  OUT_DIR="${_found}"
  point "Using --artifactdir from debos args: $( b "${OUT_DIR}" )"
else
  set -- "${@}" --artifactdir="${OUT_DIR}"
fi
unset _args _found _i

## Remaining command-line args go to debos
## We will set some options for debos, unless it was already set by the caller
## There is less validation done on these inputs

MEMORY="$( parse_size "${MEMORY}" G )" \
  || fail_invalid --memory "${MEMORY}" "must be a number, optionally followed by K/M/G/T (+ optional B)"

SCRATCHSIZE="$( parse_size "${SCRATCHSIZE}" G )" \
  || fail_invalid --scratchsize "${SCRATCHSIZE}" "must be a number, optionally followed by K/M/G/T (+ optional B)"

## Inject debos defaults for: --memory and --scratchsize (if the user didn't)
_args=( "${@}" )
_have_memory=0
_have_scratch=0
for (( _i=0; _i < ${#_args[@]}; _i++ )); do
  case "${_args[_i]}" in
    -m=*|--memory=*)  _have_memory=1;  MEMORY="${_args[_i]#*=}" ;;
    -m|--memory)      _have_memory=1;  MEMORY="${_args[_i+1]:-${MEMORY}}" ;;
    --scratchsize=*)  _have_scratch=1; SCRATCHSIZE="${_args[_i]#*=}" ;;
    --scratchsize)    _have_scratch=1; SCRATCHSIZE="${_args[_i+1]:-${SCRATCHSIZE}}" ;;
  esac
done
# > Warning: keyslot operation could fail as it requires more than available memory.
# Warning on 2G & 4G - Happy on 6G
[ "${CRYPT_ROOT}" = "true" ] \
  && [ "${MEMORY}" = "${DEFAULT_MEMORY}" ] \
  && [ "${DEFAULT_MEMORY}" = "2G" ] \
  && MEMORY=6G
[ "${_have_memory}"  = 1 ] || set -- "${@}" --memory="${MEMORY}"
[ "${_have_scratch}" = 1 ] || set -- "${@}" --scratchsize="${SCRATCHSIZE}"
unset _args _have_memory _have_scratch _i

## Normalize ARCH
case "${ARCH,,}" in
  x64|x86_64|x86-64|amd64)
    ARCH=amd64
    ;;
  arm64|aarch64)
    ARCH=arm64
    ;;
esac

## Normalize BRANCH
case ${BRANCH,,} in
  kali-last-release|kali-last-snapshot)
    BRANCH=kali-last-snapshot
    ;;
esac

## Normalize OUT_DIR
OUT_DIR="${OUT_DIR%/}"

## Normalize BUILD_MIRROR
BUILD_MIRROR="${BUILD_MIRROR%/}/"

if [ "${DEVICE}" != "rootfs" ] && [ -n "${ARCH}" ]; then
  fail "Cannot set ARCH (${ARCH}) with ${DEVICE} (rootfs only)"
elif [ "${DEVICE}" = "rootfs" ]; then
  ARCH="${ARCH:-$DEFAULT_ARCH}"
fi

## When building from an existing rootfs, ARCH/VERSION come from the rootfs name.
## Other options (DESKTOP, BRANCH, etc.) are ignored - the rootfs already baked them in.
if [ -n "${ROOTFS}" ]; then
  ## Asked to build a rootfs AND passed in an existing rootfs
  [ "${DEVICE}" == "rootfs" ] \
    && fail_mismatch -r "'-d rootfs'"

  [ "$( realpath "$( dirname "${ROOTFS}" )" )" = "$( realpath "${OUT_DIR}" )" ] \
    || fail "rootfs must be within: ${OUT_DIR}"

  ROOTFS="$( basename "${ROOTFS}" )"
  [[ "${ROOTFS}" =~ ^rootfs-.+-[a-z0-9]+\.tar\.xz$ ]] \
    || fail_invalid -r "${ROOTFS}" "must match the pattern 'rootfs-<version>-<arch>.tar.xz'"

  ARCH="$( echo "${ROOTFS}" | sed "s/\.tar\.xz$//" | awk -F- '{print $NF}' )"       # Alt: ARCH="${ROOTFS%.tar.xz}"; ARCH="${ARCH##*-}"
  VERSION="$( echo "${ROOTFS}" | sed -E "s/^rootfs-(.*)-${ARCH}\.tar\.xz$/\1/" )"   # Alt: VERSION="${ROOTFS#rootfs-}"; VERSION="${VERSION%-${ARCH}.tar.xz}"
else
  ## Validate some options
  in_list "${BRANCH}" "${SUPPORTED_BRANCHES}" \
    || fail_invalid -b "${BRANCH}"

  in_list "${DESKTOP}" "${SUPPORTED_DESKTOPS}" \
    || fail_invalid -D "${DESKTOP}"

  in_list "${FILESYSTEM}" "${SUPPORTED_FILESYSTEMS}" \
    || fail_invalid -f "${FILESYSTEM}"

  in_list "${PARTITION_TABLE}" "${SUPPORTED_PARTITION_TABLES}" \
    || fail_invalid -p "${PARTITION_TABLE}"

  valid_hostname "${KALI_HOSTNAME}" \
    || fail_invalid -H "${KALI_HOSTNAME}" "must contain only letters, digits and hyphens"

  ## Unpack USERPASS to USERNAME and PASSWORD
  echo "${USERPASS}" | grep -q ":" \
    || fail_invalid -U "${USERPASS}" "must be of the form <username>:<password>"
  USERNAME="$( echo "${USERPASS}" | cut -d: -f1 )"
  PASSWORD="$( echo "${USERPASS}" | cut -d: -f2- )"

  valid_username "${USERNAME}" \
    || fail_invalid -U "${USERPASS}" "username must start with a lowercase letter or underscore, followed by lowercase letters, digits, underscores or hyphens"

  [ -n "${PASSWORD}" ] \
    || fail_invalid -U "${USERPASS}" "password cannot be empty"

  unset USERPASS

  ## VERSION depend on other vars, set them now
  [ -n "${VERSION}" ] || VERSION="$( default_version )"

  ## Setup SSH
  if [ "${SSH}" = "true" ]; then
    if [ ! -f overlays/ssh/authorized_keys ]; then
      fail "Can't enable SSH, can't find: overlays/ssh/authorized_keys"
    fi
    ARGS+=(-t ssh:true)
  fi
fi

## Validate VERSION - it ends up in OUT_FILENAME, so a "/" would escape ${OUT_DIR}
[[ "${VERSION}" == *[[:space:]/]* ]] \
  && fail_invalid -x "${VERSION}" "must not contain spaces or '/'"

[[ "${CRYPT_PASS}" == *[[:space:]]* ]] \
  && fail_invalid -R "${CRYPT_PASS}" "must not contain spaces"

[[ "${BUILD_MIRROR}" =~ ^[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+$ ]] \
  || fail_invalid -m "${BUILD_MIRROR}" "must be a URL with no spaces (e.g. http://host/path)"

if [ "${CRYPT_ROOT}" = "true" ]; then
  ARGS+=(-t crypt_root:true)
fi

if [ "${ZRAM}" = "true" ]; then
  ARGS+=(-t zram:true)
fi

if [ "${MINIRAMFS}" = "true" ]; then
  ARGS+=(-t miniramfs:true)
fi

if [ "${CRYPT_ROOT}" = "true" ]; then
  if [ -n "${CRYPT_PASS}" ]; then
    ARGS+=(-t "crypt_password:${CRYPT_PASS}")   # crypt_password needs to come before password
  else
    warn "LUKS encrypting root partition, re-using user's credentials"
  fi
#elif [ -n "${CRYPT_PASS}" ]; then
#  warn "LUKS encrypting root partition not enabled but LUKS credentials detected"
fi

in_list "${DEVICE}" "${SUPPORTED_DEVICES}" \
  || fail_invalid -d "${DEVICE}"

case "${DEVICE}" in
  "pinephone"|"pinetab"|"sunxi" )
    FAMILY="sunxi"
    ARCH="arm64"
    ;;
  "pinephonepro"|"pinetab2"|"rockchip" )
    FAMILY="rockchip"
    ARCH="arm64"
    ;;
  "librem5" )
    FAMILY="librem5"
    ARCH="arm64"
    ;;
  "sdm845"|"sdm670"|"sm6350"|"sc7280"|"sm7150" )
    FAMILY="qcom"
    ARCH="arm64"
    SECTSIZE="$(tomlq -r '.bootimg.pagesize' "devices/qcom/configs/${DEVICE}.toml")"
    ARGS+=(-e "MKE2FS_DEVICE_SECTSIZE:${SECTSIZE}" -t bootonroot:true)
    ;;
  "amd64" )
    FAMILY="amd64"
    ARCH="amd64"
    ;;
esac

## Order packages alphabetically, separate each package with ", "
mapfile -t _pkgs < <( tr ', ' '\n' <<< "${PACKAGES}" | LC_ALL=C sort -u | awk 'NF' )
printf -v PACKAGES '%s, ' "${_pkgs[@]}"
unset _pkgs
PACKAGES="${PACKAGES%, }"

## Is rootfs set OR if we should be using rootfs
if [ -n "${ROOTFS}" ] || [ "${DEVICE}" = "rootfs" ]; then
  ## Make sure there is a default value
  [ -z "${ROOTFS}" ] && ROOTFS="rootfs-${VERSION,,}-${ARCH,,}"

  ## Make sure there is the right file extension
  ROOTFS="${ROOTFS%.tar.*}.tar.xz"
fi

## Filename structure for final file
if [ "${DEVICE}" = "rootfs" ]; then
  OUT_FILENAME="${ROOTFS%.tar.*}"
else
  OUT_FILENAME="kali-nethunterpro-${VERSION,,}-${DEVICE,,}-${DESKTOP,,//-/_}-${ARCH,,}"
fi

## Validate options against the supported lists (both rootfs & image)
## Method #1
#echo "${SUPPORTED_ARCHITECTURES}" | grep -qw "${ARCH}"    \
#  || fail "Unsupported architecture: ${ARCH} (must be one of: ${SUPPORTED_ARCHITECTURES})"
## Method #2
#echo "${SUPPORTED_ARCHITECTURES}" | grep -qw "${ARCH}" \
#  || fail_invalid -a "${ARCH}" "must be one of: ${SUPPORTED_ARCHITECTURES}"
## Method 3
in_list "${ARCH}" "${SUPPORTED_ARCHITECTURES}" \
  || fail_invalid -a "${ARCH}"

## Validate size and add the "GB" suffix
SIZE="$( parse_size "${SIZE}" GB )" \
  || fail_invalid -s "${SIZE}" "must be a number, optionally followed by K/M/G/T (+ optional B)"
ARGS+=(-t "imagesize:${SIZE}")

## Host OS checks
check_os

## Attempt to detect well-known http caching proxies on localhost
##   ...only if user didn't override --mirror or if http_proxy environment variable is set
##   - [ -v http_proxy ]                  - isn't always supported (bash >= 4.2, ~2011?)
##   - [ -z ${http_proxy:-} ]             - doesn't behave if "$ http_proxy= ./build.sh" (will try detect, rather than empty the value)
##   - [ $( env | grep '^http_proxy=' ) ] - looks messy
if [ "${BUILD_MIRROR%/}" = "${DEFAULT_BUILD_MIRROR%/}" ] && [ ! -v http_proxy ]; then
  ## Use a proxy to speed up, if available
  DETECTED_CACHING_PROXY="$( detect_apt_caching_proxy )"
  if [ -n "${DETECTED_CACHING_PROXY}" ]; then
    read -r _port _proxy <<< "${DETECTED_CACHING_PROXY}"
    debug "Detected apt caching proxy: $( b "${_proxy}" ) on port $( b "${_port}" )"
    ## Inside QEMU VM
    export http_proxy="http://10.0.2.2:${_port}"
    unset _port _proxy
  fi
fi

## No need to be root, but the message doesn't make much sense in containers
if [ "$( id -u )" -eq 0 ] && \
   [ ! -e /run/.containerenv ] && \
   [ ! -e /.dockerenv ]; then
  PROMPT="#"
  warn "This script does not require root privileges"
  warn "Please consider running it as a non-root user"
  echo ""
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Overview
#

_cross_build=""
is_cross_build && _cross_build=", so $( b "cross-building ${ARCH} image" )"

_env=$( detect_container )
[ -n "${_env}" ] && _env="container ($( b "${_env}" ))" || _env="host"

{
echo "# Build:"
if [ "${DEVICE}" = "rootfs" ]; then
  point "Building a Kali ${PROJECT} $( b "${DEVICE}" )  for $( b "${ARCH}" ) architecture"
else
  if [ -n "${ROOTFS}" ]; then
    point "Building a Kali ${PROJECT} $( b "${DEVICE} ${PLATFORM}" ) based on $( b "${ROOTFS}" )"
  else
    point "Building a Kali ${PROJECT} $( b "${DEVICE} ${PLATFORM}" ) for $( b "${ARCH}" ) architecture"
  fi
fi
point "Build environment is $( b "${_env}" )"
point "Host architecture is $( b "${HOST_ARCH}" )${_cross_build}"

echo "# Options:"
point "Branch              : $( b "${BRANCH}" )"
point "Build mirror        : $( b "${BUILD_MIRROR}" )"
point "Device              : $( b "${DEVICE}" )"
point "Output              : $( b "${OUT_DIR}/${OUT_FILENAME}*" )"   # ZIP may alter the file extension
point "Version             : $( b "${VERSION}" )"
point "Zip artifacts       : $( b "${ZIP}" )"

echo "# ${PROJECT}:"
point "Additional packages : $( b "${PACKAGES}" )"
point "Desktop environment : $( b "${DESKTOP}" )"
point "File System         : $( b "${FILESYSTEM}" )"
point "Hostname            : $( b "${KALI_HOSTNAME}" )"
point "LUKS enabled        : $( b "${CRYPT_ROOT}" )"
point "LUKS password       : $( b "${CRYPT_PASS}" )"
point "Mini RAMFS          : $( b "${MINIRAMFS}" )"
point "Partition table     : $( b "${PARTITION_TABLE}" )"
point "SSH configured      : $( b "${SSH}" )"
point "Username & password : $( b "${USERNAME}:${PASSWORD}" )"
point "ZRAM                : $( b "${ZRAM}" )"

echo "# VM build resources:"
point "Image size          : $( b "${SIZE}" )"
point "Memory              : $( b "${MEMORY}" )"
point "Scratch size        : $( b "${SCRATCHSIZE}" )"

echo "# Proxy configuration:"
if [ -n "${DETECTED_CACHING_PROXY}" ]; then
  read -r _port _proxy <<< "${DETECTED_CACHING_PROXY}"
  point "Detected caching proxy $( b "${_proxy}" ) on port $( b "${_port}" )"
elif [ -n "${http_proxy:-}" ]; then
  point "Using proxy via environment variable: $( b "http_proxy=${http_proxy}" )"
elif [ "${DEFAULT_BUILD_MIRROR%/}" != "${BUILD_MIRROR%/}" ]; then
  point "$( b "Skipping detecting" ) apt caching proxy (custom build-mirror)"
else
  point "$( b "No apt caching proxy" ) detected"
fi
} | kali_message "Kali ${PROJECT} ${PLATFORM}"
unset _cross_build _env _port _proxy

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Build
#

## Prepare output directory
vrun mkdir -pv "${OUT_DIR}/"

## Capture all output, stdout & stderror, from here on out into a file
exec &> >( tee -a "${OUT_DIR}/${OUT_FILENAME}.log" )

## Do magic
create_image "${ARGS[@]}" "${@}"

## Compress
if "${ZIP}"; then
  vrun tar --ignore-failed-read --xattrs -czvf "${OUT_DIR}/${OUT_FILENAME}.tar.gz" "${OUT_DIR}/${OUT_FILENAME}"*
fi

## Checksum
( cd "${OUT_DIR}" \
  && find . -maxdepth 1 -type f -name "${OUT_FILENAME}*" ! -name '*.log' ! -name '*.sha512sum' ! -name '*.tar.gz' -print0 \
    | while IFS= read -r -d '' _f; do
        _f="${_f#./}"
        vrun sha512sum "${_f}" | tee "${_f}.sha512sum"
      done )

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Finish
#

cat << EOF
..............
            ..,;:ccc,.
          ......''';lxO.
.....''''..........,:ld;
           .';;;:::;,,.x,
      ..'''.            0Xxoc:,.  ...
  ....                ,ONkc;,;cokOdc',.
 .                   OMo           ':$( b dd )o.
                    dMc               :OO;
                    0M.                 .:o.
                    ;Wd
                     ;XO,
                       ,d0Odlc;,..
                           ..',;:cdOOd::,.
                                    .:d;.':;.
                                       'd,  .'
                                         ;l   ..
                                          .o
                                            c
                                            .'
                                             .
Successful build! The following build artifacts were produced:
EOF
## Alt: stat  "${OUT_DIR}/${OUT_FILENAME}*"
##      ls -h "${OUT_DIR}/${OUT_FILENAME}"* | sed "s_^${PWD}/__; s_^_* _"
find "${OUT_DIR}/" -maxdepth 1 -type f -name "${OUT_FILENAME}*" | sed "s_^${PWD}/__; s_^_* _" | sort
