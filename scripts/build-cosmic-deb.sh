#!/usr/bin/env bash
set -u -o pipefail

PACKAGES_FILE="${PACKAGES_FILE:-/workspace/packages.txt}"
OUT_DIR="${OUT_DIR:-/out}"
CACHE_DIR="${CACHE_DIR:-/cache}"
WORK_DIR="${WORK_DIR:-/workspace/work}"
LOG_DIR="${LOG_DIR:-${CACHE_DIR}/logs}"

mkdir -p "${OUT_DIR}" "${CACHE_DIR}" "${WORK_DIR}" "${LOG_DIR}"

fix_ownership() {
    if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
        chown -R "${HOST_UID}:${HOST_GID}" "${OUT_DIR}" "${CACHE_DIR}" "${WORK_DIR}" || true
    fi
}

trap fix_ownership EXIT

parse_packages_file() {
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        line="$(echo "${line}" | xargs)"
        [[ -n "${line}" ]] && echo "${line}"
    done <"${PACKAGES_FILE}"
}

parse_packages_env() {
    echo "${COSMIC_PACKAGES}" | tr ',\n' '  ' | xargs -n1
}

if [[ -n "${COSMIC_PACKAGES:-}" ]]; then
    mapfile -t packages < <(parse_packages_env)
else
    if [[ ! -f "${PACKAGES_FILE}" ]]; then
        echo "Missing package list: ${PACKAGES_FILE}" >&2
        exit 1
    fi
    mapfile -t packages < <(parse_packages_file)
fi

if [[ ${#packages[@]} -eq 0 ]]; then
    echo "No source packages configured." >&2
    exit 1
fi

echo "Using source packages: ${packages[*]}"

apt-get update

declare -a succeeded=()
declare -a failed=()

for pkg in "${packages[@]}"; do
    pkg_root="${WORK_DIR}/${pkg}"
    pkg_log="${LOG_DIR}/${pkg}.log"
    rm -rf "${pkg_root}"
    mkdir -p "${pkg_root}"

    echo "==> Building ${pkg}"
    if (
        set -e
        cd "${pkg_root}"
        apt source "${pkg}"

        src_dir="$(find . -mindepth 1 -maxdepth 1 -type d | head -n1)"
        if [[ -z "${src_dir}" ]]; then
            echo "No source directory created for ${pkg}" >&2
            exit 1
        fi
        cd "${src_dir}"

        mk-build-deps -i -r -t 'apt-get -y --no-install-recommends' debian/control
        dpkg-buildpackage -us -uc -b -j"$(nproc)"

        shopt -s nullglob
        artifacts=( ../*.deb ../*.buildinfo ../*.changes )
        if [[ ${#artifacts[@]} -gt 0 ]]; then
            cp -f "${artifacts[@]}" "${OUT_DIR}/"
        fi
    ) >"${pkg_log}" 2>&1; then
        succeeded+=("${pkg}")
        echo "✓ ${pkg}"
    else
        failed+=("${pkg}")
        echo "✗ ${pkg} (see ${pkg_log})"
    fi
done

echo
echo "Build summary"
echo "  Succeeded (${#succeeded[@]}): ${succeeded[*]:-none}"
echo "  Failed (${#failed[@]}): ${failed[*]:-none}"

if [[ ${#failed[@]} -gt 0 ]]; then
    echo
    echo "Failure log tails:"
    for pkg in "${failed[@]}"; do
        echo "--- ${pkg} (${LOG_DIR}/${pkg}.log) ---"
        tail -n 40 "${LOG_DIR}/${pkg}.log" || true
        echo
    done
    exit 1
fi
