# cosmic-deb

`cosmic-deb` rebuilds Debian **sid** COSMIC source packages as binary `.deb`s against a clean Debian **trixie** container, so you can install them on a normal mutable trixie host with `apt`/`dpkg` tracking the files.

The goal is to avoid both:

- polluting the host with a large Rust/Wayland build toolchain, and
- the upstream `systemd-sysext` testing path that makes `/usr` and `/opt` read-only on a normally mutable system.

This is a standard backport-style workflow: trixie supplies the runtime ABI and build environment, sid is used only as a **source** archive, and the resulting unsigned `.deb`s are copied back to the host.

## Prerequisites

- `podman` or `docker`
- Debian trixie host (v1 is only intended for `amd64`)
- roughly 10 GB of free disk space
- roughly 8 GB of RAM recommended for smoother Rust builds

## Quickstart

```bash
make image
make build
sudo apt install ./out/*.deb
```

The build output is written to `./out/`. Reusable caches land in `./cache/`.

## What gets built

The default package list lives in [`packages.txt`](./packages.txt). It starts with the core compositor/session, shell pieces, settings, apps, and theming bits that currently exist as Debian sid **source** packages:

- compositor/session: `cosmic-comp`, `cosmic-session`, `cosmic-greeter`
- shell: `cosmic-panel`, `cosmic-applets`, `cosmic-applibrary`, `cosmic-launcher`, `cosmic-bg`, `cosmic-osd`, `cosmic-notifications`, `cosmic-idle`, `cosmic-randr`, `cosmic-screenshot`, `cosmic-workspaces-epoch`, `cosmic-initial-setup`
- settings: `cosmic-settings`, `cosmic-settings-daemon`
- apps: `cosmic-edit`, `cosmic-files`, `cosmic-term`, `cosmic-store`, `cosmic-player`
- portal/theme/assets: `xdg-desktop-portal-cosmic`, `cosmic-icons`, `cosmic-wallpapers`

Before a long run, verify the current archive state inside the container with `apt-cache showsrc <package>`. If sid does not currently publish one of these source packages yet, remove it from `packages.txt`; that component will need an upstream-source build instead of the Debian-source backport flow documented here.

## How it works

- `Containerfile`
  - starts from `debian:trixie`
  - installs the Debian packaging toolchain plus the COSMIC dependency block from the upstream `cosmic-epoch` README
  - adds a `deb-src`-only sid source so `apt source` can fetch source packages without allowing sid binaries into the build image
  - installs a stable Rust toolchain with `rustup` as a non-root `builder` user
- `build.sh`
  - reads the requested source package list
  - downloads Debian sid source packages with `apt source`
  - installs build-deps against trixie with `mk-build-deps`
  - runs `dpkg-buildpackage -us -uc -b`
  - copies finished `.deb`s into `/out`
  - keeps going after individual failures, then prints a succeeded/failed summary and the last 20 log lines for each failure

If `/cache` is mounted, the script also reuses:

- downloaded source packages under `cache/sources/`
- Cargo state under `cache/cargo/`
- Rust toolchains under `cache/rustup/`
- Rust build output under `cache/targets/`
- build logs under `cache/logs/`

## Customising the package set

Edit `packages.txt`, or point the container at a different list:

```bash
make build COSMIC_PACKAGES=/workspace/my-packages.txt
```

`COSMIC_PACKAGES` may be either:

- a path to a file containing one source package per line, or
- a whitespace-separated package list

Example:

```bash
make build COSMIC_PACKAGES="cosmic-comp cosmic-session cosmic-greeter cosmic-panel"
```

## Debugging a failed package build

Drop into the same image interactively:

```bash
make shell
```

Then inspect the same steps manually, for example:

```bash
cd /build
apt source cosmic-comp
cd cosmic-comp-*
sudo mk-build-deps -i -r -t 'apt-get -y --no-install-recommends'
dpkg-buildpackage -us -uc -b -j"$(nproc)"
```

Per-package logs are persisted in `cache/logs/` when `make build` is used.
If one or more packages fail, `make build` exits non-zero after printing the summary, but any `.deb`s that were already built successfully remain in `out/`.

If a sid package fails to build on trixie, the first place to inspect is the Debian packaging metadata in the unpacked source tree:

- `debian/control` for `Build-Depends`, `debhelper-compat`, `dh-cargo`, and versioned constraints
- `debian/rules` for cargo handling and any packaging-time assumptions about newer tooling

## Known caveats

- This is a backport workflow, not an official build from System76 or Debian.
- The resulting packages are built with `-us -uc`, so they are **unsigned** and intended for local use. If you later publish them in an APT repository, sign them first.
- Some sid source packages may require build dependencies that are newer than trixie provides, especially newer `librust-*-dev`, `debhelper-compat`, or `dh-cargo` packages.
  - Common fix #1: lower a versioned constraint in `debian/control` when trixie's package is still sufficient.
  - Common fix #2: patch `debian/rules` to use vendored cargo dependencies (`cargo vendor`) instead of depending on a missing Debian crate package.
- This recipe intentionally does **not** use `systemd-sysext`, upstream git submodule builds, package signing, or multi-architecture support.
- v1 is only documented and intended for `amd64`.

## Uninstalling from the host

```bash
sudo apt remove 'cosmic-*'
```
