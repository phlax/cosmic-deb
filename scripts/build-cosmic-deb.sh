#!/bin/bash
set -euo pipefail

repo_url="${COSMIC_REPOSITORY:-https://github.com/pop-os/cosmic-session.git}"
repo_ref="${COSMIC_REF:-master}"
source_dir="${SOURCE_DIR:-/workspace/cosmic-session}"
output_dir="${OUTPUT_DIR:-/out}"
cache_dir="${BUILD_CACHE_DIR:-/cache}"
host_uid="${HOST_UID:-1000}"
host_gid="${HOST_GID:-1000}"
source_parent="$(dirname "$source_dir")"
toolchain_bin="/home/builder/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin"
missing_tools=()

mkdir -p "$source_parent" "$output_dir" "$cache_dir/cargo"
chown -R builder:builder "$source_parent" "$output_dir" "$cache_dir"

if [ ! -d "$source_dir/.git" ]; then
  rm -rf "$source_dir"
  runuser -u builder -- git clone --branch "$repo_ref" --depth 1 "$repo_url" "$source_dir"
else
  runuser -u builder -- git -C "$source_dir" fetch --depth 1 origin "$repo_ref"
  runuser -u builder -- git -C "$source_dir" checkout --force FETCH_HEAD
fi

if [ ! -f "$source_dir/debian/control" ]; then
  echo "Expected Debian packaging metadata at $source_dir/debian/control" >&2
  exit 1
fi

for tool in cargo rustc; do
  if [ ! -x "$toolchain_bin/$tool" ]; then
    missing_tools+=("$tool")
  fi
done

if [ "${#missing_tools[@]}" -gt 0 ]; then
  echo "Expected Rust toolchain binaries in $toolchain_bin: ${missing_tools[*]}" >&2
  exit 1
fi

apt-get update
mk-build-deps \
  --install \
  --remove \
  --tool 'apt-get -y --no-install-recommends' \
  "$source_dir/debian/control"

for tool in cargo rustc rustdoc rustfmt; do
  [ -x "$toolchain_bin/$tool" ] || continue
  cat >/usr/local/bin/$tool <<EOF
#!/bin/sh
exec $toolchain_bin/$tool "\$@"
EOF
  chmod +x /usr/local/bin/$tool
done

runuser -u builder -- env \
  HOME=/home/builder \
  PATH=/usr/local/bin:$toolchain_bin:$PATH \
  CARGO_HOME="$cache_dir/cargo" \
  bash -c "cd '$source_dir' && dpkg-buildpackage -b -uc -us"

find "$source_parent" -maxdepth 1 -type f \
  \( -name '*.deb' -o -name '*.changes' -o -name '*.buildinfo' -o -name '*.build' \) \
  -exec cp -f {} "$output_dir/" \;

chown -R "$host_uid:$host_gid" "$source_parent" "$output_dir" "$cache_dir"
