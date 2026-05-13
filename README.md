# cosmic-deb

This repository provides a Debian trixie base image plus a Compose workflow for
building the full COSMIC desktop stack as Debian packages directly from the
upstream [pop-os](https://github.com/pop-os) git repositories.

> **Note:** COSMIC is _not_ currently packaged in Debian (including sid).
> All packages are built from the pop-os upstream git repos, which carry their
> own `debian/` packaging directories.

## Build the full COSMIC stack

```console
HOST_UID="$(id -u)" HOST_GID="$(id -g)" docker compose run --rm build-cosmic
```

This command will:

- Build the local trixie image from `Dockerfile` (first run).
- Iterate every entry in `scripts/packages.list` in dependency order.
- For each package: clone the pop-os upstream repo, install its build
  dependencies with `mk-build-deps`, and run `dpkg-buildpackage -b -uc -us`.
- After each successful build, regenerate a local apt repository inside `./out`
  so subsequent packages can resolve `cosmic-*` build-dependencies against the
  packages already built in this run.
- Copy `.deb`, `.changes`, and `.buildinfo` artifacts into `./out`.
- Print a success/failure summary at the end; exit non-zero if any package failed.

Host directories used:

| Directory    | Purpose                                             |
|--------------|-----------------------------------------------------|
| `./workspace`| Cloned COSMIC source trees                         |
| `./cache`    | Shared Cargo/registry cache (reused across builds)  |
| `./out`      | Exported build artifacts and local apt repo index   |

## Package-set completeness / distro parity

`scripts/packages.list` includes the core COSMIC desktop set plus the additional
packages needed to close the install gaps seen in testing and better match
other distro COSMIC stacks (for example Fedora), including:

- `cosmic-app-library`, `xdg-desktop-portal-cosmic`, `cosmic-initial-setup`
- `cosmic-player`, `cosmic-store`, `cosmic-wallpapers`
- `pop-fonts`, `pop-icon-theme`, `pop-launcher`, `pop-sound-theme`, `adw-gtk3`
- `appstream-data-pop`

Repository-name mapping exceptions:

- `pop-icon-theme` is built from `https://github.com/pop-os/icon-theme.git`
- `pop-launcher` is built from `https://github.com/pop-os/launcher.git`
- `pop-sound-theme` is built from `https://github.com/pop-os/gtk-theme.git`
- `appstream-data-pop` is built from `https://github.com/pop-os/appstream-data.git`

Debian/trixie exceptions:

- `casper`: this Ubuntu live/installer dependency is intentionally not built by
  this repository; install `cosmic-initial-setup-casper` only where `casper` is
  available from the target distro.
- `breeze-icon-theme` and `playerctl` remain external archive packages and are
  not built by this repository.

## Build a single package

Set `ONLY` to the package name from `scripts/packages.list`:

```console
HOST_UID="$(id -u)" HOST_GID="$(id -g)" ONLY=cosmic-session \
    docker compose run --rm build-cosmic
```

## Troubleshooting

If `docker compose run` reports `sudo: command not found`, rebuild the image:

```console
docker compose build --no-cache build-cosmic
```
