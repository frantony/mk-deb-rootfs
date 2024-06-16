#!/bin/bash

set -e

if [ ! -e "$1" ]; then
	echo "usage:"
	echo "  stage2.sh <config>"
	exit 1
fi

set -x

source lib $1

if [ -z "${NCPU}" ]; then
	NCPU=$(nproc)
fi

L=linux-${LV}
A=${L}.tar.xz
KERNELURL=https://cdn.kernel.org/pub/linux/kernel/${KERNELVDIR}/${A}

OUTPUT=$(pwd)/output/stage2

SUFFIX="-$(date +'%Y%m%d%H%M')"

case "${QEMU_ARCH}-${QEMU_MACHINE}" in
riscv64-virt)
	DEFCONFIG="defconfig"
	LINUX_CROSS_COMPILE=riscv64-linux-gnu-
	LINUX_IMAGE_PATH=arch/riscv/boot
	;;
aarch64-virt)
	DEFCONFIG="defconfig"
	LINUX_CROSS_COMPILE=aarch64-linux-gnu-
	LINUX_IMAGE_PATH=arch/arm64/boot
	;;
mips-malta|mipsel-malta|mips64el-malta)
	DEFCONFIG="malta_defconfig"
	LINUX_CROSS_COMPILE=mips-linux-gnu-
	LINUX_IMAGE_PATH=""
	;;
x86_64-q35)
	DEFCONFIG="x86_64_defconfig"
	LINUX_CROSS_COMPILE=x86_64-linux-gnu-
	LINUX_IMAGE_PATH=arch/x86_64/boot
	;;
*)
	echo "ERROR: unknown qemu target"
	exit 1
	;;
esac

mkdir -p src

if [ ! -e src/${A} ]; then
	( cd src && wget -c ${KERNELURL} )
fi

if [ ! -d src/${L} ]; then
	( cd src && tar vfx ${A} )
fi

cd src/${L}

export ARCH=${LINUX_ARCH}
export CROSS_COMPILE=${LINUX_CROSS_COMPILE}

make mrproper

LINUX_BUILDDIR=${LINUX_IMAGE}-${LV}-${QEMU_ARCH}-${QEMU_MACHINE}-builddir
O=${OUTPUT}/${LINUX_BUILDDIR}
make O=${O} -j${NCPU} ${DEFCONFIG}

SCRIPTS_CONFIG="./scripts/config --file ${O}/.config"

${SCRIPTS_CONFIG} -d MODULES
${SCRIPTS_CONFIG} -e FHANDLE
${SCRIPTS_CONFIG} -e CGROUPS
${SCRIPTS_CONFIG} -e AUTOFS4_FS
${SCRIPTS_CONFIG} -e BPF_SYSCALL -e CGROUP_BPF
${SCRIPTS_CONFIG} -e KEXEC
${SCRIPTS_CONFIG} --set-val NR_CPUS 4
${SCRIPTS_CONFIG} -e PAGE_SIZE_4KB

${SCRIPTS_CONFIG} -e VIRTIO_PCI
${SCRIPTS_CONFIG} -e VIRTIO_BLK
${SCRIPTS_CONFIG} -e VIRTIO_BLK_SCSI
${SCRIPTS_CONFIG} -e SCSI_LOWLEVEL
${SCRIPTS_CONFIG} -e SCSI_VIRTIO
${SCRIPTS_CONFIG} -e VIRTIO_NET
${SCRIPTS_CONFIG} -e HW_RANDOM_VIRTIO

${SCRIPTS_CONFIG} -d WIRELESS_EXT
${SCRIPTS_CONFIG} -d CFG80211
${SCRIPTS_CONFIG} -d LIB80211
${SCRIPTS_CONFIG} -d HOSTAP
${SCRIPTS_CONFIG} -d ATALK
${SCRIPTS_CONFIG} -d PHONET

${SCRIPTS_CONFIG} -e NET_9P
${SCRIPTS_CONFIG} -e NET_9P_VIRTIO
${SCRIPTS_CONFIG} -e 9P_FS

${SCRIPTS_CONFIG} -d MISC_FILESYSTEMS
${SCRIPTS_CONFIG} -d BTRFS_FS
${SCRIPTS_CONFIG} -d JFS_FS
${SCRIPTS_CONFIG} -d REISERFS_FS
${SCRIPTS_CONFIG} -d XFS_FS

${SCRIPTS_CONFIG} -e IKCONFIG
${SCRIPTS_CONFIG} -e IKCONFIG_PROC

${SCRIPTS_CONFIG} -e WIREGUARD

if [ "${QEMU_ARCH}" = "mipsel" -o "${QEMU_ARCH}" = "mips" ]; then
	${SCRIPTS_CONFIG} -e HIGHMEM
	if [ "${QEMU_ARCH}" = "mips" ]; then
		${SCRIPTS_CONFIG} -d CPU_LITTLE_ENDIAN
		${SCRIPTS_CONFIG} -e CPU_BIG_ENDIAN
	fi
fi

if [ "${QEMU_ARCH}" = "mips64el" ]; then
	${SCRIPTS_CONFIG} -e CPU_MIPS64_R2
	${SCRIPTS_CONFIG} -e MIPS_O32_FP64_SUPPORT
	${SCRIPTS_CONFIG} -e 64BIT
	${SCRIPTS_CONFIG} -e MIPS32_O32
	${SCRIPTS_CONFIG} -e MIPS32_N32
fi

## automatically answer defaults, see https://serverfault.com/a/116317
yes "" | make O=${O} oldconfig

time make O=${O} -j${NCPU} -s ${LINUX_IMAGE}

copy_one()
{
	ORIGNAME="$1"
	if [ -n "$2" ]; then
		BASENAME="$2"
	else
		BASENAME=$(basename "$ORIGNAME")
	fi

	PREFNAME=${BASENAME}-${LV}-${QEMU_ARCH}-${QEMU_MACHINE}
	TARGET=${OUTPUT}/${PREFNAME}${SUFFIX}
	cp ${O}/${ORIGNAME} ${TARGET}
	ln -s -r -f -v ${TARGET} ${OUTPUT}/${PREFNAME}-latest
}

copy_one ${LINUX_IMAGE_PATH}/${LINUX_IMAGE}
copy_one .config config
