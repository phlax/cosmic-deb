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
