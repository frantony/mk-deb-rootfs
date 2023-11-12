stage1 and stage3 output tarballs can be used for creating cross-platform docker images.

Example:

```
mk-deb-rootfs/contrib/docker# zcat ../../output/stage1/debian-sid-riscv64-latest.tar.gz | docker import - debian-sid-riscv64
sha256:c5fd19f51b45fb87aefdd4d0eae3216db7f183108e72d77ddd7e6fc816755a73
mk-deb-rootfs/contrib/docker# docker images | head -n 2
REPOSITORY                   TAG       IMAGE ID       CREATED          SIZE
debian-sid-riscv64           latest    c5fd19f51b45   12 seconds ago   229MB
mk-deb-rootfs/contrib/docker# docker run --rm -it debian-sid-riscv64 /bin/bash
root@9c4eeee5ad93:/# uname -m
riscv64
```

See also https://github.com/docker/buildx/
