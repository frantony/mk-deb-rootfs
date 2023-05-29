Initial setup
=============

Install docker.

Install qemu, binfmt-support, and qemu-user-static:

```
apt install binfmt-support qemu-user-static
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
docker build -f Dockerfile.debian11 --tag mk-deb-rootfs-11 .
cd ..
docker run -it --rm --privileged -v $(pwd):/workdir mk-deb-rootfs-11
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
