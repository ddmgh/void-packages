#!/bin/sh
#
# Public Domain, 2009-2010 - Juan RP <xtraeme@gmail.com>
#
trap "echo; error_out $?" INT QUIT

[ "$(id -u)" -ne 0 ] && echo "root perms are required." && exit 1

ISOLINUX_ARGS="-b isolinux/isolinux.bin -c isolinux/boot.cat"
ISOLINUX_ARGS="$ISOLINUX_ARGS -boot-load-size 4 -no-emul-boot"
ISOLINUX_ARGS="$ISOLINUX_ARGS -boot-info-table"

CONFIG_FILE="$HOME/.xbps-mklive.conf"

#
# The following vars are overwritten by the config file.
#
PACKAGE_REPO="/storage/xbps/packages"
OUTPUT_FILE="$HOME/xbps-live-$(uname -m).iso"
ISO_VOLUME="XBPS GNU/Linux Live"
SYSLINUX_DATADIR="/usr/share/syslinux"
SPLASH_IMAGE=$HOME/splash.rle

if [ -f $CONFIG_FILE ]; then
	. $CONFIG_FILE
fi

if [ -z "$PACKAGE_LIST" ]; then
	PACKAGE_LIST="xbps-base-system xbps-casper"
else
	PACKAGE_LIST="xbps-base-system xbps-casper $PACKAGE_LIST"
fi
BUILD_TMPDIR=$(mktemp --tmpdir="$(pwd)" -d) || exit 1
BUILD_TMPDIR=$(readlink -f $BUILD_TMPDIR)
TEMP_ROOTFS="$BUILD_TMPDIR/casper/rootfs"
ISOLINUX_DIR="$BUILD_TMPDIR/isolinux"

info_msg()
{
	printf "\033[1m$@\n\033[m"
}

mount_pseudofs()
{
	for fs in sys proc dev; do
		if [ ! -d $TEMP_ROOTFS/$fs ]; then
			mkdir -p $TEMP_ROOTFS/$fs
		fi
		mount --bind /$fs $TEMP_ROOTFS/$fs || error_out
	done
}

umount_pseudofs()
{
	for fs in sys proc dev; do
		umount -f $TEMP_ROOTFS/$fs 2>&1 >/dev/null
	done
}

error_out()
{
	umount_pseudofs

	[ "$1" -ne 0 ] && echo "ERROR: stage mentioned above returned $1!"
	info_msg "Cleaning up $BUILD_TMPDIR..."
	rm -rf $BUILD_TMPDIR
	exit 1
}

write_etc_motd()
{
	cat >> "$TEMP_ROOTFS/etc/motd" <<_EOF
Welcome to the XBPS GNU/Linux Live system, you have been autologged in.
This user has full sudo(8) permissions without any password, be careful
executing commands through sudo(8).

To play with package management use the xbps-bin(8) and xbps-repo(8)
utilities. Please visit:

	http://xbps.nopcode.org/

For more information and/or documentation about using the X Binary
Package System. Enjoy it.

		Juan RP <xtraeme@gmail.com>

_EOF
}

write_default_isolinux_conf()
{
	local kver="$1"

	cat >> "$ISOLINUX_DIR/isolinux.cfg" << _EOF
DEFAULT vesamenu.c32
PROMPT 0
TIMEOUT 600
ONTIMEOUT c

MENU BACKGROUND $(basename $SPLASH_IMAGE)
MENU VSHIFT 5
MENU ROWS 20
MENU TABMSGROW 10
MENU TABMSG Press ENTER to boot or TAB to edit a menu entry
MENU AUTOBOOT BIOS default device boot in # second{,s}...
MENU TIMEOUTROW 12

MENU COLOR title        * #FF5255FF *
MENU COLOR border       * #00000000 #00000000 none
MENU COLOR sel          * #ffffffff #FF5255FF *

LABEL linux
MENU LABEL Boot XBPS GNU/Linux ${kver}
KERNEL /casper/vmlinuz
INITRD /casper/initrd.gz
APPEND boot=casper keymap=es locale=es_ES

LABEL linuxtoram
MENU LABEL Boot XBPS GNU/Linux ${kver} (toram)
KERNEL /casper/vmlinuz
INITRD /casper/initrd.gz
APPEND boot=casper toram keymap=es locale=es_ES

LABEL c
MENU LABEL Boot first HD found by the BIOS
LOCALBOOT 0x80
_EOF
}

[ -z "$PACKAGE_LIST" ] && error_out
[ -z "$OUTPUT_FILE" ] && error_out
[ -z "$ISO_VOLUME" ] && error_out
[ -z "$PACKAGE_REPO" ] && error_out

[ ! -d "$TEMP_ROOTFS/var/db/xbps" ] && mkdir -p "$TEMP_ROOTFS/var/db/xbps"

for _repo_ in ${PACKAGE_REPO}; do
	info_msg "Adding ${_repo_} package repository..."
	xbps-repo.static -r $TEMP_ROOTFS add ${_repo_}
	[ $? -ne 0 ] && error_out $?
