#
# Copy some scripts into the buildroot and setup to execute them in a chroot
#

# TODO
# - make this phase more generic (it is a little hacky)
mkdir /mnt/installer
cp -a /installer/runparts.d/inchroot /mnt/installer/runparts.d
cp -a /installer/installer /mnt/installer

mount -t devtmpfs none /mnt/dev
mount -t devpts none /mnt/dev/pts
mount -t proc none /mnt/proc
mount -t sysfs none /mnt/sys

S=0
script_prefix=inchroot chroot /mnt /installer/installer || S=$?

if [ "$S" -ne 0 ]; then
    echo "ERROR: something in the chroot exited with an error ($S)"
    false
fi

# Only clean up if we dont exit in the error message above - that allows
# inspection to be done by the user if needed.
umount /mnt/dev/pts
umount /mnt/dev
umount /mnt/proc
umount /mnt/sys

# Remove our installer script files from the installed system
rm -rf /mnt/installer

# TODO
# - copy any /zfs.log file from the ramdisk into the installed system?
