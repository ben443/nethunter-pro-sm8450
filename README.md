# Kali NetHunter Pro (Build-Script)

<!-- Upstream: https://salsa.debian.org/Mobian-team/mobian-recipes -->

[Kali NetHunter Pro](https://www.kali.org/get-kali/#kali-mobile) _([docs](https://www.kali.org/docs/nethunter-pro/))_ is a Mobile Penetration Testing Platform, based on GNU/Linux _(rather than [Kali NetHunter](https://www.kali.org/get-kali/#kali-mobile) which uses [Android](https://www.kali.org/docs/nethunter/))_.

![Kali NetHunter Pro Logo](./images/kali-nethunterpro-logo-dragon-orange-transparent.png)

A set of [debos](https://github.com/go-debos/debos) recipes for building a
Kali Linux based image for mobile phones<!--, initially targeting Pine64's PinePhone-->.

Pre-built images are available [here](https://www.kali.org/get-kali/#kali-mobile), otherwise you can build it yourself.

The [default user](https://www.kali.org/docs/introduction/default-credentials/) is `kali` with password `1234`.

## Build

To build the image, you need to have `debos` and `bmaptool`. On a Debian-based
system, install these dependencies by typing the following command in a terminal:

```
sudo apt install debos bmap-tools xz-utils
```

Note: DNS resolution may break after installing the above packages. To fix this, add a valid DNS resolver (e.g., `1.1.1.1`) to the file `/etc/systemd/resolved.conf` and then `sudo systemctl restart systemd-resolved.service`

If you want to build an image for a Qualcomm-based device, additional packages
are required, which you can install with the following command:

```
sudo apt install android-sdk-libsparse-utils yq mkbootimg
```

### Qualcomm targets

- `sc7280`
- `sdm670`
- `sdm845`
- `sm6350`
- `sm8450`
- `gts8wifi` (Samsung Galaxy Tab S8 Wi-Fi / SM8450)

Example build command for Galaxy Tab S8 Wi-Fi:

```
./build.sh -t gts8wifi
```

For `sm8450` targets, the build now compiles and installs `uniLoader` from source during image creation.

Building with disk encryption support will also require the package `cryptsetup` to be installed
on your host.

Similarly, if you want to use F2FS for the root filesystem (which isn't such a
good idea, as it has been known to cause corruption in the past), you'll need to
install `f2fs-tools` as well.

The build system will cache and re-use it's output files. To create a fresh build
remove `*.tar.gz`, `*.sqfs` and `*.img` before starting the build.

If your system isn't debian-based (or if you choose to install `debos` without
using `apt`, which is a terrible idea), please make sure you also install the
following required packages:
- `debootstrap`
- `qemu-system-x86`
- `qemu-user-static`
- `binfmt-support`
- `squashfs-tools-ng` (only required for generating installer images)

Then simply browse to the `kali-nethunter-pro` folder and execute `./build.sh`.

You can use `./build.sh -d` to use the docker version of `debos`.

### Samsung Galaxy Tab S8 Wi-Fi (gts8wifi / SM8450)

`gts8wifi` is a Qualcomm SM8450 target and follows the repository's qcom build flow.

Build examples:

```sh
./build.sh -t gts8wifi
./build.sh -t gts8wifi -e phosh
```

Fedora boot prerequisites and constraints (from `ben443/samsung-gts8-notes`):
- Use TWRP recovery as a recovery/safety environment.
- Use Project Mu as the secondary bootloader (`boot` replacement) before testing Fedora boot.
- Expect manual partitioning/flashing steps; this repository does not automate repartitioning or per-device flashing.
- Fedora notes currently rely on ext4 rootfs preparation and a matching DTB (`sm8450-galaxy-tab-s8-5g.dtb`) in the Fedora boot path; one referenced source is Robotix22 Project Mu: <https://github.com/Robotix22/MU-Qcom/raw/8e7ebd3973e54ab22d830f1203fed4877176e99f/Platforms/SM8450Pkg/FdtBlob/sm8450-galaxy-tab-s8-5g.dtb>.

Caveats:
- Device support here is build-system integration for qcom/SM8450 artifacts, not a full flashing or hardware enablement workflow.
- If your boot chain requirements differ from current qcom defaults, adjust local boot components accordingly.

Related upstream references:
- [`aaronsb/sm-x800-linux`](https://github.com/aaronsb/sm-x800-linux): useful for Samsung SM8450 boot-chain context (notably uniLoader usage), but this is focused on Tab S8+ (`gts8pwifi`) so partitioning and device-specific hardware notes are not directly interchangeable with `gts8wifi`.
- [`sm8450-mainline`](https://github.com/sm8450-mainline): useful as a broader SM8450 mainline ecosystem reference (DT/device-tree sources, U-Boot/UEFI work, and firmware packaging), and should be treated as upstream context rather than a drop-in configuration for this repository.

### Building QEMU image

You can build a QEMU x86_64 image by adding the `-t amd64` flag to `build.sh`

### Running QEMU image

#### From commandline

The resulting files are raw images. You can start qemu like so:

```
qemu-system-x86_64 -drive format=raw,file=<imagefile.img> -enable-kvm \
    -cpu host -vga virtio -m 2048 -smp cores=4 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd
```

UEFI firmware files are available in Debian thanks to the
[OVMF](https://packages.debian.org/sid/all/ovmf/filelist) package.
Comprehensive explanation about firmware files can be found at
[OVMF project's repository](https://github.com/tianocore/edk2/tree/master/OvmfPkg).


It can be useful to be able to SSH into the QEMU image, in order to collect
logs directly from the host system. This can be done lanching qemu like this:

```
qemu-system-x86_64 -drive format=raw,file=<imagefile.img> -enable-kvm \
    -cpu host -vga virtio -m 2048 -smp cores=4 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
    -nic user,hostfwd=tcp::8888-:22
```

that forwards port 8888 on the host to port 22 on the guest system. Then, connection
from the host system to the guest is as simple as

```
$ ssh mobian@localhost -p 8888
$ sftp -P 8888 mobian@localhost
```

#### Using virt-manager

You may want to run the image under [virt-manager](https://packages.debian.org/stable/virt-manager)
for easier access to USB redirection and keyboard controls. 

To create a VM for mobian image on x86_64, launch virt-manager, click `New VM` -> 
`Import existing disk image` -> select the raw image and OS version then progress to the 
`Ready to begin installation` page, check `customize configuration before install` then click finish.

Under `Hypervisor Details`, change firmware to `UEFI x86_64: /usr/share/OVMF/OVMF_CODE_4M.fd` then `apply` and `begin installation`, 
the image should now boot up.


#### Convert and resize disk image

You may also want to convert the raw image to [qcow2](https://www.qemu.org/docs/master/system/images.html#disk-image-file-formats) format
and resize it like this:

```
qemu-img convert -f raw -O qcow2 <raw_image.img> <qcow_image.qcow2>
qemu-img resize -f qcow2 <qcow_image.qcow2> +20G
```

## Install

Insert a MicroSD card into your computer, and type the following command:

```
sudo bmaptool copy <image> /dev/<sdcard>
```

or:

```
sudo dd if=<image> of=/dev/<sdcard> bs=1M
```

*Note: Make sure to use your actual SD card device, such as `mmcblk0` instead of
`<sdcard>`.*

**CAUTION: This will format the SD card and erase all its contents!!!**

## Install via Windows

You can use balena etcher to install the image downloaded onto the sd card. Start etcher and select the image file, target (which would be the sd card) and then "Flash".

## Contributing

If you want to help with this project, please have a look at the
[roadmap](https://wiki.debian.org/Teams/Mobian/Roadmap) and
[open issues](https://salsa.debian.org/Mobian-team/mobian-recipes/-/issues).

In case you need more information, feel free to get in touch with the developers
on [#mobian:matrix.org](https://matrix.to/#/#mobian:matrix.org).

# License

This software is licensed under the terms of the GNU General Public License,
version 3.
