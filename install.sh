#!/bin/sh

. ./config

#LOG_FILE="./install-$(date "+%y-%m-%d--%H-%M-%S").log"
LOG_FILE="./install.log"

echo "SteamOS Deboostrap Install" > "$LOG_FILE" 2>&1
echo "" >> "$LOG_FILE" 2>&1

################################################################################
# Tests ########################################################################
################################################################################

test_config () {
    if [ -z "$TARGET" ]; then
        echo "TARGET not specified" 1>&2
        echo "TARGET not specified" >> "$LOG_FILE" 2>&1
        exit 1
    fi

    if [ -z "$EFI" ]; then
        echo "EFI not specified" 1>&2
        echo "EFI not specified" >> "$LOG_FILE" 2>&1
        exit 1
    fi

    if [ -z "$SWAP" ]; then
        echo "SWAP not specified" 1>&2
        echo "SWAP not specified" >> "$LOG_FILE" 2>&1
        exit 1
    fi

    if [ -z "$ROOT" ]; then
        echo "ROOT not specified" 1>&2
        echo "ROOT not specified" >> "$LOG_FILE" 2>&1
        exit 1
    fi
}

test_block_devices () {
    if [ ! -b "$TARGET" ]; then
        echo "TARGET is not a valid block device" 1>&2
        echo "TARGET is not a valid block device" >> "$LOG_FILE" 2>&1
        exit 1
    fi

    if [ ! -b "$EFI" ]; then
        echo "EFI is not a valid block device" 1>&2
        echo "EFI is not a valid block device" >> "$LOG_FILE" 2>&1
        exit 1
    fi

    if [ ! -b "$SWAP" ]; then
        echo "SWAP is not a valid block device" 1>&2
        echo "SWAP is not a valid block device" >> "$LOG_FILE" 2>&1
        exit 1
    fi
}

test_filesystems_types () {
    get_filesystem_details

    if [ "$EFI_TYPE" != "vfat" ]; then
        echo "EFI is not a EFI System Partition" 1>&2
        echo "EFI is not a EFI System Partition" >> "$LOG_FILE" 2>&1
        exit 1
    fi

    if [ "$SWAP_TYPE" != "swap" ]; then
        echo "SWAP is not a swap Partition" 1>&2
        echo "SWAP is not a swap Partition" >> "$LOG_FILE" 2>&1
        exit 1
    fi
}

test_debootstrap () {
    debootstrap --version > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo "SteamOS debootstrap not installed. Please install from" 1>&2
        echo "http://repo.steampowered.com/steamos/pool/main/d/debootstrap/debootstrap_1.0.54.steamos+bsos6_all.deb" 1>&2
        echo "SteamOS debootstrap not installed. Please install from" >> "$LOG_FILE" 2>&1
        echo "http://repo.steampowered.com/steamos/pool/main/d/debootstrap/debootstrap_1.0.54.steamos+bsos6_all.deb" >> "$LOG_FILE" 2>&1
        exit 1
    fi

    version="$(debootstrap --version)"

    if [ "${version#*steamos}" = "$version" ]; then
        echo "Debootstrap must be installed from SteamOS repo. Please remove the current debootstrap and install from" 1>&2
        echo "http://repo.steampowered.com/steamos/pool/main/d/debootstrap/debootstrap_1.0.54.steamos+bsos6_all.deb" 1>&2
        echo "Debootstrap must be installed from SteamOS repo. Please remove the current debootstrap and install from" >> "$LOG_FILE" 2>&1
        echo "http://repo.steampowered.com/steamos/pool/main/d/debootstrap/debootstrap_1.0.54.steamos+bsos6_all.deb" >> "$LOG_FILE" 2>&1
        exit 1
    fi
}

################################################################################
# Heplers ######################################################################
################################################################################

get_filesystem_details () {
    TARGET_UUID="$(blkid | grep "$TARGET" | awk '{ len=length($2) - 7; print substr($2, 7, len) }')"
    EFI_UUID="$(blkid | grep "$EFI" | awk '{ len=length($2) - 7; print substr($2, 7, len) }')"
    SWAP_UUID="$(blkid | grep "$SWAP" | awk '{ len=length($2) - 7; print substr($2, 7, len) }')"

    TARGET_TYPE="$(blkid | grep "$TARGET" | awk '{ len=length($3) - 7; print substr($3, 7, len) }')"
    EFI_TYPE="$(blkid | grep "$EFI" | awk '{ len=length($3) - 7; print substr($3, 7, len) }')"
    SWAP_TYPE="$(blkid | grep "$SWAP" | awk '{ len=length($3) - 7; print substr($3, 7, len) }')"
}

################################################################################
# Installations Steps ##########################################################
################################################################################

