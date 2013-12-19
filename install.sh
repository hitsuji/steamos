#!/bin/sh

## Include user configuration
GRUB=
TARGET=
HOME=
EFI=
MBR=
SWAP=
ROOT=
SKIP_NVIDIA=
DNS1="8.8.8.8" ## default to google
DNS2="8.8.4.4" ## default to google
DNS3=
LOCALE="LANG=en_US.UTF-8 LANGUAGE=en_US:en" ## default to US
TIMEZONE="Etc/UTC"                          ## default to UTC
HOSTNAME="steamos"                          ## default to steamos
USERNAME=
PASSWORD=

. ./config

LOG_FILE="./install.log"
#LOG_FILE="./install-$(date "+%y-%m-%d--%H-%M-%S").log"


## List of packages selected in apt
APT_VALVE_REPO="valve-archive-keyring steamos-beta-repo"
APT_LOCALES="locales locales-all"
APT_CONSOLE="console-setup"
APT_BASE_UTILS="acpi acpi-support-base acpid laptop-detect discover pciutils usbutils openssh-client openssh-server bash-completion command-not-found"
APT_KERNEL="linux-image-amd64 firmware-linux-free firmware-linux-nonfree firmware-realtek firmware-ralink firmware-linux"
APT_GRUB_EFI="grub-efi-amd64"
APT_GRUB_BIOS="grub-pc"
APT_PLYMOUTH="plymouth plymouth-drm plymouth-themes-steamos"
APT_DESKTOP="task-desktop valve-wallpapers lightdm"
APT_STEAM="libc6:i386 libgl1-mesa-dri:i386 libgl1-mesa-glx:i386 steamos-modeswitch-inhibitor:i386 steam:i386 libtxc-dxtn-s2tc0:i386 libgl1-fglrx-glx:i386"
APT_NVIDIA="libgl1-nvidia-glx:i386 nvidia-vdpau-driver:i386"
APT_STEAMOS="steamos-base-files steamos-modeswitch-inhibitor steamos-autoupdate" ##steam-launcher


################################################################################
## Tests #######################################################################
################################################################################

test_config () {
    ## GRUB
    if [ -z "$GRUB" ]; then
        stderr "GRUB option not set"
    fi

    if ! ([ "$GRUB" = "BIOS" ] || [ "$GRUB" = "UEFI" ]); then
        stderr "GRUB option must be either BIOS or UEFI"
        exit 1
    fi

    ## TARGET
    if [ -z "$TARGET" ]; then
        stderr "TARGET option not set"
        exit 1
    fi

    if [ ! -b "$TARGET" ]; then
        stderr "TARGET is not a valid block device"
        exit 1
    fi

    if [ "$GRUB" = "UEFI" ]; then
        ## EFI
        if [ -z "$EFI" ]; then
            stderr "EFI option not set"
            exit 1
        fi

        if [ ! -b "$EFI" ]; then
            stderr "EFI is not a valid block device"
            exit 1
        fi
    fi

    if [ "$GRUB" = "BIOS" ]; then
        ## MBR
        if [ -z "$MBR" ]; then
            stderr "MBR option not set"
            exit 1
        fi

        if [ ! -b "$MBR" ]; then
            stderr "MBR is not a valid block device"
            exit 1
        fi
    fi

    ## SWAP
    if [ -z "$SWAP" ]; then
        stderr "SWAP option not set"
        exit 1
    fi

    if [ ! -b "$SWAP" ]; then
        stderr "SWAP is not a valid block device"
        exit 1
    fi

    ## ROOT
    if [ -z "$ROOT" ]; then
        stderr "ROOT option not set"
        exit 1
    fi

    ## USERNAME
    if [ -z "$USERNAME" ]; then
        stderr "USERNAME option not set"
        exit 1
    fi

    ## PASSWORD
    if [ -z "$PASSWORD" ]; then
        stderr "PASSWORD option not set"
        exit 1
    fi
}

