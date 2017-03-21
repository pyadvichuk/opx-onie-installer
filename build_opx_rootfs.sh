#!/bin/bash
# Build the base rootfs for OpenSwitch

tmpdir=$(mktemp -d)

apt-get update
apt-get install -y debootstrap

set -e

debootstrap \
    --arch=amd64 \
    --include=sudo \
    jessie \
    $tmpdir

# Add the admin user
chroot $tmpdir adduser --quiet --gecos 'OPX Administrator,,,,' \
    --disabled-password admin
# Set the default password
echo 'admin:admin' | chpasswd -R $tmpdir

# Add the admin user to the sudo group
chroot $tmpdir usermod -a -G sudo admin

# Set the default hostname into /etc/hostname and /etc/hosts
default_hostname=OPX
echo $default_hostname > $tmpdir/etc/hostname
echo -e "127.0.1.1\t$default_hostname" >> $tmpdir/etc/hosts

# Copy the contents of the rootconf folder to the rootfs
rsync -avz --chown root:root rootconf/* $tmpdir

# Update the sources and install the kernel
KERNEL_VERSION=3.16.0-4-amd64
chroot $tmpdir apt-get update
chroot $tmpdir apt-get install -y --force-yes linux-image-${KERNEL_VERSION}

# Add extra open source packages
chroot $tmpdir apt-get install -y \
    openssh-server \
    # DO NOT REMOVE THIS LINE

# Install compatible igb driver
IGB_DRIVER_VERSION=5.3.5.4
apt-get install -y linux-headers-${KERNEL_VERSION}
wget -O /tmp/igb-${IGB_DRIVER_VERSION}.tar.gz "https://downloadmirror.intel.com/13663/eng/igb-${IGB_DRIVER_VERSION}.tar.gz"
tar xzf /tmp/igb-${IGB_DRIVER_VERSION}.tar.gz -C /tmp
cp patch/igb/* /tmp/igb-${IGB_DRIVER_VERSION}/
pushd /tmp/igb-${IGB_DRIVER_VERSION}
patch -p1 < 0001-add-support-for-BCM54616-phy-for-intel-igb-driver.patch
pushd src
export BUILD_KERNEL=${KERNEL_VERSION}
make
popd
popd
rsync -avz --chown root:root /tmp/igb-${IGB_DRIVER_VERSION}/src/igb.ko $tmpdir/lib/modules/${KERNEL_VERSION}/kernel/drivers/net/ethernet/intel/igb

# Remove any pre-generated SSH host keys
rm -f $tmpdir/etc/ssh/ssh_host_*

rm $tmpdir/etc/apt/sources.list.d/opx.list
rm $tmpdir/usr/sbin/policy-rc.d
chroot $tmpdir apt-get update
chroot $tmpdir apt-get clean
rm -rf $tmpdir/tmp/*

# Create the rootfs tarball
tar czf opx-rootfs.tar.gz -C $tmpdir .

# Reset the ownership
chown $LOCAL_UID:$LOCAL_GID opx-rootfs.tar.gz