debootstrap_install () {
    test_debootstrap
    test_block_devices
    test_filesystems_types

    echo "=== Formatting $TARGET"
    echo "=== Formatting $TARGET" >> "$LOG_FILE"

    mkfs.ext4 "$TARGET" >> "$LOG_FILE" 2>&1

    mkdir -p "$ROOT" >> "$LOG_FILE" 2>&1

    get_filesystem_details

    echo "=== Mounting $TARGET"
    echo "=== Mounting $TARGET" >> "$LOG_FILE"

    mount "$TARGET" "$ROOT" >> "$LOG_FILE" 2>&1

    echo "=== Installing base system"
    echo "=== Installing base system" >> "$LOG_FILE"

    debootstrap --arch amd64 alchemist "$ROOT" http://repo.steampowered.com/steamos >> "$LOG_FILE" 2>&1

    if [ $? -ne 0 ]; then
        echo "Error installing base system" 1>&2
        echo "Error installing base system" >> "$LOG_FILE" 2>&1
        exit 1
    fi
}

prepare_chroot () {
    echo "=== Preparing Chroot"
    echo "=== Preparing Chroot" >> "$LOG_FILE"

    mkdir -p "$ROOT/boot/efi" >> "$LOG_FILE" 2>&1

    mount "$EFI" "$ROOT/boot/efi" >> "$LOG_FILE" 2>&1

    mount --bind /dev "$ROOT/dev" >> "$LOG_FILE" 2>&1
    mount --bind /sys "$ROOT/sys" >> "$LOG_FILE" 2>&1
    mount --bind /dev/pts "$ROOT/dev/pts" >> "$LOG_FILE" 2>&1
    mount -t proc none "$ROOT/proc" >> "$LOG_FILE" 2>&1
}

setup_preseed () {
    cp "preseed" "$ROOT/root/preseed"
    cp "hacks" "$ROOT/root/hacks"

    chmod +x "$ROOT/root/hacks"

    chroot "$ROOT" /bin/sh -c "debconf-set-selections root/preseed" >> "$LOG_FILE" 2>&1
    chroot "$ROOT" /bin/sh -c "/root/hacks" >> "$LOG_FILE" 2>&1
}

configure_base () {
    chroot "$ROOT" /bin/sh -c "cat /proc/mounts > /etc/mtab"

    echo "=== Configuring Apt"
    echo "=== Configuring Apt" >> "$LOG_FILE"

## Generate the sources.list
    cat - > "$ROOT/etc/apt/sources.list" << EOF
deb http://repo.steampowered.com/steamos alchemist main contrib non-free

deb http://ftp.debian.org/debian stable main contrib non-free
deb http://ftp.debian.org/debian wheezy-updates main contrib non-free
deb http://security.debian.org wheezy/updates main contrib non-free

#deb http://ftp.debian.org/debian wheezy-backports main contrib non-free
EOF

## Generate apt preferences
    cat - > "$ROOT/etc/apt/preferences" << EOF
Package: *
Pin: release l=SteamOS
Pin-Priority: 500

Package: *
Pin: release l=Steam
Pin-Priority: 500

Package: *
Pin: release l=Debian
Pin-Priority: 100

Package: *
Pin: release l=Debian Backports
Pin-Priority: 50

Package: *
Pin: release l=Debian-Security
Pin-Priority: 100
EOF

    echo "=== Configuring DNS"
    echo "=== Configuring DNS" >> "$LOG_FILE"

    ## Configure DNS
    echo "" > "$ROOT/etc/resolv.conf"
    [ ! -z "$DNS1" ] && echo "nameserver $DNS1" >> "$ROOT/etc/resolv.conf"
    [ ! -z "$DNS2" ] && echo "nameserver $DNS2" >> "$ROOT/etc/resolv.conf"
    [ ! -z "$DNS3" ] && echo "nameserver $DNS3" >> "$ROOT/etc/resolv.conf"

    echo "=== Configuring Base System"
    echo "=== Configuring Base System" >> "$LOG_FILE"

    chroot "$ROOT" /bin/sh -c "apt-get update" >> "$LOG_FILE" 2>&1
    chroot "$ROOT" /bin/sh -c "apt-get install valve-archive-keyring steamos-beta-repo --force-yes --allow-unauthenticated" >> "$LOG_FILE" 2>&1
    chroot "$ROOT" /bin/sh -c "apt-get update && apt-get upgrade --force-yes --allow-unauthenticated" >> "$LOG_FILE" 2>&1

    chroot "$ROOT" /bin/sh -c "apt-get install locales locales-all --yes" >> "$LOG_FILE" 2>&1

    chroot "$ROOT" /bin/sh -c "update-locale $LOCALE"

    chroot "$ROOT" /bin/sh -c "apt-get install console-setup --yes" >> "$LOG_FILE" 2>&1

    echo "$TIMEZONE" > "$ROOT/etc/timezone"
    chroot "$ROOT" /bin/sh -c "dpkg-reconfigure -f noninteractive tzdata" >> "$LOG_FILE" 2>&1

    chroot "$ROOT" /bin/sh -c "apt-get install acpi acpi-support-base acpid laptop-detect discover pciutils usbutils openssh-client openssh-server --yes" >> "$LOG_FILE" 2>&1
}

