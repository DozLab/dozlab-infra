FROM alpine

RUN apk --no-cache add \
    bash \
    curl \
    iproute2 \
    iptables \
    libc6-compat

WORKDIR /find

RUN curl -Lo firecracker.tgz https://github.com/firecracker-microvm/firecracker/releases/download/v0.24.0/firecracker-v0.24.0-x86_64.tgz \
    && mkdir firecracker \
    && tar -xf firecracker.tgz -C firecracker \
    && chmod +x firecracker/firecracker-v0.24.0-x86_64 \
    && mv firecracker/firecracker-v0.24.0-x86_64 /usr/local/bin/firecracker

# Guest kernel: Firecracker's CI build of Linux 5.10 (cgroup v2 with the cpu and cpuset
# controllers, which Kubernetes needs; 4.14 had neither). This build still reads the
# virtio_mmio.device= boot option that Firecracker v0.24 uses to announce the disks; the 6.1
# build doesn't, so it needs a newer Firecracker.
ARG KERNEL_URL=https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.15/x86_64/vmlinux-5.10.245
ARG KERNEL_SHA256=c453f36520d2f2792ab8e4532a814e4a647a4a41a4c94d4e9083a502800159b1
RUN curl -fsSL -o /find/vmlinux.bin "$KERNEL_URL" \
    && echo "$KERNEL_SHA256  /find/vmlinux.bin" | sha256sum -c -

COPY start-firecracker.sh /usr/local/bin/start-firecracker
RUN chmod +x /usr/local/bin/start-firecracker

ENTRYPOINT ["/usr/local/bin/start-firecracker"]
