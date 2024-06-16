#!/bin/sh

#
# I use scripts like this for turning minimal Debian system
# with just an SSH server into server/workstation.
#
# All setup actions are registered in the /etc git repo.
#

set -x
set -e

GIT_USER_EMAIL="you@example.com"
GIT_CONFIG_USER_NAME="Your Name"

#GIT_USER_EMAIL="antonynpavlov@gmail.com"
#GIT_CONFIG_USER_NAME="Antony Pavlov"

GIT_CONFIG_EDITOR=vim

DEBIAN_TUNER="debian-tuner"
INSTALLED_CURRENT_LIST="${DEBIAN_TUNER}/installed_current.list"

# hostname
HN="saga"

IS_SERVER="no"

#APTPROXY="http://192.168.1.???:3142"
APTPROXY=""
APTPROXYFILE=apt/apt.conf.d/01proxy

FN0=$(pwd)/$0

apt_force_ipv4()
{
	APTIPV4FILE=apt/apt.conf.d/99force-ipv4
	echo 'Acquire::ForceIPv4 "true";' > ${APTIPV4FILE}

	echo ${APTIPV4FILE}
}

apt_setup_proxy()
{
	if [ -n "${APTPROXY}" ]; then
		echo "Acquire::http { Proxy \"${APTPROXY}\"; };" > ${APTPROXYFILE}
	fi
}

apt_clear_proxy()
{
	if [ -n "${APTPROXY}" ]; then
		rm -f ${APTPROXYFILE}
	fi
}

initial_git_repo_setup()
{
	APTIPV4FILE=$(apt_force_ipv4)
	apt_setup_proxy

	apt update
	apt install -y git

	rm -f ${APTIPV4FILE}
	apt_clear_proxy

	if [ ! -d .git ]; then
		cat > .gitignore <<EOF
ld.so.cache
.pwd.lock
group-
gshadow-
passwd-
shadow-
subgid-
subuid-
ssh/ssh_host_dsa_key
ssh/ssh_host_dsa_key.pub
ssh/ssh_host_ecdsa_key
ssh/ssh_host_ecdsa_key.pub
ssh/ssh_host_ed25519_key
ssh/ssh_host_ed25519_key.pub
ssh/ssh_host_rsa_key
ssh/ssh_host_rsa_key.pub
.fstab
fake-hwclock.data
resolv.conf.bak
EOF
		git init .
		git add .gitignore
	fi

	git config user.email "$GIT_USER_EMAIL"
	git config user.name "$GIT_CONFIG_USER_NAME"
	git config core.editor "$GIT_CONFIG_EDITOR"

	git add .
	git commit -s -m "first boot; apt install -y git"

	APTIPV4FILE=$(apt_force_ipv4)
	apt_setup_proxy
	apt install -y aptitude
	rm -f ${APTIPV4FILE}
	apt_clear_proxy
	git add .
	git commit -s -m "apt install -y aptitude"

	mkdir -p $(dirname ${INSTALLED_CURRENT_LIST})
	LANG=C aptitude search -F "%c;;;%M;;;%p;;;%v" '.*' | grep -v "^v\|^p" | sed "s/;;;;;;/ - /;s/;;;/ /g" > ${INSTALLED_CURRENT_LIST}
	git add ${INSTALLED_CURRENT_LIST}
	git commit -s -F- <<EOF
${DEBIAN_TUNER}: introduce $(basename ${INSTALLED_CURRENT_LIST})

LANG=C aptitude search -F "%c;;;%M;;;%p;;;%v" '.*' | grep -v "^v\|^p" | sed "s/;;;;;;/ - /;s/;;;/ /g" > ${INSTALLED_CURRENT_LIST}
EOF

	cat <<EOF > .git/hooks/pre-commit
#!/bin/sh

set -e

cd $(git rev-parse --show-toplevel)

LANG=C aptitude search -F "%c;;;%M;;;%p;;;%v" '.*' | grep -v "^v\|^p" | sed "s/;;;;;;/ - /;s/;;;/ /g" > ${INSTALLED_CURRENT_LIST}
git add ${INSTALLED_CURRENT_LIST}
EOF
	chmod +x .git/hooks/pre-commit
}

backup_myself()
{
	FN0=$1

	TD=$(dirname ${INSTALLED_CURRENT_LIST})

	mkdir -p $TD
	TN=$(basename ${FN0})

	cp ${FN0} $TD/$TN
	git add $TD/$TN
	git commit -s --allow-empty -m "backup $TN" $TD/$TN
}

install_one_package()
{
	PKG=$1

	apt install -y $PKG
#	LANG=C aptitude search -F "%c;;;%M;;;%p;;;%v" '.*' | grep -v "^v\|^p" | sed "s/;;;;;;/ - /;s/;;;/ /g" > ${INSTALLED_CURRENT_LIST}
	git add .
	git commit -s --allow-empty -m "apt install -y $PKG"
}

