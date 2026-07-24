# Kali-NetHunter-Pro Build-Script

<!-- Upstream: https://salsa.debian.org/Mobian-team/mobian-recipes -->

_Kali NetHunter Pro image builder, via `debos` (with `fakemachine` and `KVM`), [forked](https://salsa.debian.org/Mobian-team/mobian-recipes) from [Mobian](./README.mobian.md)._

These are the same [build-scripts](https://gitlab.com/kalilinux/nethunter/build-scripts) that the [Kali NetHunter team](https://www.kali.org/) uses to generate the official Kali NetHunter Pro images, found on [kali.org/get-kali/](https://www.kali.org/get-kali/).

Kali NetHunter Pro is a mobile penetration testing platform, based on GNU/Linux, rather than [Kali NetHunter](https://www.kali.org/get-kali/#kali-mobile) which uses [Android](https://www.kali.org/docs/nethunter/).

For more information, please see: [kali.org/docs/nethunter-pro/](https://www.kali.org/docs/nethunter-pro/).

_Build [your Kali](https://www.kali.org/docs/introduction/kali-linux-image-overview/), today!_

![Kali NetHunter Pro Logo](./images/kali-nethunterpro-logo-dragon-orange-transparent.png)

## Prerequisites

_We recommend building on a Linux-based host, which matches the desired architecture._

There are various ways to get ready to use kali-nethunter-pro build-script. You can either:

- `build.sh` - [Build straight from your machine](#build-from-the-host)
- `build-in-container.sh` - [Build from within a container](#build-from-within-a-container) _(such as Docker or Podman)_ <!-- Should be able to use other alts, but they are untested -->

For this script to work, it **will require KVM**. However, super user access isn't required.
_We will skip over enabling KVM in BIOS/UEFI._ <!-- Technically its possible to build without it (QEMU vs QEMU+KVM), but its slooooooow -->

The reason why KVM is required is the build actually happens from within a virtual machine (VM), that is created on-the-fly by the build tool [debos](https://github.com/go-debos/debos).
_Debos uses [fakemachine](https://github.com/go-debos/fakemachine) under the hood, which in turn relies on QEMU+KVM._

- - -

First install git, and make sure that the repository is cloned locally:

```console
$ sudo apt-get install --no-install-recommends \
    git ca-certificates
$ git clone https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-pro.git
$ cd ./kali-nethunter-pro/
```

- - -

Due to the requirements of QEMU/KVM, you must be part of the `kvm` group.
You can check by doing:

```console
$ # Not apart of the group
$ grep kvm /etc/group
kvm:x:104:
$
$ # In the group
$ grep kvm /etc/group
kvm:x:104:kali
$
```

If your username does not appear in the line returned (e.g. `kali`), it means that you are not in the group, and you must add yourself to the `kvm` group.
You can do that by doing:

```console
$ sudo adduser $USER kvm
```

Then **log out and log back in** for the change to take effect. <!-- That's not closing down the terminal app and re-opening it, but rather logging out of Xfce!
...or

```console
$ newgrp kvm
```

libvirt == If using rootless podman -->

### Build From The Host

To build directly on your host, with `build.sh`, install the build dependencies:

```console
$ sudo apt-get install --no-install-recommends \
    debos e2fsprogs linux-image-amd64 xz-utils parted dosfstools fdisk yq cryptsetup f2fs-tools btrfs-progs
```
<!-- This should match what is in: [Dockerfile](./Dockerfile) & [kali.org/docs/nethunter-pro/](https://www.kali.org/docs/nethunter-pro/) -->

_NOTE: `yq` (which provides `tomlq`) is required for Qualcomm-based devices (`sdm*`, `sm*` and `sc*`) - it's used to read the boot image page size out of each device's config._

_NOTE: Building with `-c/--crypt-root` (LUKS disk encryption) additionally requires `cryptsetup`._

_NOTE: Building with `-f/--filesystem f2fs` additionally requires `f2fs-tools`. F2FS isn't recommended for the root filesystem, as it has been known to cause corruption in the past._

_NOTE: Building with `-f/--filesystem btrfs` additionally requires `btrfs-progs`._

- - -

Now you can use `./build.sh`, which will build a NetHunter Pro image straight on your machine.

### Build From Within A Container

_We will skip over setting up any container software._

If you prefer to build from within a container, you will need to install and configure either `docker` or `podman` on your machine.

- `docker` requires the user to be added to the Docker group, or using the root account (e.g. `$ sudo ./build-in-container.sh`).
- `podman` has been tested with both as rootful (e.g. `$ sudo ./build-in-container.sh`) and rootless (e.g. `$ ./build-in-container.sh`).

- - -

`build-in-container.sh` is simply a wrapper on top of `build.sh`. It detects which OCI-compliant container engine to use, takes care of creating the [container image](./Dockerfile) if missing, and then it starts the container to perform the build from within.

You have three ways to provide the container image:

```console
$ # Option #1 - Automated build (recommended)
$ ./build-in-container.sh
$ ./build-in-container.sh --force   # If you need to rebuild the image from scratch
$
$
$
$ # Option #2 - Manual build
$ docker build -t kali-build/kali-nethunterpro .
$ # ...OR...
$ podman build -t kali-build/kali-nethunterpro .
$
$
$
$ # Option #3 - Use the pre-generated
$ docker pull registry.gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-pro:latest
$ # ...OR...
$ podman pull registry.gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-pro:latest
```

- - -

If you have both `docker` and `podman` installed, `build-in-container.sh` will default to using `podman`. To change this, prefix `CONTAINER=docker` before `./build-in-container.sh`:

```console
$ CONTAINER=docker ./build-in-container.sh [...]
```
- - -

Now you can use `./build-in-container.sh` (rather than `./build.sh`), to build a image.

## Help

```console
$ ./build.sh --help
Usage: build.sh [OPTIONS] [-- <debos options>]

Build a Kali NetHunter Pro image.

Build options:
  -a, --arch ARCH              Build a image for this architecture (default: amd64)
                               Supported: amd64 arm64
  -b, --branch BRANCH          Kali branch used to build the image (default: kali-rolling)
                               Supported: kali-rolling kali-dev kali-last-snapshot
  -d, --device DEVICE          Variant of image to build, see below for details (default: amd64)
                               Supported: amd64 pinephone pinetab sunxi pinephonepro pinetab2 rockchip librem5 sdm845 sdm670 sm6350 sc7280 sm7150 rootfs
  -m, --mirror URL             Mirror used to build the image (default: http://http.kali.org/kali)
  -r, --rootfs ROOTFS          Rootfs to use to build the image (default: none)
  -s, --size SIZE              Size of the disk image in GB (default: 8)
  -x, --version VERSION        What to name the image release as (default: rolling)
  -z, --zip                    Zip image and metadata files after the build
  -h, --help                   Show this help and exit

Customization options:
  -D, --desktop DESKTOP        Desktop environment installed in the image (default: phosh)
                               Supported: phosh plasma-mobile
  -f, --filesystem FORMAT      Filesystem to use (default: ext4)
                               Supported: ext4 btrfs f2fs
  -c, --crypt-root             Enables LUKS2 full-disk encryption on the root partition
  -R, --crypt-password PASS    Passphrase used for crypt-root's LUKS encryption (default: 1234)
  -p, --partition-table VALUE  Partition table to use (default: gpt)
                               Supported: gpt mbr
  -M, --miniramfs              Generates a stripped-down initramfs for devices which have a size restriction
  -H, --hostname HOSTNAME      Set system host name (default: kali)
  -S, --ssh                    Configure SSH (default: false)
  -U, --userpass USERPASS      Username and password, separated by a colon (default: kali:1234)
  -Z, --zram                   Mounts /tmp and /var/tmp on compressed RAM-backed zram devices instead of flash storage

Apt caching proxy:
  Auto-detected: localhost:3142 (apt-cacher-ng), localhost:8000 (squid-deb-proxy).
  If detected and http_proxy is not set, http_proxy is exported automatically.

Supported environment variables:
  http_proxy  HTTP proxy URL, see README.md for details
  DEBUG       Print extra debug output
  Any --flag value can be pre-set via the env var of the same name (e.g. BUILD_MIRROR, ARCH)

Most useful debos options:
  --artifactdir DIR   Set artifact directory (default: /home/kali/kali-nethunter-pro/output)
  --memory SIZE       Memory to build VM, e.g. 4G or 4096M (default: 2G)
  --scratchsize SIZE  Scratch disk to build VM, e.g. 45G (default: 8G)
  --verbose           Make output more detailed
  --debug-shell       Get a shell on the VM
  --help, -h          See all debos options

Examples:
  build.sh
  build.sh --device pinephone
  build.sh -b kali-dev -d pinetab -D plasma-mobile
  build.sh -b kali-last-snapshot -d rootfs
  build.sh -r ./output/rootfs-last_snapshot-amd64.tar.xz -d librem5
  build.sh -d librem5 -- --memory 4G --scratchsize 16G
  build.sh -d amd64 -- --debug-shell
$
```

_NOTE: `-a/--arch` can only works with `-d/--device rootfs`._

_NOTE: `-S/--ssh` requires your SSH public key at `overlays/ssh/authorized_keys` before building._

_NOTE: Setting "--flag" value as a environment variables only works for on the host (e.g. `./build.sh`). These do not get passed when using a container (e.g. `./build-in-container.sh`)._

For more information and/or examples, please see:

- [kali.org/docs/nethunter-pro/](https://www.kali.org/docs/nethunter-pro/)

## Build + Custom Values

Use either `build.sh` or `build-in-container.sh`, at your preference.
From this point we will use `build.sh` for brevity.

The default options will build a [Kali rolling](https://www.kali.org/docs/general-use/kali-branches/) generic image, using Phosh as desktop environment for AMD64 architecture.
This can be used with QEMU and/or virt-manager.

```console
$ ./build.sh
┏━━(Kali NetHunter Pro image)
┃ # Build:
┃  * Building a Kali NetHunter Pro amd64 image for amd64 architecture
┃  * Build environment is host
┃  * Host architecture is amd64
┃ # Options:
┃  * Branch              : kali-rolling
┃  * Build mirror        : http://http.kali.org/kali/
┃  * Device              : amd64
┃  * Output              : /home/kali/kali-nethunter-pro/output/kali-nethunterpro-rolling-amd64-phosh-amd64*
┃  * Version             : rolling
┃  * Zip artifacts       : false
┃ # NetHunter Pro:
┃  * Desktop environment : phosh
┃  * File System         : ext4
┃  * Hostname            : kali
┃  * LUKS enabled        : false
┃  * LUKS password       : 1234
┃  * Mini RAMFS          : false
┃  * Partition table     : gpt
┃  * SSH configured      : false
┃  * Username & password : kali:1234
┃  * ZRAM                : false
┃ # VM build resources:
┃  * Image size          : 8GB
┃  * Memory              : 2G
┃  * Scratch size        : 8G
┃ # Proxy configuration:
┃  * No apt caching proxy detected
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[...]
```

- - -

Now, we are going to build it from the [last stable release (last snapshot)](https://www.kali.org/docs/general-use/kali-branches/) of Kali (`-b`/`--branch`), and using Plasma Mobile as the desktop environment (`-D`/`--desktop`).

```console
$ ./build.sh -b kali-last-snapshot -D plasma-mobile
```

- - -

When building a series of images, it's faster to split the build in two: first build a rootfs with `./build.sh -d rootfs` (`-d`/`--device`), then build each image from it with `./build.sh -r ROOTFS_NAME.tar.xz` (`-r`/`--rootfs`). The rootfs is the slow part, so building it once and reusing it pays off as soon as you need a second image.

In the example below, we built a kali-rolling rootfs first for `arm64` (`-a`/`--arch`), and then we build a series of images:

```console
$ ./build.sh -b kali-rolling -d rootfs -a arm64
$
$ ./build.sh -r output/rootfs-rolling-arm64.tar.xz -d pinephone
$ ./build.sh -r output/rootfs-rolling-arm64.tar.xz -d pinephonepro
$ ./build.sh -r output/rootfs-rolling-arm64.tar.xz -d librem5
```

_NOTE: If doing multiple builds parallel/simultaneously, use either  `-r/--rootfs` or `--artifactdir` (e.g. `$ ./build.sh -d pinephone -- --artifactdir output/pinephone`)._

<!-- Bulk build easy copy/paste example:

```console
release=YYYY.X
./build.sh -b kali-last-snapshot -d rootfs -a arm64 -x "${release}"
for device in pinephone pinephonepro librem5; do
  ./build.sh -r "output/rootfs-${release}-arm64.tar.xz" -d "${device}" 2>&1 | tee "${device}.log" &
done
wait
``` -->


- - -

If you wish to debug a failed run, with as much output as possible (`DEBUG=1`), and pull packages from a specific [Kali mirror](https://www.kali.org/docs/community/kali-linux-mirrors/) using `-m`/`--mirror`:

```console
$ DEBUG=1 ./build.sh --mirror http://kali.download/kali
```

## Caching Proxy Configuration

When building OS images, it is useful to have a caching mechanism in place, to avoid downloading all the packages from the Internet, again and again.
To this effect, the build script attempts to detect known caching proxies that would be running on the local host. If first refers to the local APT configuration `Acquire::http::Proxy`. If not set, it then tries to detect `apt-cacher-ng` and `squid-deb-proxy` by checking if a service is listening on their default port. This mechanism doesn't work for `approx` (a well-known APT caching proxy), as it's auto-started on demand.

_NOTE: This detection only runs when using the default mirror. If you pass your own `-m/--mirror` value, detection is skipped._

To override this detection, you can export the environment variable `http_proxy` yourself.
However, you should remember that `debos` does the build within a QEMU Virtual Machine, therefore `localhost` in the build environment refers to the guest VM, not to the host running the build-script. If you want to reach the host from the VM, you will want to use: `http://10.0.2.2`.
For example, if you want to use a proxy that is running on your machine on the port `9876`, use: `export http_proxy=http://10.0.2.2:9876`.
If you want to make sure that no proxy is used, use: `$ http_proxy= ./build.sh`.

Refer to <https://github.com/go-debos/debos#environment-variables> for more details.

Alternatively, you can setup a [local Kali mirror](https://www.kali.org/docs/community/setting-up-a-kali-linux-mirror/).

## Deploy Image

See also: [kali.org/docs/nethunter-pro/](https://www.kali.org/docs/nethunter-pro/)

The [default user](https://www.kali.org/docs/introduction/default-credentials/) is `kali` with password `1234`.

### Flash to a device (dd)

Insert a MicroSD card into your computer, and type the following command:

```console
$ lsblk
$ sudo dd if=output/kali-nethunterpro-rolling-pinephone-phosh-arm64.img of=/dev/<sdcard> bs=1M
```

_NOTE: Make sure to use your actual SD card device, such as `mmcblk0` instead of `<sdcard>`._

**CAUTION: This will format the SD card and erase all its contents!**

#### From Windows (balenaEtcher)

You can use [balenaEtcher](https://etcher.balena.io/) to flash the image onto the SD card. Start Etcher, select the image file, select the target (the SD card), then "Flash".

### Running an `amd64` build in QEMU

An `amd64` build produces a raw disk image, which can be run directly with QEMU.
UEFI firmware files are available in Debian thanks to the [OVMF](https://packages.debian.org/sid/all/ovmf/filelist) package.
It is also possible to SSH into the running image (useful for pulling logs off the host), via port forwarding (22/TCP \[NetHunter/VM/Guest\] -> 8888/TCP \[Host\]):

```console
$ sudo apt-get install --no-install-recommends \
    qemu-system-x86 ovmf
$ qemu-system-x86_64 \
    -drive format=raw,file=output/kali-nethunterpro-rolling-amd64-phosh-amd64.img \
    -enable-kvm \
    -cpu host \
    -vga virtio \
    -m 2048 \
    -smp cores=4 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
    -nic user,hostfwd=tcp::8888-:22
```

Then in another console:

```console
$ ssh kali@localhost -p 8888
$ sftp -P 8888 kali@localhost
```

### Running an `amd64` build in virt-manager

You may instead want to run the image under [virt-manager](https://packages.debian.org/stable/virt-manager) for easier access to USB redirection and keyboard controls.
Launch virt-manager. `New VM` -> `Import existing disk image` -> select the raw image, progress to `Ready to begin installation`, check `customize configuration before install`, click finish. Under `Hypervisor Details`, change firmware to `UEFI x86_64: /usr/share/OVMF/OVMF_CODE_4M.fd`, then `apply` and `begin installation`.

You may also want to convert the raw image to [qcow2](https://www.qemu.org/docs/master/system/images.html#disk-image-file-formats) format and resize it:

```console
$ qemu-img convert -f raw -O qcow2 output/kali-nethunterpro-rolling-amd64-phosh-amd64.img output/kali-nethunterpro-rolling-amd64-phosh-amd64.qcow2
$ qemu-img resize -f qcow2 output/kali-nethunterpro-rolling-amd64-phosh-amd64.qcow2 +20G
```

## Troubleshooting

### Build-Script

#### Not Enough Memory

When the scratch area gets full (i.e. the `--scratchsize` value is too low), the build might fail with this kind of error messages:

```console
[...]: failed to write (No space left on device)
[...]: Cannot write: No space left on device
```

Solution: bump the value of `--scratchsize`.
You can pass arguments to debos after the special character `--`, so if you need for example 50G, you can do `$ ./build.sh [...] -- --scratchsize=50G`.

### Get A Shell In The VM When The Build Fails

When debugging build failures, it's convenient to be dropped in a shell within the VM where the build takes place.
This is possible by giving the option `--debug-shell` to debos: `$ ./build.sh [...] -- --debug-shell`.

## Known Limitations

There are a few known limitations of using this build-script:

- [Docker rootless](https://docs.docker.com/engine/security/rootless/) is not supported

_If you find something, [let us know](https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-pro/-/work_items)!_