test_filesystems_types () {
    get_filesystem_details

    if [ "$GRUB" = "UEFI" ]; then
        if [ "$EFI_TYPE" != "vfat" ]; then
            stderr "EFI is not a EFI System Partition"
            exit 1
        fi
    fi

    if [ "$SWAP_TYPE" != "swap" ]; then
        stderr "SWAP is not a swap Partition"
        exit 1
    fi
}

test_debootstrap () {
    debootstrap --version > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        stdout "=== Installing Debootstrap"

        wget -O "/tmp/debootstrap.deb" "http://repo.steampowered.com/steamos/pool/main/d/debootstrap/debootstrap_1.0.54.steamos+bsos6_all.deb"  >> "$LOG_FILE" 2>&1
        apt-get install "/tmp/debootstrap.deb"  >> "$LOG_FILE" 2>&1
        rm -f "/tmp/debootstrap.deb"
    fi

    version="$(debootstrap --version)"

    if [ "${version#*steamos}" = "$version" ]; then
        stdout "=== Replacing Debootstrap"

        apt-get remove debootstrap

        wget -O "/tmp/debootstrap.deb" "http://repo.steampowered.com/steamos/pool/main/d/debootstrap/debootstrap_1.0.54.steamos+bsos6_all.deb"  >> "$LOG_FILE" 2>&1
        apt-get install "/tmp/debootstrap.deb"  >> "$LOG_FILE" 2>&1
        rm -f "/tmp/debootstrap.deb"
        exit 1
    fi
}

################################################################################
# Heplers ######################################################################
################################################################################

begin_logging () {
    echo "SteamOS Deboostrap Install" > "$LOG_FILE" 2>&1
    echo "" >> "$LOG_FILE" 2>&1
}

get_filesystem_details () {
    TARGET_UUID="$(blkid | grep "$TARGET" | awk '{ len=length($2) - 7; print substr($2, 7, len) }')"
    SWAP_UUID="$(blkid | grep "$SWAP" | awk '{ len=length($2) - 7; print substr($2, 7, len) }')"

    TARGET_TYPE="$(blkid | grep "$TARGET" | awk '{ len=length($3) - 7; print substr($3, 7, len) }')"
    SWAP_TYPE="$(blkid | grep "$SWAP" | awk '{ len=length($3) - 7; print substr($3, 7, len) }')"

    if [ "$GRUB" = "UEFI" ]; then
        EFI_UUID="$(blkid | grep "$EFI" | awk '{ len=length($2) - 7; print substr($2, 7, len) }')"
        EFI_TYPE="$(blkid | grep "$EFI" | awk '{ len=length($3) - 7; print substr($3, 7, len) }')"
    fi

    if [ ! -z "$HOME" ]; then
        HOME_UUID="$(blkid | grep "$HOME" | awk '{ len=length($2) - 7; print substr($2, 7, len) }')"
        HOME_TYPE="$(blkid | grep "$HOME" | awk '{ len=length($3) - 7; print substr($3, 7, len) }')"
    fi
}

chroot_install () {
    chroot "$ROOT" /bin/sh -c "apt-get install $1 --yes" >> "$LOG_FILE" 2>&1
}

stdout () {
    echo "$1"
    echo "$1" >> "$LOG_FILE"
}

stderr () {
    echo "$1" 1>&2
    echo "$1" >> "$LOG_FILE" 2>&1
}

remount_root () {
    get_filesystem_details

    stdout "=== Mounting $TARGET"

    mount "$TARGET" "$ROOT" >> "$LOG_FILE" 2>&1

    if [ ! -z "$HOME" ]; then
        stdout "=== Mounting $HOME"
        mount "$HOME" "$ROOT/home" >> "$LOG_FILE" 2>&1
    fi
}

dev_tools () {
    chroot_install "debconf-utils pastebinit"
}

################################################################################
# Installations Steps ##########################################################
################################################################################