kernel_install () {
    echo "=== Installing Kernel"
    echo "=== Installing Kernel" >> "$LOG_FILE"
    chroot "$ROOT" /bin/sh -c "apt-get install linux-image-amd64 firmware-linux-free firmware-linux-nonfree firmware-realtek firmware-ralink firmware-linux --yes" >> "$LOG_FILE" 2>&1

    echo "=== Installing GRUB"
    echo "=== Installing GRUB" >> "$LOG_FILE"
    chroot "$ROOT" /bin/sh -c "apt-get install grub-efi-amd64 --yes" >> "$LOG_FILE" 2>&1

    echo "grub"

    echo "=== Installing PLYMOUTH"
    echo "=== Installing PLYMOUTH" >> "$LOG_FILE"
    chroot "$ROOT" /bin/sh -c "apt-get install plymouth plymouth-drm plymouth-themes-steamos --yes" >> "$LOG_FILE" 2>&1

    chroot "$ROOT" /bin/sh -c "plymouth-set-default-theme -R steamos" >> "$LOG_FILE" 2>&1
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*$/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' "$ROOT/etc/default/grub"
    echo "GRUB_BACKGROUND=/usr/share/plymouth/themes/steamos/steam.png" >> "$ROOT/etc/default/grub"
    sed -i 's/#GRUB_GFXMODE=640x480/GRUB_GFXMODE=1280x800-24/' "$ROOT/etc/default/grub"
    sed -i 's/GRUB_DISTRIBUTION=.*$/GRUB_DISTRIBUTION=SteamOS/' "$ROOT/etc/default/grub"

    chroot "$ROOT" /bin/sh -c "update-grub" >> "$LOG_FILE" 2>&1

    echo "=== Configuring /etc/fstab"
    echo "=== Configuring /etc/fstab" >> "$LOG_FILE"

    cat - > "$ROOT/etc/fstab" << EOF
UUID=$TARGET_UUID / $TARGET_TYPE errors=remount-ro 0 1
UUID=$EFI_UUID /boot/efi vfat defaults 0 2
UUID=$SWAP_UUID none swap sw 0 0
EOF

    echo "$HOSTNAME" > "$ROOT/etc/hostname"
    sed -i "1a\
127.0.1.1 $HOSTNAME" "$ROOT/etc/hosts"

}

desktop_install () {
    echo "=== Installing the Desktop"
    echo "=== Installing the Desktop" >> "$LOG_FILE"

    chroot "$ROOT" /bin/sh -c "apt-get install task-desktop valve-wallpapers lightdm --yes" >> "$LOG_FILE" 2>&1
    echo "/usr/sbin/lightdm" > "$ROOT/etc/X11/default-display-manager"
}

remount_root () {
    get_filesystem_details

    echo "=== Mounting $TARGET"
    echo "=== Mounting $TARGET" >> "$LOG_FILE"

    mount "$TARGET" "$ROOT" >> "$LOG_FILE" 2>&1
}

testing () {
    echo "=== Installing Steam"
    echo "=== Installing Steam" >> "$LOG_FILE"

    chroot "$ROOT" /bin/sh -c "dpkg --add-architecture i386" >> "$LOG_FILE" 2>&1
    chroot "$ROOT" /bin/sh -c "apt-get update" >> "$LOG_FILE" 2>&1
    chroot "$ROOT" /bin/sh -c "apt-get install libc6:i386 libgl1-mesa-dri:i386 libgl1-mesa-glx:i386 steamos-modeswitch-inhibitor:i386 steam:i386 libtxc-dxtn-s2tc0:i386 libgl1-fglrx-glx:i386 --yes" >> "$LOG_FILE" 2>&1
}

testing2 () {
    chroot "$ROOT" /bin/sh -c "apt-get install libgl1-nvidia-glx:i386 nvidia-vdpau-driver:i386 --yes" >> "$LOG_FILE" 2>&1
}

main () {
    # todo: test if sudo
    # todo: default_config + current config
    # test_config
    # debootstrap_install
    remount_root # for testing only
    prepare_chroot
    setup_preseed
    # configure_base
    # kernel_install
    # desktop_install
    testing
    testing2
}

main ${1+"$@"}
