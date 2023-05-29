#!/bin/bash

set -e

if [ ! -e "$1" ]; then
	echo "usage:"
	echo "  stage2.sh <config>"
	exit 1
fi

set -x

source $1

if [ -z "${NCPU}" ]; then
	NCPU=$(nproc)
fi

LV=5.10.180
L=linux-${LV}
A=${L}.tar.xz
OUTPUT=$(pwd)/output/stage2

SUFFIX="-$(date +'%Y%m%d%H%M')"

config_debian_defaults()
{
	O=$1

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

	${SCRIPTS_CONFIG} -e IKCONFIG
	${SCRIPTS_CONFIG} -e IKCONFIG_PROC

	${SCRIPTS_CONFIG} -e WIREGUARD
}

config_mips64r2()
{
	O=$1

	SCRIPTS_CONFIG="./scripts/config --file ${O}/.config"

	${SCRIPTS_CONFIG} -e CPU_MIPS64_R2
	${SCRIPTS_CONFIG} -e MIPS_O32_FP64_SUPPORT
	${SCRIPTS_CONFIG} -e 64BIT
	${SCRIPTS_CONFIG} -e MIPS32_O32
	${SCRIPTS_CONFIG} -e MIPS32_N32
}

build_kernel()
{
	LINUX_KERNEL=$1
	DEFCONFIG=$2
	EXTRACONFIG=$3

	O=${OUTPUT}/${LINUX_KERNEL}
	make O=${O} ${DEFCONFIG}

	config_debian_defaults ${O}
	if [ -n "$EXTRACONFIG" ]; then
		$EXTRACONFIG ${O}
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

		PREFNAME=${BASENAME}-${QEMU_ARCH}-${QEMU_MACHINE}
		TARGET=${OUTPUT}/${PREFNAME}${SUFFIX}
		cp ${O}/${ORIGNAME} ${TARGET}
		ln -s -r -f -v ${TARGET} ${OUTPUT}/${PREFNAME}-latest
	}

	copy_one ${LINUX_IMAGE_PATH}/${LINUX_IMAGE}
	copy_one .config config
}

mkdir -p src

if [ ! -e src/${A} ]; then
	( cd src && wget -c https://cdn.kernel.org/pub/linux/kernel/v5.x/${A} )
fi

if [ ! -d src/${L} ]; then
	( cd src && tar vfx ${A} )
fi

cd src/${L}

export ARCH=${LINUX_ARCH}
export CROSS_COMPILE=${LINUX_CROSS_COMPILE}

make mrproper

LINUX_KERNEL=${LINUX_IMAGE}-${QEMU_ARCH}-${QEMU_MACHINE}

if [ ! -f "output/stage2/${LINUX_KERNEL}-latest" ]; then
	case "${LINUX_KERNEL}" in
	Image.gz-aarch64-virt)
		build_kernel "${LINUX_KERNEL}" "defconfig"
		;;
	vmlinux-mipsel-malta)
		build_kernel "${LINUX_KERNEL}" "malta_defconfig"
		;;
	vmlinux-mips64el-malta)
		build_kernel "${LINUX_KERNEL}" "malta_defconfig" config_mips64r2
		;;
	bzImage-x86_64-q35)
		build_kernel "${LINUX_KERNEL}" "x86_64_defconfig"
		;;
	*)
		echo "ERROR: unknown linux kernel"
		exit 1
		;;
	esac
fi
