# Образ для сборки Xray-core под телефоны на ОС Аврора. В Debian 12 glibc 2.36, это
# старше, чем 2.38 в Авроре 5.1, поэтому собранная программа там запускается.
FROM debian:bookworm
ARG GO_VERSION=1.27.3
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git gcc-arm-linux-gnueabihf libc6-dev-armhf-cross \
        gcc-aarch64-linux-gnu libc6-dev-arm64-cross \
    && rm -rf /var/lib/apt/lists/*
RUN arch=$(dpkg --print-architecture) \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" | tar -xz -C /usr/local
ENV PATH=/usr/local/go/bin:$PATH GOTOOLCHAIN=local
COPY build-xray.sh /usr/local/bin/build-xray.sh
ENTRYPOINT ["/bin/sh", "/usr/local/bin/build-xray.sh"]