debootstrap_install () {
    test_debootstrap
    test_filesystems_types

    stdout "=== Formatting $TARGET"

    mkfs.ext4 "$TARGET" >> "$LOG_FILE" 2>&1

    if [ ! -z "$HOME" ]; then
        stdout "=== Formatting $HOME"
        mkfs.ext4 "$HOME" >> "$LOG)FILE" 2>&1
    fi

    mkdir -p "$ROOT" >> "$LOG_FILE" 2>&1

    get_filesystem_details

    stdout "=== Mounting $TARGET"

    mount "$TARGET" "$ROOT" >> "$LOG_FILE" 2>&1

    if [ ! -z "$HOME" ]; then
        stdout "=== Mounting $HOME"
        mkdir "$ROOT/home" >> "$LOG_FILE" 2>&1
        mount "$HOME" "$ROOT/home" >> "$LOG_FILE" 2>&1
    fi

    stdout "=== Installing base system"

    debootstrap --arch amd64 alchemist "$ROOT" http://repo.steampowered.com/steamos >> "$LOG_FILE" 2>&1

    if [ $? -ne 0 ]; then
        stderr "stderr installing base system"
        exit 1
    fi
}

prepare_chroot () {
    stdout "=== Preparing Chroot"

    if [ "$GRUB" = "UEFI" ]; then
        mkdir -p "$ROOT/boot/efi" >> "$LOG_FILE" 2>&1
        mount "$EFI" "$ROOT/boot/efi" >> "$LOG_FILE" 2>&1
    fi

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

    stdout "=== Configuring Apt"

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

    stdout "=== Configuring DNS"

    echo "" > "$ROOT/etc/resolv.conf"
    [ ! -z "$DNS1" ] && echo "nameserver $DNS1" >> "$ROOT/etc/resolv.conf"
    [ ! -z "$DNS2" ] && echo "nameserver $DNS2" >> "$ROOT/etc/resolv.conf"
    [ ! -z "$DNS3" ] && echo "nameserver $DNS3" >> "$ROOT/etc/resolv.conf"

    stdout "=== Configuring Base System"

    chroot "$ROOT" /bin/sh -c "dpkg --add-architecture i386" >> "$LOG_FILE" 2>&1
    chroot "$ROOT" /bin/sh -c "apt-get update" >> "$LOG_FILE" 2>&1
    chroot_install "$APT_VALVE_REPO --force-yes --allow-unauthenticated"
    chroot "$ROOT" /bin/sh -c "apt-get update && apt-get upgrade --force-yes --allow-unauthenticated" >> "$LOG_FILE" 2>&1

    chroot_install "$APT_LOCALES"

    chroot "$ROOT" /bin/sh -c "update-locale $LOCALE"

    chroot_install "$APT_CONSOLE"

    echo "$TIMEZONE" > "$ROOT/etc/timezone"
    chroot "$ROOT" /bin/sh -c "dpkg-reconfigure -f noninteractive tzdata" >> "$LOG_FILE" 2>&1

    chroot_install "$APT_BASE_UTILS"
}

pre_download () {
    stdout "=== Downloading Packages"

    chroot_install "$APT_KERNEL $APT_GRUB_EFI $APT_GRUB_BIOS $APT_PLYMOUTH $APT_DESKTOP $APT_STEAM $APT_NVIDIA $APT_STEAMOS --download-only"
}

