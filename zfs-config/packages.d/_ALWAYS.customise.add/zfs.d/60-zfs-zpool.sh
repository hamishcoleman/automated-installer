#
# Create the initial zpool
#

if [ -z "$CONFIG_POOL" ]; then
    export CONFIG_POOL=tank
fi

. $ZFS_POOL_SCRIPT
