# name: coverage-driver
# desc: Make sure the project's PHP has a code coverage driver (pcov/xdebug)
# default: on
#
# `composer coverage` measures nothing without pcov or xdebug in the PHP that
# runs the tests, and "nothing measured" reads as 0% — which fails --min with a
# message about coverage rather than about the missing extension. Configuring
# the project includes configuring that.
#
# Where the driver has to end up depends on how the project runs PHP:
#
#   Sail       the runtime image ships pcov (and xdebug). An image built before
#              that was true is the usual cause of the WARN — the fix is a
#              rebuild, not a package.
#   host PHP   the extension is installed with the system package manager or
#              pecl, which needs root; this step does it when it can and prints
#              the exact command when it cannot.
#
# Knobs:
#   COVERAGE_DRIVER=pcov|xdebug   which extension to install on a host PHP (default: pcov)
#   COVERAGE_DRIVER=skip          do nothing, just report
#   COVERAGE_DRIVER_REBUILD=0     never rebuild the Sail image (report instead)
#
# This step runs after `sail`, because on a Sail project the driver lives in the
# image that step's Compose file points at.

DRIVER="${COVERAGE_DRIVER:-pcov}"

if [[ $DRIVER == skip ]]; then
    info "COVERAGE_DRIVER=skip — leaving the coverage driver alone"
    return 0 2>/dev/null || exit 0
fi

[[ $DRIVER == pcov || $DRIVER == xdebug ]] \
    || die "COVERAGE_DRIVER must be pcov, xdebug or skip — got: $DRIVER"

# --- helpers ---------------------------------------------------------------

# has_driver <php-invocation...> — true when that PHP loads pcov or xdebug.
has_driver() {
    "$@" -m 2>/dev/null | grep -qiE '^(pcov|xdebug)$'
}

# sudo_prefix — how to get root for a package install, empty when already root,
# unset (status 1) when there is no non-interactive way to become root.
sudo_prefix() {
    [[ $(id -u) == 0 ]] && { printf ''; return 0; }
    command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1 && { printf 'sudo'; return 0; }
    return 1
}

compose_file() {
    local f
    for f in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
        [[ -f $f ]] && { printf '%s' "$f"; return 0; }
    done
    return 1
}

# --- 1. Sail projects: the driver is in the image --------------------------

if [[ -x vendor/bin/sail ]] && command -v docker >/dev/null 2>&1; then
    IMAGE="$(sed -n -E 's/^[[:space:]]*image:[[:space:]]*.?(sail-[0-9.]+\/app).?[[:space:]]*$/\1/p' "$(compose_file || echo /dev/null)" 2>/dev/null | head -1)"

    if [[ -z $IMAGE ]]; then
        warn "Sail is installed but no sail-*/app image is named in the compose file — skipping the image check"
    elif ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        # Nothing stale to fix: the first `sail up -d` builds the image from the
        # current Dockerfile, and current Sail runtimes ship pcov.
        info "$IMAGE is not built yet — 'vendor/bin/sail up -d' builds it with pcov included"
        return 0 2>/dev/null || exit 0
    elif docker run --rm --entrypoint php "$IMAGE" -m 2>/dev/null | grep -qiE '^(pcov|xdebug)$'; then
        info "$IMAGE already has a coverage driver"
        return 0 2>/dev/null || exit 0
    elif [[ ${COVERAGE_DRIVER_REBUILD:-1} == 0 ]]; then
        warn "$IMAGE has no coverage driver — rebuild it: vendor/bin/sail build --no-cache"
        return 0 2>/dev/null || exit 0
    else
        # The image predates pcov landing in Sail's runtimes. --no-cache because
        # the apt layer that installs the extensions is exactly the cached one.
        info "$IMAGE has no coverage driver — rebuilding it (several minutes; COVERAGE_DRIVER_REBUILD=0 skips this)"
        if run vendor/bin/sail build --no-cache; then
            [[ ${DRY_RUN:-0} == 1 ]] || info "image rebuilt — restart the stack with 'vendor/bin/sail up -d' to pick it up"
        else
            warn "the rebuild failed — run 'vendor/bin/sail build --no-cache' by hand and check the Docker output"
        fi
        return 0 2>/dev/null || exit 0
    fi
fi

# --- 2. host PHP: install the extension ------------------------------------

if has_driver php; then
    info "the host PHP already has a coverage driver"
    return 0 2>/dev/null || exit 0
fi

PHP_MINOR="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null || true)"

# The package name differs per distribution, and pecl is the fallback for the
# ones this does not know. Whatever is chosen is reported, so a run that could
# not install still tells the user exactly what to type.
INSTALL_CMD=()
if command -v apt-get >/dev/null 2>&1; then
    INSTALL_CMD=(apt-get install -y "php${PHP_MINOR}-${DRIVER}")
elif command -v dnf >/dev/null 2>&1; then
    INSTALL_CMD=(dnf install -y "php-${DRIVER}")
elif command -v apk >/dev/null 2>&1; then
    INSTALL_CMD=(apk add --no-cache "php${PHP_MINOR//./}-${DRIVER}")
elif command -v pecl >/dev/null 2>&1; then
    INSTALL_CMD=(pecl install "$DRIVER")
fi

if [[ ${#INSTALL_CMD[@]} -eq 0 ]]; then
    warn "no pcov/xdebug in the host PHP and no package manager to install one — install ${DRIVER} for PHP ${PHP_MINOR} by hand"
    return 0 2>/dev/null || exit 0
fi

if ! SUDO="$(sudo_prefix)"; then
    warn "no pcov/xdebug in the host PHP — installing one needs root: sudo ${INSTALL_CMD[*]}"
    return 0 2>/dev/null || exit 0
fi

info "installing ${DRIVER} for PHP ${PHP_MINOR}..."
if ! run ${SUDO:+$SUDO} "${INSTALL_CMD[@]}"; then
    warn "could not install ${DRIVER} — run '${SUDO:+$SUDO }${INSTALL_CMD[*]}' by hand"
    return 0 2>/dev/null || exit 0
fi

# Debian's php-pcov package enables itself; a pecl build only drops the .so, so
# the extension still has to be switched on in php.ini. The .so has to be there
# first: writing `extension=` for a library that was never built turns every
# later `php` call into a warning, which is worse than the missing driver.
if [[ ${DRY_RUN:-0} != 1 ]] && ! has_driver php; then
    INI="$(php -r 'echo php_ini_loaded_file() ?: "";')"
    EXT_DIR="$(php -r 'echo ini_get("extension_dir");')"

    if [[ -z $INI || ! -f ${EXT_DIR}/${DRIVER}.so ]]; then
        warn "${DRIVER} is still not loaded — install it by hand: ${SUDO:+$SUDO }${INSTALL_CMD[*]}"
        return 0 2>/dev/null || exit 0
    fi

    if run ${SUDO:+$SUDO} sh -c "printf 'extension=%s\n' '$DRIVER' >> '$INI'" && has_driver php; then
        info "enabled ${DRIVER} in ${INI}"
    else
        warn "${DRIVER} installed but not loaded — add 'extension=${DRIVER}' to php.ini${INI:+ ($INI)}"
        return 0 2>/dev/null || exit 0
    fi
fi

[[ ${DRY_RUN:-0} == 1 ]] || info "coverage driver ready: $(php -m | grep -iE '^(pcov|xdebug)$' | tr '\n' ' ')"
