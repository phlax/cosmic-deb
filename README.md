# cosmic-deb

Build COSMIC Debian packages by rebuilding Debian **sid source packages** inside a Debian **trixie** container.

This repository follows Debian package build semantics:

- `apt source <source-package>`
- `mk-build-deps -i -r -t 'apt-get -y --no-install-recommends'`
- `dpkg-buildpackage -us -uc -b`

Artifacts for successful builds are written to `./out` on the host.

## Quickstart

```bash
mkdir -p out cache work
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose run --rm build-cosmic
```

The container runs as a non-root `builder` user mapped to `HOST_UID/HOST_GID` so bind-mounted `out/`, `cache/`, and `work/` stay writable.

## Package selection

Default package list: `./packages.txt` (source package names, comments allowed).

Override package selection at runtime with `COSMIC_PACKAGES`:

```bash
COSMIC_PACKAGES="cosmic-session cosmic-comp cosmic-panel" \
  docker compose run --rm build-cosmic
```

## Output and logs

- Build artifacts: `./out/*.deb`, `./out/*.buildinfo`, `./out/*.changes`
- Per-package logs: `./cache/logs/<source-package>.log`
- Working source trees: `./work/`

Builds continue when an individual package fails. The script prints a final summary and includes failure log tails.

## Notes

- This is a Debian-style sid-to-trixie backport/rebuild workflow, not an upstream git-clone workflow.
- Not all sid COSMIC source packages necessarily backport cleanly to trixie at a given point in time (for example due to newer/missing build dependencies).
