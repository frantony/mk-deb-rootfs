#!/bin/bash

set -e

if [ ! -e "$1" ]; then
	echo "usage:"
	echo "  stage3.sh <config>"
	exit 1
fi

set -x

source $1

if [ -z "$DLINUXTARZ" ]; then
	DLINUXTARZ=output/stage1/debian-${DEBRELEASE}-${DEBARCH}-latest.tar.gz
fi

DLINUXTARZ=$(realpath "$DLINUXTARZ")

LINUX_KERNEL=${LINUX_IMAGE}-${QEMU_ARCH}-${QEMU_MACHINE}

if [ -z "${QEMU_KERNEL}" ]; then
	QEMU_KERNEL=output/stage2/${LINUX_KERNEL}-latest
fi

E2IMAGE=output/stage3/linux-rootfs-${QEMU_ARCH}-${QEMU_MACHINE}.qcow2
E2MNT=ext2

DISK_SIZE=16G

for i in \
	${QEMU_KERNEL} \
	${DLINUXTARZ} \
	; do

	if [ ! -f "${i}" ]; then
		echo "can't find file '${i}'"
		exit 1
	fi
done


prepare_rootfs_image()
{
rm -rf ${E2MNT}
mkdir -p ${E2MNT}

tar -x -f ${DLINUXTARZ} -C ${E2MNT}

cat > ${E2MNT}/etc/apt/sources.list <<EOF
deb ${DEBMIRROR} ${DEBRELEASE} main contrib non-free
EOF

cat > ${E2MNT}/etc/network/interfaces.d/eth0 <<EOF
allow-hotplug eth0
iface eth0 inet dhcp
post-up /alter_debian_once 2>&1 >/dev/console
EOF

cat > ${E2MNT}/alter_debian_once <<EOF
#!/bin/bash -e

set -x

APT_GET_INSTALL="apt-get install -y --no-install-recommends --no-install-suggests"

DEBRELEASE="$DEBRELEASE"
EOF

if [ -n "$APTCACHE" ]; then
cat >> ${E2MNT}/alter_debian_once <<EOF
echo 'Acquire::http { Proxy "http://${APTCACHE}"; };' > /etc/apt/apt.conf.d/01proxy
EOF
fi

cat >> ${E2MNT}/alter_debian_once <<EOF
# Starting with v197 systemd/udev will automatically assign predictable,
# stable network interface names for all local Ethernet,
# WLAN and WWAN interfaces.
# see https://www.freedesktop.org/wiki/Software/systemd/PredictableNetworkInterfaceNames/
# Disable this feature
ln -s -f /dev/null /etc/systemd/network/99-default.link
EOF

cat >> ${E2MNT}/alter_debian_once <<EOF
apt-get update

INSTALL_PACKAGES=""

INSTALL_PACKAGES="\$INSTALL_PACKAGES openssh-server"
INSTALL_PACKAGES="\$INSTALL_PACKAGES python3"

\$APT_GET_INSTALL \$INSTALL_PACKAGES
EOF

if [ "${DEBARCH}" = "amd64" ]; then

	cat >> ${E2MNT}/alter_debian_once <<EOF
INSTALL_PACKAGES=""
INSTALL_PACKAGES="\$INSTALL_PACKAGES linux-image-amd64 grub-pc"
\$APT_GET_INSTALL \$INSTALL_PACKAGES

sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="quiet"$/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX=.*$/GRUB_CMDLINE_LINUX="console=ttyS0 rw net.ifnames=0 systemd.unified_cgroup_hierarchy=0"/' /etc/default/grub
sed -i 's/^#GRUB_TERMINAL=.*$/GRUB_TERMINAL="console serial"/' /etc/default/grub
sed -i 's/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=1/' /etc/default/grub

grub-install /dev/sda
update-grub
EOF

fi

cat >> ${E2MNT}/alter_debian_once <<EOF
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

if [ -f authorized_keys ]; then
	ROOTSSH=${E2MNT}/root/.ssh
	mkdir -p ${ROOTSSH}/
	cp authorized_keys ${ROOTSSH}/authorized_keys
	chmod 600 ${ROOTSSH}/authorized_keys
fi

cat >> ${E2MNT}/alter_debian_once <<EOF
rm -f /etc/apt/apt.conf.d/01proxy

dmesg

cat > /etc/network/interfaces.d/eth0 <<_EOF
allow-hotplug eth0
iface eth0 inet dhcp
_EOF

( rm -f -- "\$0" )

halt -p
EOF

chmod +x ${E2MNT}/alter_debian_once

mkdir -p $(dirname ${E2IMAGE})
virt-make-fs --partition --format=qcow2 --size=${DISK_SIZE} ${E2MNT} ${E2IMAGE}

rm -rf ${E2MNT}

}


prepare_rootfs_image

QEMU=qemu-system-${QEMU_ARCH}

if [ "$(uname -m)" = "x86_64" -a "${QEMU_ARCH}" = "x86_64" ]; then
	KVM="-enable-kvm"
else
	KVM=""
fi

${QEMU} $KVM -nodefaults \
	-M ${QEMU_MACHINE} \
	-cpu ${QEMU_CPU} ${QEMU_SMP} \
	-m ${QEMU_MEM} \
	${QEMU_BIOS} \
	-serial mon:stdio \
	-drive id=hd0,media=disk,if=none,format=qcow2,file=${E2IMAGE} \
		-device virtio-scsi-pci -device scsi-hd,drive=hd0 \
	-nographic \
	-nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22,hostfwd=tcp::6900-:5900 \
	-kernel "${QEMU_KERNEL}" \
	-append "${QEMU_APPEND}"

BNE2IMAGE=$(echo ${E2IMAGE} | sed "s/\.qcow2$//")

qemu-img convert -c -O qcow2 ${E2IMAGE} ${BNE2IMAGE}.shrunk.qcow2
virt-tar-out -a ${E2IMAGE} / - | gzip > ${BNE2IMAGE}.tar.gz
