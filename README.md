Initial setup
=============

Install docker.

Install qemu, binfmt-support, and qemu-user-static:

```
apt install binfmt-support qemu-user-static
```

Make sure that your kernel has binfmt support.

Enable an execution of different multi-architecture binaries by QEMU and binfmt_misc:

``
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
``

Prevent mipsn32 and mips conflicts by disabling mipsn32:

```
echo '-1' > /proc/sys/fs/binfmt_misc/qemu-mipsn32el
echo '-1' > /proc/sys/fs/binfmt_misc/qemu-mipsn32
```

* https://wiki.debian.org/QemuUserEmulation.
* https://github.com/multiarch/qemu-user-static
* https://www.stereolabs.com/docs/docker/building-arm-container-on-x86/


run apt-cacher-ng container (optionaly)
---------------------------------------

```
cd docker
docker build -f Dockerfile.apt-cacher-ng --tag apt-cacher .
cd ..
mkdir -p var/apt-cacher-ng
docker run -d -p 3142:3142 -v $(pwd)/var/apt-cacher-ng:/var/cache/apt-cacher-ng --net=bridge --rm --name apt-cacher-run apt-cacher
```


run main container
------------------

```
cd docker
docker build -f Dockerfile.debian12 --tag mk-deb-rootfs-12 .
cd ..
docker run -it --rm --privileged -v $(pwd):/workdir mk-deb-rootfs-12
```


using main container
--------------------

1. Generate minimal debian rootfs:

```
./stage1.sh config/bullseye-arm64
```

Result:

```
output/stage1/debian-bullseye-arm64-202305281029.tar.gz
output/stage1/debian-bullseye-arm64-latest.tar.gz
```


2. Build linux kernel:

```
./stage2.sh config/bullseye-arm64
```

Result:

```
output/stage2/config-aarch64-virt-202305281137
output/stage2/config-aarch64-virt-latest
output/stage2/Image.gz-aarch64-virt
output/stage2/Image.gz-aarch64-virt-202305281137
output/stage2/Image.gz-aarch64-virt-latest
```


3. Update rootfs using qemu-system

```
./stage3.sh config/bullseye-arm64
```

Result:

```
output/stage3/linux-rootfs-aarch64-virt.qcow2
output/stage3/linux-rootfs-aarch64-virt.shrunk.qcow2
output/stage3/linux-rootfs-aarch64-virt.tar.gz
```
