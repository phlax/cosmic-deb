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
shopt -s nullglob
toolchain_bins=(/home/builder/.rustup/toolchains/stable-*/bin)
shopt -u nullglob
missing_tools=()

case "$source_dir" in
  /workspace/*) ;;
  *)
    echo "SOURCE_DIR must stay within /workspace: $source_dir" >&2
    exit 1
    ;;
esac

if [ "$source_dir" = "/workspace" ]; then
  echo "SOURCE_DIR must not be /workspace" >&2
  exit 1
fi

if [ "${#toolchain_bins[@]}" -eq 0 ]; then
  echo "Expected a stable Rust toolchain under /home/builder/.rustup/toolchains" >&2
  exit 1
fi

toolchain_bin="${toolchain_bins[0]}"

mkdir -p "$source_parent" "$output_dir" "$cache_dir/cargo"
chown -R builder:builder "$source_parent" "$output_dir" "$cache_dir"

if [ ! -d "$source_dir/.git" ]; then
  case "$source_dir" in
    /workspace/*) ;;
    *)
      echo "Refusing to remove an unexpected SOURCE_DIR: $source_dir" >&2
      exit 1
      ;;
  esac
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
  cat >"/usr/local/bin/$tool" <<EOF
#!/bin/sh
exec $toolchain_bin/$tool "\$@"
EOF
  chmod +x "/usr/local/bin/$tool"
done

runuser -u builder -- env \
  HOME=/home/builder \
  PATH=/usr/local/bin:$toolchain_bin:$PATH \
  CARGO_HOME="$cache_dir/cargo" \
  bash -c "cd '$source_dir' && dpkg-buildpackage -b -uc -us"

mapfile -t artifacts < <(
  find "$source_parent" -maxdepth 1 -type f \
    \( -name '*.deb' -o -name '*.changes' -o -name '*.buildinfo' \)
)

if [ "${#artifacts[@]}" -eq 0 ]; then
  echo "No build artifacts were produced in $source_parent" >&2
  exit 1
fi

cp -f "${artifacts[@]}" "$output_dir/"

chown -R "$host_uid:$host_gid" "$source_parent" "$output_dir" "$cache_dir"
