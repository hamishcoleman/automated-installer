#
# Save the prefix for the zpool command
#

ZFS_POOL_SCRIPT=/tmp/zfs.zpool.script

# TODO
# - the "-d" option sets no features on the pool.  This probably creates
#   a strange looking pool.  However there is an incompatible feature being
#   set somewhere, causing creation to fail without it.  Fix this!

cat <<EOF >"$ZFS_POOL_SCRIPT"
# The command to use to assemble the ZFS filesystem.  For review and editing
zpool create -d -f \\
    -O atime=off \\
    -o ashift=12 \\
    -O canmount=off \\
    -O compression=lz4 \\
    -o feature@lz4_compress=enabled \\
    -O normalization=formD \\
    -O mountpoint=none \\
    -R /mnt \\
    \$CONFIG_POOL \\
EOF

echo "$ZFS_VDEVS" | while read -r line; do
    echo " $line \\" >>"$ZFS_POOL_SCRIPT"
done

echo >>"$ZFS_POOL_SCRIPT"

lsblk -n -d -e 11 -o "NAME,MODEL,SIZE,WWN" | while read -r line; do
    echo "# $line" >>"$ZFS_POOL_SCRIPT"
done
