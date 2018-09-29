#
# Create a regular user
#

# Create one specific user - intended for the interactive installation of
# user workstations.  This user is not given sudo access here.
if [ -n "$CONFIG_USER" ]; then
    echo "Creating user: $CONFIG_USER"
    useradd -m "$CONFIG_USER" -s /bin/bash -c "$CONFIG_USER_FN"
    echo -e "$CONFIG_USER:$CONFIG_USER_PW" | chpasswd
fi

# Create users for any authorized_keys shipped with the ramdisk builder.
# This is intended for admin access for post-install configuration management
# tools and for any IT team users.  Therefore, these users need to be given
# sudo access.  To assist with not hardcoding passwords, they are also
# given NOPASSWD sudo access - this can be removed or adjusted by the
# post-install configuration management.
#
groupadd --system sudonopw
echo "# This file created by the installer scripts" >/etc/sudoers.d/sudonopw
echo "%sudonopw ALL=(ALL:ALL) NOPASSWD: ALL" >>/etc/sudoers.d/sudonopw

for keyfile in ~root/authorized_keys/*.pub; do
    if [ ! -r "$keyfile" ]; then
        continue
    fi

    BN=$(basename "$keyfile" .pub)

    echo "Creating user with key: $BN"
    useradd -m "$BN" -s /bin/bash -G sudo,sudonopw

    SSHDIR="/home/$BN/.ssh"
    mkdir -p "$SSHDIR"
    cp "$keyfile" "$SSHDIR/authorized_keys"
    chown -R "$BN:$BN" "$SSHDIR"
    chmod -R go-wx "$SSHDIR"
    chmod go= "$SSHDIR"

    # TODO
    # - configure ssh to turn off password login!
done

# TODO:
# populate the systemwide known hosts file!
