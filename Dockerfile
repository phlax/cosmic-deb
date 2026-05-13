FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive
ARG BUILDER_UID=1000
ARG BUILDER_GID=1000

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        dbus \
        devscripts \
        dpkg-dev \
        equivs \
        fakeroot \
        libclang-dev \
        libdbus-1-dev \
        libdisplay-info-dev \
        libexpat1-dev \
        libflatpak-dev \
        libfontconfig-dev \
        libfreetype-dev \
        libgbm-dev \
        libglvnd-dev \
        libgstreamer-plugins-base1.0-dev \
        libgstreamer1.0-dev \
        libinput-dev \
        libpam0g-dev \
        libpipewire-0.3-dev \
        libpixman-1-dev \
        libpulse-dev \
        libseat-dev \
        libssl-dev \
        libsystemd-dev \
        libwayland-dev \
        libxkbcommon-dev \
        lintian \
        lld \
        mold \
        quilt \
        rustup \
        sudo \
        udev \
    && rm -rf /var/lib/apt/lists/*

RUN printf '%s\n' \
        'Types: deb-src' \
        'URIs: https://deb.debian.org/debian' \
        'Suites: sid' \
        'Components: main' \
        'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' \
        >/etc/apt/sources.list.d/sid-src.sources \
    && apt-get update \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid "${BUILDER_GID}" builder \
    && useradd --uid "${BUILDER_UID}" --gid "${BUILDER_GID}" --create-home --shell /bin/bash builder \
    && printf '%s\n' 'builder ALL=(ALL) NOPASSWD:/usr/bin/apt-get update, /usr/bin/mk-build-deps *' >/etc/sudoers.d/builder \
    && chmod 0440 /etc/sudoers.d/builder \
    && mkdir -p /build /workspace /cache /out \
    && chown -R builder:builder /build /workspace /cache /out

USER builder
ENV HOME=/home/builder
ENV PATH=/home/builder/.cargo/bin:${PATH}
RUN rustup default stable

WORKDIR /build
CMD ["/workspace/scripts/build-cosmic-deb.sh"]
