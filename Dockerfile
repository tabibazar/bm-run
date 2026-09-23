# The build and API environment for bm. Everything bm does happens inside this
# container, so the only thing your machine needs is Docker.
#
# BareMetal apps are x86-64, so this is an amd64 image. On an Apple-silicon Mac
# it runs under emulation: slower, but it needs no KVM, because building a
# unikernel does not need to run one.
FROM --platform=linux/amd64 ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
# BareMetal-App's setup.sh checks for exactly:
#   git curl unzip tar gcc nasm make patch jq mkfs.ext2
# The rest is what BareMetal-AppPort's own setup needs to build its libraries.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential nasm git curl ca-certificates unzip tar xz-utils \
      patch jq e2fsprogs util-linux \
      python3 python3-dev pkg-config file bc m4 autoconf automake libtool cmake \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