done

if [ ! -f $SYSLINUX_DATADIR/isolinux.bin -o \
     ! -f $SYSLINUX_DATADIR/vesamenu.c32 ]; then
	echo "Missing required isolinux files in $SYSLINUX_DATADIR!"
	error_out
fi

[ ! -d "$ISOLINUX_DIR" ] && mkdir -p "$ISOLINUX_DIR"

if [ ! -f "$ISOLINUX_DIR/isolinux.bin" ]; then
	cp -f $SYSLINUX_DATADIR/isolinux.bin "$ISOLINUX_DIR"
fi

if [ ! -f "$ISOLINUX_DIR/isolinux.cfg" ]; then
	kernel_ver=$(xbps-repo.static -r $TEMP_ROOTFS show kernel|grep Version|awk '{print $2}')
	if [ -z "$kernel_ver" ]; then
		echo "Missing 'kernel' pkg in repository pool (xbps-repo)!"
		error_out
	fi
	write_default_isolinux_conf ${kernel_ver}
fi

[ ! -f "$SPLASH_IMAGE" ] && echo "Cannot find splash image!" && error_out 1

cp -f $SPLASH_IMAGE "$ISOLINUX_DIR"

if [ ! -f "$ISOLINUX_DIR/vesamenu.c32" ]; then
	cp -f $SYSLINUX_DATADIR/vesamenu.c32 "$ISOLINUX_DIR"
fi

mount_pseudofs

xbps_relver=$(xbps-bin.static -V)
xbps-uhelper.static cmpver ${xbps_relver} 20091222
if [ $? -eq 255 ]; then
	yesflag="-f"
	for _pkg_ in ${PACKAGE_LIST}; do
		info_msg "Installing ${_pkg_} package..."
		xbps-bin.static -r $TEMP_ROOTFS ${yesflag} install ${_pkg_}
		[ $? -ne 0 ] && error_out $?
	done
else
	yesflag="-y"
	xbps-bin.static -r $TEMP_ROOTFS ${yesflag} install ${PACKAGE_LIST}
	[ $? -ne 0 ] && error_out $?
fi
xbps-bin.static -r $TEMP_ROOTFS ${yesflag} autoupdate || error_out $?
xbps-bin.static -r $TEMP_ROOTFS ${yesflag} autoremove || error_out $?
xbps-bin.static -r $TEMP_ROOTFS ${yesflag} purge all || error_out $?
xbps-bin.static -r $TEMP_ROOTFS list > $BUILD_TMPDIR/packages.txt

info_msg "Creating /etc/motd..."
write_etc_motd

info_msg "Rebuilding and copying initramfs..."
# Set lzma compression for the initramfs, to save space.
sed -i -e "s|COMPRESSION_TYPE=gzip|COMPRESSION_TYPE=lzma|" \
	$TEMP_ROOTFS/etc/initramfs-tools/initramfs.conf
xbps-bin -r $TEMP_ROOTFS -f reconfigure kernel
[ $? -ne 0 ] && error_out $?
cp -f "$TEMP_ROOTFS/boot/initrd.img-${kernel_ver}" \
	"$BUILD_TMPDIR/casper/initrd.gz" || error_out $?
mkdir -p $TEMP_ROOTFS/cow

info_msg "Copying kernel binary..."
cp -f "$TEMP_ROOTFS/boot/vmlinuz-${kernel_ver}" \
	"$BUILD_TMPDIR/casper/vmlinuz" || error_out $?

info_msg "Cleaning up rootfs..."
rm -f $TEMP_ROOTFS/boot/initrd*
rm -f $TEMP_ROOTFS/boot/vmlinuz*

umount_pseudofs

info_msg "Building squashed root filesystem..."
mksquashfs "$TEMP_ROOTFS" "$BUILD_TMPDIR/casper/filesystem.squashfs" \
	-root-becomes / && \
	chmod 444 "$BUILD_TMPDIR/casper/filesystem.squashfs"
[ $? -ne 0 ] && error_out $?

info_msg "Removing temporary rootfs directory..."
rm -rf "$TEMP_ROOTFS" || error_out $?

info_msg "Creating sha256 checksums..."
cd $BUILD_TMPDIR
for f in $(find . -type f -print); do
	[ "$f" = "./sha256.txt" ] && continue
	printf "${f#.}\t$(xbps-uhelper.static digest $f)\n" \
		>> $BUILD_TMPDIR/sha256.txt
done

info_msg "Building ISO image..."
mkisofs -J -r -V "$ISO_VOLUME" -b isolinux/isolinux.bin \
	-c isolinux/boot.cat -no-emul-boot -boot-load-size 4 \
	-boot-info-table -o "$OUTPUT_FILE" "$BUILD_TMPDIR"
[ $? -ne 0 ] && error_out $?

info_msg "Removing temporary build directory..."
rm -rf "$BUILD_TMPDIR" || error_out $?

info_msg "Created $(readlink -f $OUTPUT_FILE) successfully."

exit 0
