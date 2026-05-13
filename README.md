# cosmic-deb

This repository provides a Debian trixie base image plus a minimal Compose workflow for building COSMIC desktop Debian packages.

## Build `cosmic-session` with Docker Compose

```console
HOST_UID="$(id -u)" HOST_GID="$(id -g)" docker compose run --rm build-cosmic
```

That command will:

- build the local trixie image from `Dockerfile`
- clone `https://github.com/pop-os/cosmic-session.git`
- install its build dependencies in the container
- run `dpkg-buildpackage`
- copy the resulting `.deb`, `.changes`, `.buildinfo`, and `.build` files into `./out`

Host directories used by the Compose flow:

- `./workspace` for the cloned COSMIC source tree
- `./cache` for reusable Cargo/cache state between builds
- `./out` for exported build artifacts

To build a different COSMIC package, override the repository and source path:

```console
HOST_UID="$(id -u)" HOST_GID="$(id -g)" \
COSMIC_REPOSITORY=https://github.com/pop-os/cosmic-comp.git \
SOURCE_DIR=/workspace/cosmic-comp \
docker compose run --rm build-cosmic
```
