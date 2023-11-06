#!/bin/bash

set -e

if [ ! -e "$1" ]; then
	echo "usage:"
	echo "  run-qemu.sh <config> <drive-image-file>"
	exit 1
fi

set -x

source $1

E2IMAGE=$2

if [ -z "${QEMU_KERNEL}" ]; then
	LINUX_KERNEL=${LINUX_IMAGE}-${QEMU_ARCH}-${QEMU_MACHINE}
	QEMU_KERNEL=output/stage2/${LINUX_KERNEL}-latest
fi

for i in \
	${QEMU_KERNEL} \
	${E2IMAGE} \
	; do

	if [ ! -f "${i}" ]; then
		echo "can't find file '${i}'"
		exit 1
	fi
done


QEMU=qemu-system-${QEMU_ARCH}

KVM=""
if [ "$(uname -m)" = "x86_64" -a "${QEMU_ARCH}" = "x86_64" ]; then
	grep -E -w 'vmx|svm' /proc/cpuinfo >/dev/null && KVM="-enable-kvm"
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
	\
	-device virtio-net-pci,netdev=network1 \
		-netdev user,id=network1,hostfwd=tcp::2222-:22,hostfwd=tcp::6900-:5900 \
	\
	-kernel "${QEMU_KERNEL}" \
	-append "${QEMU_APPEND}"