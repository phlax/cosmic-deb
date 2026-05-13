FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

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
        udev \
    && rm -rf /var/lib/apt/lists/*

RUN printf '%s\n' \
        'Types: deb-src' \
        'URIs: https://deb.debian.org/debian' \
        'Suites: unstable' \
        'Components: main' \
        'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' \
        >/etc/apt/sources.list.d/sid-src.sources \
    && apt-get update \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /build /workspace /cache /out

ENV PATH=/root/.cargo/bin:${PATH}
RUN rustup default stable

WORKDIR /build
CMD ["/workspace/scripts/build-cosmic-deb.sh"]