install_hwinfo()
{
	install_one_package hwinfo

	# FIXME: mkdir -p ${debian_tuner}
	mkdir -p ${DEBIAN_TUNER}
	hwinfo --all --log=${DEBIAN_TUNER}/hwinfo.log
	git add ${DEBIAN_TUNER}/hwinfo.log
	git commit -s -F- <<EOF
${DEBIAN_TUNER}: add hwinfo.log

hwinfo --all --log=${DEBIAN_TUNER}/hwinfo.log
EOF
}

use_bookworm()
{
	cat <<EOF > apt/sources.list
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
#deb-src http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
#deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware

# bookworm-updates, to get updates before a point release is made;
# see https://www.debian.org/doc/manuals/debian-reference/ch02.en.html#_updates_and_backports
deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
#deb-src http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
EOF
	git commit -s -m "apt/sources.list: use deb.debian.org / bookworm" apt/sources.list
	apt update
}

set_hostname()
{
	HN=$1

	echo "${HN}" > hostname
	sed -i "s/^\(127.0.1.1\)\s\+.*$/\1\t${HN}/" hosts

	git commit -s -m "set hostname to ${HN}" hostname hosts

	hostname ${HN}
}


cd /etc/

FIRST_TIME=no
if [ ! -d .git ]; then
	FIRST_TIME=yes
fi

export DEBIAN_FRONTEND=noninteractive

if [ "$FIRST_TIME" = "yes" ]; then
	initial_git_repo_setup
fi

backup_myself "${FN0}"

if [ "$FIRST_TIME" = "yes" ]; then
	set_hostname "${HN}"
	use_bookworm

	# apt: force IPv4
	APTIPV4FILE=$(apt_force_ipv4)
	git add ${APTIPV4FILE}
	git commit -s -m "apt: force IPv4" ${APTIPV4FILE}
	# /apt: force IPv4

	# apt: setup proxy
	if [ -n "${APTPROXY}" ]; then
		apt_setup_proxy
		git add ${APTPROXYFILE}
		git commit -s -m "apt: setup proxy" ${APTPROXYFILE}
		apt update
	fi
	# /apt: setup proxy
fi


git stash

#apt-get dist-upgrade -y
#git add .
#git commit -s -m "apt-get dist-upgrade -y"

if [ "$FIRST_TIME" = "yes" ]; then
	install_hwinfo
fi

install_one_package lshw

# update-initramfs uses zstd if possible
install_one_package zstd

install_one_package firmware-realtek
install_one_package firmware-misc-nonfree
install_one_package intel-microcode

# debian 12.4, linux 6.1.0
#sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="quiet"$/GRUB_CMDLINE_LINUX_DEFAULT="mitigations=off"/' default/grub
#update-grub
#git commit -s -m "grub: disable Spectre, Meltdown etc mitigations" default/grub

sed -i 's/^#GRUB_DISABLE_OS_PROBER=false$/GRUB_DISABLE_OS_PROBER=true/' default/grub
update-grub
git commit -s -m "grub: disable os prober" default/grub

install_one_package memtest86+
install_one_package memtester
install_one_package testdisk
install_one_package stress

install_one_package lm-sensors
install_one_package hdparm
install_one_package smartmontools
install_one_package lsscsi
install_one_package mtd-utils
install_one_package iotop

install_one_package usbutils

install_one_package pciutils

install_one_package i2c-tools
install_one_package edid-decode
install_one_package ddccontrol

install_one_package net-tools
install_one_package ethtool
install_one_package vlan
install_one_package bridge-utils
install_one_package nicstat
install_one_package iftop

install_one_package makedev
install_one_package sysfsutils

install_one_package psmisc
install_one_package procinfo
install_one_package lsof
install_one_package htop
install_one_package strace
install_one_package ltrace

install_one_package plocate
install_one_package time

install_one_package vim
install_one_package screen
install_one_package tmux

install_one_package enca
install_one_package recode
install_one_package tofrodos
install_one_package dos2unix
install_one_package hexedit
install_one_package hexer
install_one_package uudeview
install_one_package gawk
install_one_package expect
install_one_package pv
install_one_package file

# file renaming
install_one_package convmv
install_one_package renameutils

install_one_package tree

# terminal interaction recorders/players
install_one_package termrec
install_one_package ttyrec

install_one_package git-doc
install_one_package git-annex
install_one_package git-lfs

install_one_package ntpdate

install_one_package arping
install_one_package iptraf
install_one_package tcpdump
install_one_package nmap

install_one_package wireguard

install_one_package autossh
install_one_package sshfs
install_one_package sshpass
install_one_package telnet

if [ "$IS_SERVER" = "yes" ]; then
	# unbound - validating, recursive, caching DNS resolver
	install_one_package unbound
