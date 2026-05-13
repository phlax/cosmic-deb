#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PACKAGE_FILE=/build/packages.txt
if [[ -f /workspace/packages.txt ]]; then
    DEFAULT_PACKAGE_FILE=/workspace/packages.txt
fi

OUT_DIR=${OUT_DIR:-/out}
CACHE_DIR=${CACHE_DIR:-/cache}
WORK_ROOT=${WORK_ROOT:-/build/work}

if [[ -d "${CACHE_DIR}" ]]; then
    DOWNLOAD_ROOT=${DOWNLOAD_ROOT:-${CACHE_DIR}/sources}
    LOG_ROOT=${LOG_ROOT:-${CACHE_DIR}/logs}
    export CARGO_HOME=${CARGO_HOME:-${CACHE_DIR}/cargo}
    export RUSTUP_HOME=${RUSTUP_HOME:-${CACHE_DIR}/rustup}
else
    DOWNLOAD_ROOT=${DOWNLOAD_ROOT:-/build/downloads}
    LOG_ROOT=${LOG_ROOT:-/build/logs}
    export CARGO_HOME=${CARGO_HOME:-${HOME}/.cargo}
    export RUSTUP_HOME=${RUSTUP_HOME:-${HOME}/.rustup}
fi

export PATH="${CARGO_HOME}/bin:${PATH}"

mkdir -p "${OUT_DIR}" "${WORK_ROOT}" "${DOWNLOAD_ROOT}" "${LOG_ROOT}" "${CARGO_HOME}" "${RUSTUP_HOME}"

resolve_packages() {
    if [[ -n "${COSMIC_PACKAGES:-}" ]]; then
        if [[ -f "${COSMIC_PACKAGES}" ]]; then
            sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "${COSMIC_PACKAGES}"
            return
        fi
        printf '%s\n' "${COSMIC_PACKAGES}" | tr -s '[:space:]' '\n' | sed '/^[[:space:]]*$/d'
        return
    fi

    sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "${DEFAULT_PACKAGE_FILE}"
}

mapfile -t PACKAGES < <(resolve_packages)

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    echo "No packages requested. Set COSMIC_PACKAGES or populate ${DEFAULT_PACKAGE_FILE}."
    exit 1
fi

echo "Refreshing apt metadata..."
sudo apt-get update

echo "Ensuring rustup stable toolchain..."
rustup default stable >/dev/null

declare -a SUCCEEDED=()
declare -a FAILED=()

fetch_dsc() {
    local pkg=$1

    if ! apt-cache showsrc "${pkg}" 2>/dev/null | grep -q '^Package:'; then
        echo "Source package ${pkg} is not present in the configured APT sources. Run 'apt-get update' and verify the sid deb-src configuration before retrying 'apt-cache showsrc ${pkg}'." >&2
        return 1
    fi

    (
        cd "${DOWNLOAD_ROOT}"
        apt source --download-only "${pkg}" >&2
    )

    ls -1t "${DOWNLOAD_ROOT}/${pkg}"_*.dsc 2>/dev/null | head -n1
}

for pkg in "${PACKAGES[@]}"; do
    log_file="${LOG_ROOT}/${pkg}.log"
    build_root="${WORK_ROOT}/${pkg}"
    src_dir="${build_root}/src"
    rm -rf "${build_root}"
    mkdir -p "${build_root}"

    echo "==> Building ${pkg}"
    if (
        set -euo pipefail

        if ! dsc_file=$(fetch_dsc "${pkg}"); then
            exit 1
        fi
        if [[ -z "${dsc_file}" ]]; then
            echo "Unable to locate a downloaded source package for ${pkg}."
            exit 1
        fi

        dpkg-source -x "${dsc_file}" "${src_dir}"

        if [[ -d "${CACHE_DIR}" ]]; then
            export CARGO_TARGET_DIR="${CACHE_DIR}/targets/${pkg}"
            mkdir -p "${CARGO_TARGET_DIR}"
            if [[ ! -e "${src_dir}/target" ]]; then
                ln -s "${CARGO_TARGET_DIR}" "${src_dir}/target"
            fi
        fi

        cd "${src_dir}"
        sudo mk-build-deps -i -r -t 'apt-get -y --no-install-recommends'
        dpkg-checkbuilddeps
        dpkg-buildpackage -us -uc -b -j"$(nproc)"

        mapfile -t built_debs < <(find "${build_root}" -maxdepth 1 -type f -name '*.deb' ! -name '*-build-deps*.deb' | sort)
        if [[ ${#built_debs[@]} -eq 0 ]]; then
            echo "No binary .deb artifacts were produced for ${pkg}."
            exit 1
        fi

        mv -f "${built_debs[@]}" "${OUT_DIR}/"
    ) >"${log_file}" 2>&1; then
        SUCCEEDED+=("${pkg}")
        echo "   ok: ${pkg}"
    else
        FAILED+=("${pkg}")
        echo "   failed: ${pkg} (see ${log_file})"
    fi
done

echo
echo "Build summary"
echo "============="
echo "Succeeded (${#SUCCEEDED[@]}):"
if [[ ${#SUCCEEDED[@]} -gt 0 ]]; then
    printf '  - %s\n' "${SUCCEEDED[@]}"
else
    echo "  (none)"
fi

echo
echo "Failed (${#FAILED[@]}):"
if [[ ${#FAILED[@]} -gt 0 ]]; then
    printf '  - %s\n' "${FAILED[@]}"
    echo
    echo "Failure log tails"
    echo "-----------------"
    for pkg in "${FAILED[@]}"; do
        log_file="${LOG_ROOT}/${pkg}.log"
        echo
        echo "[${pkg}] ${log_file}"
        tail -n 20 "${log_file}" || true
    done
    exit 1
else
    echo "  (none)"
fi