kernel_install () {
    stdout "=== Installing Kernel"

    chroot_install "$APT_KERNEL"

    stdout "=== Installing GRUB"

    if [ "$GRUB" = "UEFI" ]; then
        chroot_install "$APT_GRUB_EFI"
    elif [ "$GRUB" = "BIOS" ]; then
        chroot_install "$API_GRUB_BIOS"
    fi


    stdout "=== Installing PLYMOUTH"

    chroot_install "$APT_PLYMOUTH"

    chroot "$ROOT" /bin/sh -c "plymouth-set-default-theme -R steamos" >> "$LOG_FILE" 2>&1
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*$/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' "$ROOT/etc/default/grub"
    echo "GRUB_BACKGROUND=/usr/share/plymouth/themes/steamos/steam.png" >> "$ROOT/etc/default/grub"
    sed -i 's/#GRUB_GFXMODE=640x480/GRUB_GFXMODE=1280x800-24/' "$ROOT/etc/default/grub"
    sed -i 's/GRUB_DISTRIBUTION=.*$/GRUB_DISTRIBUTION=SteamOS/' "$ROOT/etc/default/grub"

    chroot "$ROOT" /bin/sh -c "update-grub" >> "$LOG_FILE" 2>&1

    if [ "$GRUB" = "UEFI" ]; then
        chroot "$ROOT" /bin/sh -c "grub-install" >> "$LOG_FILE" 2>&1
    elif [ "$GRUB" = "BIOS" ]; then
        chroot "$ROOT" /bin/sh -c "grub-install $MBR" >> "$LOG_FILE" 2>&1
    fi

    stdout "=== Configuring /etc/fstab"

    if [ "$GRUB" = "UEFI" ] && [ -z "$HOME" ]; then

        cat - > "$ROOT/etc/fstab" << EOF
UUID=$TARGET_UUID / ext4 errors=remount-ro 0 1
UUID=$EFI_UUID /boot/efi vfat defaults 0 2
UUID=$SWAP_UUID none swap sw 0 0
EOF

    elif [ "$GRUB" = "UEFI" ] && [ -n "$HOME" ]; then

        cat - > "$ROOT/etc/fstab" << EOF
UUID=$TARGET_UUID / ext4 errors=remount-ro 0 1
UUID=$EFI_UUID /boot/efi vfat defaults 0 2
UUID=$HOME_UUID /home defaults 0 0
UUID=$SWAP_UUID none swap sw 0 0
EOF

    elif [ "$GRUB" = "BIOS" ] && [ -z "$HOME" ]; then

        cat - > "$ROOT/etc/fstab" << EOF
UUID=$TARGET_UUID / ext4 errors=remount-ro 0 1
UUID=$SWAP_UUID none swap sw 0 0
EOF

    elif [ "$GRUB" = "BIOS" ] && [ -n "$HOME" ]; then

        cat - > "$ROOT/etc/fstab" << EOF
UUID=$TARGET_UUID / ext4 errors=remount-ro 0 1
UUID=$HOME_UUID /home defaults 0 0
UUID=$SWAP_UUID none swap sw 0 0
EOF

    fi

    echo "$HOSTNAME" > "$ROOT/etc/hostname"
    echo "127.0.1.1 $HOSTNAME" >> "$ROOT/etc/hosts"
}

desktop_install () {
    stdout "=== Installing the Desktop"

    chroot_install "$APT_DESKTOP"
    echo "/usr/sbin/lightdm" > "$ROOT/etc/X11/default-display-manager"

    stdout "=== Installing Steam"

    chroot_install "$APT_STEAM"

    if [ "$SKIP_NVIDIA" != "yes" ]; then
        stdout "=== Installing nVidia Drivers"
    fi

    chroot_install "$APT_NVIDIA"

    stdout "=== Installing SteamOS"

    chroot_install "$APT_STEAMOS"
}

main () {
    ## TODO: if sudo

    case "$1" in
        "all")
            begin_logging
            test_config
            debootstrap_install
            prepare_chroot
            setup_preseed
            configure_base
            kernel_install
            pre_download
            desktop_install
        ;;
        "devall")
            begin_logging
            test_config
            debootstrap_install
            prepare_chroot
            setup_preseed
            configure_base
            dev_tools
            kernel_install
            pre_download
            desktop_install
        ;;
        "devbase")
            begin_logging
            test_config
            debootstrap_install
            prepare_chroot
            setup_preseed
            configure_base
            dev_tools
        ;;
        "test")
            begin_logging
            test_config
            remount_root
            prepare_chroot
            setup_preseed
            testing
        ;;
    esac
}

main "${1+"$@"}"
