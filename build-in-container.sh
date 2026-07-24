#!/usr/bin/env bash
#
# $ ./$0
# $ ./$0 [...] --force
# $ CONTAINER=docker ./$0
#

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Environment
#

set -euEo pipefail
trap 'cleanup' INT TERM

cd "$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Variables
#

CONTAINER=${CONTAINER:-}
FORCE=0
IMAGE=kali-build/kali-nethunterpro   # Alt: docker.io/godebos/debos ~ https://hub.docker.com/r/godebos/debos ~ https://github.com/go-debos/debos
OPTS=()
SUDO=()

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Functions
#

## Output bold only if both stdout/stderr are opened on a terminal
if [ -t 1 ] && [ -t 2 ]; then
  b() { tput bold; echo -n "${*}"; tput sgr0; }
else
  b() { echo -n "${*}"; }
fi

point() { echo " * ${*}"; }
warn()  { echo "WARNING: ${*}" 1>&2; }
fail()  { echo "ERROR: ${*}"   1>&2; exit 1; }

vexec() { b "$ ${*}"; echo; exec "${@}"; }   # Last program in this script should use exec
vrun()  { b "$ ${*}"; echo;      "${@}" & child_pid=${!}; wait "${child_pid}"; }   # Backgrounded + waited on (rather than a plain foreground call) so cleanup() can kill it if we're interrupted

# Kill vrun()
cleanup() { [ -n "${child_pid:-}" ] && kill -TERM "${child_pid}" 2>/dev/null; }

build_container() {
  local _cache_args=()
  [ "${FORCE}" -eq 1 ] && _cache_args=(--no-cache)

  if [ "${FORCE}" -eq 1 ] || ! "${SUDO[@]}" "${CONTAINER}" inspect --type image "${IMAGE}" >/dev/null 2>&1; then
    vrun "${SUDO[@]}" "${CONTAINER}" build --network host "${_cache_args[@]}" --tag "${IMAGE}" .
    echo
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Parse & validate arguments
#

_passthrough=()
while [ $# -gt 0 ]; do
  case "${1}" in
    --force)  FORCE=1;                shift ;;
    *)        _passthrough+=("${1}"); shift ;;
  esac
done
set -- "${_passthrough[@]}"
unset _passthrough

if command -v podman >/dev/null 2>&1 && \
  { [ -z "${CONTAINER}" ] || [ "${CONTAINER}" == "podman" ]; }; then
  CONTAINER=podman

  ## We don't want stdout in the journal
  OPTS+=( --log-driver none )

  rootless=$( "${CONTAINER}" info --format '{{.Host.Security.Rootless}}' )
  if [ "${rootless}" != "false" ]; then
    warn "${CONTAINER} is rootless (or '${CONTAINER} info' failed)"
    warn "  ${CONTAINER} info Host.Security.Rootless: '${rootless}'"

    ## Using /dev/kvm speeds up building A LOT (KVM + QEMU), otherwise its slooooow (QEMU only)
    ##   Podman can run (easy) as rootful and rootless. Rootless needs permission to access /dev/kvm
    ##   Its possible to pass the hosts groups (primary + secondary/supplementary) in order to access /dev/kvm
    ##   You have (a lot of) options with podman, one of them is crun vs runc.
    ##   Had issues (2026-06-12), runc (1.3.5+ds1-1) was silently having issues - crun (1.28-1) working
    if ! command -v crun >/dev/null 2>&1; then
      warn "rootless ${CONTAINER} + runc cannot access: /dev/kvm"
      warn "  Either: install crun (e.g. $ sudo apt install crun) or re-run with sudo (aka rootful)"
      fail "Missing 'crun', aborting"
    fi

    OPTS+=(
      --runtime crun            # runc works with rootful, crun works with rootless, in order to (correctly) pass secondary/supplementary hosts groups into container
      --userns=keep-id          # Keep host's uid/gid so to quiet fakemachine's "do not run as root" warning
      --group-add keep-groups   # Pass all host groups (e.g. kvm) into the userns (user namespace) to access /dev/kvm
    )
  fi
elif command -v docker >/dev/null 2>&1 && \
  { [ -z "${CONTAINER}" ] || [ "${CONTAINER}" == "docker" ]; }; then
  CONTAINER=docker
else
  if [ -z "${CONTAINER}" ]; then
    fail "No container engine detected, aborting"
  else
    fail "Unknown CONTAINER value: ${CONTAINER}"
  fi
fi

## Permissions & security
OPTS+=(
  ## The build happens via `debos`, which uses `fakemachine` to spin up a nested QEMU/KVM VM and does the actual OS install inside THAT VM, not via chroot/debootstrap in this container directly.
  ## So there is no "--cap-add" from bpftrace.
  ## Artifacts produced from a "base-line" bare metal build (./build.sh), was compared with a container (./build-in-container.sh)
  ##   $ virt-ls -l -R --uids kali-linux-*.img
  ## Items checked for:
  ##   - Artifact size (excluding compression noise)
  ##   - Artifact diff (file count, permissions, owner/group, size, path as well as content)
  ##   - Build time length
  --cap-drop=ALL
)

## If stdin is an option, use tty
if [ -t 0 ]; then
  OPTS+=(
    --interactive
    --tty
  )
fi

OPTS+=(
  --rm

  --network host

  --volume "${PWD}:/build"   # Alt: ${PWD}:/srv or ${PWD}:/recipes   # Alt: --mount type=bind,source=${PWD},destination=/recipes
  --workdir /build

  ## This is for ./build.sh, as we are using root to run that
  --env "HOST_UID=${SUDO_UID:-$( id -u )}"
  --env "HOST_GID=${SUDO_GID:-$( id -g )}"
)

## Kernel-based Virtual Machine (KVM) - Check if virtualization extensions is enabled (in BIOS/UEFI)
[ -e /dev/kvm ] \
  || fail "Missing /dev/kvm, aborting"
## Method #1
#_kvm_gid="$( stat -c "%g" /dev/kvm )" \
#  || fail "Cannot stat: /dev/kvm (permissions issue?)"
#OPTS+=( --device /dev/kvm --group-add "${_kvm_gid}" )
#unset _kvm_gid
## Method #2 ( --userns=keep-id /--group-add keep-groups )
OPTS+=( --device /dev/kvm )

## When running as root, force container to non-root to quiet fakemachine warning (as it does not want to be root)
[ "$( id -u )" -eq 0 ] \
  && OPTS+=( --user "$( stat --format="%u:%g" . )" )

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Build
#

build_container

vexec "${SUDO[@]}" "${CONTAINER}" run "${OPTS[@]}" "${IMAGE}" /build/build.sh "${@}"
