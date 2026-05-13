#!/usr/bin/env bash
set -u -o pipefail

PACKAGES_FILE="${PACKAGES_FILE:-/workspace/packages.txt}"
OUT_DIR="${OUT_DIR:-/out}"
CACHE_DIR="${CACHE_DIR:-/cache}"
WORK_DIR="${WORK_DIR:-/work}"
LOG_DIR="${LOG_DIR:-${CACHE_DIR}/logs}"

if ! mkdir -p "${OUT_DIR}" "${CACHE_DIR}" "${LOG_DIR}"; then
    echo "Failed to create one or more output/cache directories." >&2
    exit 1
fi

for dir in "${OUT_DIR}" "${CACHE_DIR}" "${LOG_DIR}"; do
    if [[ ! -w "${dir}" ]]; then
        echo "Directory is not writable: ${dir}" >&2
        exit 1
    fi
done

if ! mkdir -p "${WORK_DIR}"; then
    fallback_work_dir="/tmp/cosmic-work"
    echo "Unable to create WORK_DIR=${WORK_DIR}; falling back to ${fallback_work_dir}" >&2
    WORK_DIR="${fallback_work_dir}"
    if ! mkdir -p "${WORK_DIR}"; then
        echo "Failed to create fallback work directory: ${WORK_DIR}" >&2
        exit 1
    fi
fi

parse_packages_file() {
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        line="$(echo "${line}" | xargs)"
        [[ -n "${line}" ]] && echo "${line}"
    done <"${PACKAGES_FILE}"
}

parse_packages_env() {
    printf '%s\n' "${COSMIC_PACKAGES}" | tr ',[:space:]' '\n' | sed '/^$/d'
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

sudo apt-get update

declare -a succeeded=()
declare -a failed=()

for pkg in "${packages[@]}"; do
    pkg_root="${WORK_DIR}/${pkg}"
    pkg_log="${LOG_DIR}/${pkg}.log"
    if ! rm -rf "${pkg_root}" 2>"${pkg_log}" || ! mkdir -p "${pkg_root}" 2>>"${pkg_log}"; then
        failed+=("${pkg}")
        echo "✗ ${pkg} (workspace preparation failed; see ${pkg_log})"
        continue
    fi

    echo "==> Building ${pkg}"
    if (
        set -e
        cd "${pkg_root}"
        apt source "${pkg}"

        mapfile -t source_dirs < <(find . -mindepth 1 -maxdepth 1 -type d -name "${pkg}-*" | sort)
        if [[ ${#source_dirs[@]} -eq 0 ]]; then
            mapfile -t source_dirs < <(find . -mindepth 1 -maxdepth 1 -type d | sort)
        fi
        if [[ ${#source_dirs[@]} -ne 1 ]]; then
            echo "No source directory created for ${pkg}" >&2
            if [[ ${#source_dirs[@]} -gt 1 ]]; then
                printf 'Found multiple source directories:\n%s\n' "${source_dirs[@]}" >&2
            fi
            exit 1
        fi
        src_dir="${source_dirs[0]}"
        cd "${src_dir}"

        mk-build-deps -i -r -t 'sudo apt-get -y --no-install-recommends' debian/control
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
