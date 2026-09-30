FROM alpine

RUN apk --no-cache add \
    bash \
    curl \
    iproute2 \
    iptables \
    libc6-compat

WORKDIR /find

# Firecracker, pinned by version and the release's published SHA-256. v1.15.1 is the newest
# release that Firecracker's CI publishes guest kernels for (firecracker-ci/v1.15), so it's
# paired with the kernel below (dozlab-api docs/decision.md, option B).
ARG FIRECRACKER_VERSION=v1.15.1
ARG FIRECRACKER_SHA256=d4a32ab2322d887ca1bc4a4e7afa9cc35393e6362dfc2b3becb389d362e4275a
RUN curl -fsSLo firecracker.tgz https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-x86_64.tgz \
    && echo "$FIRECRACKER_SHA256  firecracker.tgz" | sha256sum -c - \
    && tar -xf firecracker.tgz \
    && install -m 0755 release-${FIRECRACKER_VERSION}-x86_64/firecracker-${FIRECRACKER_VERSION}-x86_64 /usr/local/bin/firecracker \
    && rm -rf firecracker.tgz release-${FIRECRACKER_VERSION}-x86_64

# Guest kernel: Firecracker's CI build of Linux 6.1 from the same v1.15 set (cgroup v2 with the
# cpu and cpuset controllers, which Kubernetes needs). It needs Firecracker 1.x: it finds its
# disks through ACPI, not the virtio_mmio.device= option v0.24 used. Fallback from the same set:
#   --build-arg KERNEL_URL=https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.15/x86_64/vmlinux-5.10.245
#   --build-arg KERNEL_SHA256=c453f36520d2f2792ab8e4532a814e4a647a4a41a4c94d4e9083a502800159b1
ARG KERNEL_URL=https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.15/x86_64/vmlinux-6.1.155
ARG KERNEL_SHA256=e20e46d0c36c55c0d1014eb20576171b3f3d922260d9f792017aeff53af3d4f2
RUN curl -fsSL -o /find/vmlinux.bin "$KERNEL_URL" \
    && echo "$KERNEL_SHA256  /find/vmlinux.bin" | sha256sum -c -

COPY start-firecracker.sh /usr/local/bin/start-firecracker
RUN chmod +x /usr/local/bin/start-firecracker

ENTRYPOINT ["/usr/local/bin/start-firecracker"]