fi
install_one_package dnsutils
install_one_package dnstracer
install_one_package bind9-host

if [ "$IS_SERVER" = "yes" ]; then
	install_one_package isc-dhcp-server
fi
install_one_package dhcpdump

install_one_package nfs-kernel-server

install_one_package lftp
install_one_package ftp

install_one_package tftp-hpa

if [ "$IS_SERVER" = "yes" ]; then
	install_one_package tftpd-hpa
	install_one_package vsftpd
fi

##install_one_package links2
install_one_package w3m
install_one_package curl

install_one_package whois

install_one_package netcat-openbsd
install_one_package socat

install_one_package archivemount
install_one_package arj
install_one_package lzma
install_one_package lzop
install_one_package rar
install_one_package unar
install_one_package zip
# zstd is already installed, see above

# performance benchmarks
install_one_package netperf
install_one_package lmbench
install_one_package lmbench-doc

# lsb-release - Linux Standard Base version reporting utility (minimal implementation)
install_one_package lsb-release

if [ "$IS_SERVER" = "yes" ]; then
	install_one_package iptables
	install_one_package iptables-persistent

	# dnsmasq - small caching DNS proxy and DHCP/TFTP server
	install_one_package dnsmasq
fi

##install_one_package elfutils

##install_one_package docker.io
##install_one_package podman

install_one_package qemu-system
install_one_package qemu-utils
install_one_package guestfs-tools
install_one_package syslinux-common
install_one_package uml-utilities
install_one_package driverctl

install_one_package python3
install_one_package python3-pip
##install_one_package ipython3

### filesystems
##install_one_package squashfs-tools
##install_one_package mtools
##install_one_package genromfs

### hardware manipulation
##install_one_package openocd
##install_one_package flashrom
##install_one_package ftdi-eeprom

### serial communication programs
##install_one_package picocom
##install_one_package minicom
##install_one_package lrzsz
##install_one_package ckermit
##install_one_package setserial

### minimal x11 gui workstation
##install_one_package jwm
##install_one_package slim
##
##fix_n_install_luit()
##{
##	# Debian 12.1 problem (luit_2.0.20221028-1_amd64)
##	# The following packages have unmet dependencies:
##	#  luit : Breaks: x11-utils (< 7.7+6) but 7.7+5 is to be installed
##	#  E: Error, pkgProblemResolver::Resolve generated breaks, this may be caused by held packages.
##	#  see https://dev1galaxy.org/viewtopic.php?pid=42148#p42148
##	#      https://www.mail-archive.com/debian-bugs-dist@lists.debian.org/msg1915280.html
##	TDIR=$(mktemp -d fix-luit.XXXXXXXXXX)
##
##	P=$(pwd)
##
##	cd $TDIR
##
##	apt-get download luit
##
##	DEBPACKAGE=$(basename luit_*deb .deb)
##	mkdir ${DEBPACKAGE}
##	dpkg-deb -x ${DEBPACKAGE}.deb ${DEBPACKAGE}
##	dpkg-deb -e ${DEBPACKAGE}.deb "${DEBPACKAGE}/DEBIAN"
##	sed -i '/Breaks:/d' "${DEBPACKAGE}/DEBIAN/control"
##	sed -i '/Replaces:/d' "${DEBPACKAGE}/DEBIAN/control"
##
##	FIXMEDEBPACKAGE="${DEBPACKAGE}_fixed.deb"
##	dpkg-deb -b ${DEBPACKAGE} ${FIXMEDEBPACKAGE}
##
##	dpkg -i ${FIXMEDEBPACKAGE}
##
##	cd ${P}
##	rm -rf ${TDIR}
##}
##
##fix_n_install_luit
##install_one_package xorg
##install_one_package tightvncserver
##install_one_package x11vnc
##
##install_one_package firefox-esr
### firefox-esr relies on pciutils, pciutils is already installed, see above
##
##install_one_package ffmpeg
##install_one_package pavucontrol
##install_one_package pamixer
##install_one_package alsa-utils
##install_one_package mpv
##
##install_one_package rxvt-unicode
##
##install_one_package evince
### /minimal x11 gui workstation

# The Last One!
# install_one_package can fail after installing resolvconf!
# e.g. resolvconf is used by wireguard dns
install_one_package resolvconf

### Setup static bridge interface
##BR="br1"
##IF="enp7s0"
##IP="192.168.1.???/24"
##IFFILE="network/interfaces.d/${IF}"
##cat <<EOF > ${IFFILE}
##auto ${BR}
##allow-hotplug ${BR}
##iface ${BR} inet static
##        bridge_ports ${IF}
##        bridge_hw ${IF}
##        address ${IP}
##EOF
##git add ${IFFILE}
##git commit -s -m "network: interfaces: ${IF}: set up ${BR}" ${IFFILE}
##ifup ${BR}

git stash pop
