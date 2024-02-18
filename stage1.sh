#!/bin/bash

set -e

if [ ! -e "$1" ]; then
	echo "usage:"
	echo "  stage1.sh <config>"
	exit 1
fi

set -x

source $1

source lib

if [ -z "${ROOTPASSWD}" ]; then
	ROOTPASSWD="changeit"
fi

SUFFIX="-$(date +'%Y%m%d%H%M')"

DEBRELARCH=debian-${DEBRELEASE}-${DEBARCH}
DEBROOTDIR=$(pwd)/${DEBRELARCH}

rm -rf $DEBROOTDIR

debootstrap --foreign --arch=${DEBARCH} \
		--no-check-gpg \
		--include=ifupdown \
		$DEBRELEASE $DEBROOTDIR ${ST1_DEBMIRROR}

DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
	LC_ALL=C LANGUAGE=C LANG=C \
	PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin \
	chroot $DEBROOTDIR /debootstrap/debootstrap --second-stage

echo "root:$ROOTPASSWD" | chroot $DEBROOTDIR chpasswd

echo "${DEBRELEASE}-${DEBARCH}" > ${DEBROOTDIR}/etc/hostname

#
# clean up
#
chroot ${DEBROOTDIR} apt-get clean
rm -rf ${DEBROOTDIR}/tmp/* ${DEBROOTDIR}/var/tmp/*

OUTPUT=$(pwd)/output/stage1
OTAR=${DEBRELARCH}${SUFFIX}.tar.gz

mkdir -p ${OUTPUT}
tar czf ${OUTPUT}/${OTAR} -C $DEBROOTDIR .
rm -rf $DEBROOTDIR

ln -s -r -f -v ${OUTPUT}/${OTAR} ${OUTPUT}/${DEBRELARCH}-latest.tar.gz
