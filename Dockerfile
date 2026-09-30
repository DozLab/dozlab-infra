# Guest kernel, built from kernel.org source: Firecracker's CI config for 6.1.155
# (kernel/firecracker-6.1.155.config) plus DozLab's additions (kernel/dozlab.config), mainly the
# netfilter features kube-proxy needs, which Firecracker's CI kernels leave out. Docker caches
# this stage, so it only rebuilds when the version or a config file changes.
FROM debian:bookworm-slim AS kernel

RUN apt-get update && apt-get install -y --no-install-recommends \
        bc bison build-essential ca-certificates curl flex libelf-dev libssl-dev xz-utils \
    && rm -rf /var/lib/apt/lists/*

ARG KERNEL_VERSION=6.1.155
ARG KERNEL_SRC_SHA256=c29387aeee085fbcbd91236224b9df805063bac43615e75cea2c6b29604a5c73
WORKDIR /build
RUN curl -fsSLo linux.tar.xz https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz \
    && echo "$KERNEL_SRC_SHA256  linux.tar.xz" | sha256sum -c - \
    && tar -xf linux.tar.xz && rm linux.tar.xz

COPY kernel/ /build/kernel/
WORKDIR /build/linux-${KERNEL_VERSION}
# Merge the config, then fail if any DozLab option didn't survive olddefconfig (an unmet
# dependency drops an option silently).
RUN ./scripts/kconfig/merge_config.sh -m /build/kernel/firecracker-${KERNEL_VERSION}.config /build/kernel/dozlab.config \
    && make olddefconfig \
    && missing=$(grep -E '^CONFIG_' /build/kernel/dozlab.config | while read -r opt; do grep -qxF "$opt" .config || echo "$opt"; done) \
    && if [ -n "$missing" ]; then echo "kernel options not applied:"; echo "$missing"; exit 1; fi \
    && make -j"$(nproc)" vmlinux \
    && cp vmlinux /vmlinux \
    && cp .config /vmlinux.config

FROM alpine

RUN apk --no-cache add \
    bash \
    curl \
    iproute2 \
    iptables \
    libc6-compat

WORKDIR /find

# Firecracker, pinned by version and the release's published SHA-256. v1.15.1 is the newest
# release that Firecracker's CI publishes guest kernels for (firecracker-ci/v1.15); the kernel
# above uses that release's 6.1 config (dozlab-api docs/decision.md, option B). 6.1 needs
# Firecracker 1.x: it finds its disks through ACPI, not the virtio_mmio.device= option v0.24 used.
ARG FIRECRACKER_VERSION=v1.15.1
ARG FIRECRACKER_SHA256=d4a32ab2322d887ca1bc4a4e7afa9cc35393e6362dfc2b3becb389d362e4275a
RUN curl -fsSLo firecracker.tgz https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-x86_64.tgz \
    && echo "$FIRECRACKER_SHA256  firecracker.tgz" | sha256sum -c - \
    && tar -xf firecracker.tgz \
    && install -m 0755 release-${FIRECRACKER_VERSION}-x86_64/firecracker-${FIRECRACKER_VERSION}-x86_64 /usr/local/bin/firecracker \
    && rm -rf firecracker.tgz release-${FIRECRACKER_VERSION}-x86_64

COPY --from=kernel /vmlinux /find/vmlinux.bin
COPY --from=kernel /vmlinux.config /find/vmlinux.config

COPY start-firecracker.sh /usr/local/bin/start-firecracker
RUN chmod +x /usr/local/bin/start-firecracker

ENTRYPOINT ["/usr/local/bin/start-firecracker"]
