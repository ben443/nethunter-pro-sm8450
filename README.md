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
- `sm8450` (Samsung Galaxy Tab S8 WiFi, `gts8wifi`)

Example build command for Galaxy Tab S8 WiFi:

```
./build.sh -t sm8450
```

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

This repository now includes an **experimental** Qualcomm target for the Galaxy Tab S8 Wi-Fi:

```sh
./build.sh -t sm8450 -e phosh
```

Implemented scope:
- Qualcomm SM8450 build target wiring in `build.sh`
- SM8450 device config at `devices/qcom/configs/sm8450.toml`
- CI image jobs for `sm8450` in `.gitlab-ci.yml`

Reference provenance:
- User-provided notes repository: `ben443/samsung-gts8-notes`
- Notes commit `80f93e1627fb9a9e402be78daa93d3d0431b449c` (`PORTING_PLAN.md`)
- Notes commit `0a929d6f9f4701542ea392204db354c253f862fd` (`Booting Fedora/README.md`)

Limitations and validation status:
- This is build-system integration only and is **not** hardware boot-validated in this repository.
- Device-specific flashing/install procedures and partition modification steps are intentionally not automated here.
- Manual hardware validation is still required to confirm boot, display, touch, Wi-Fi, USB, and storage behavior.

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
