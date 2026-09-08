# name: sail
# desc: Install Laravel Sail and write the Docker Compose file
# default: on
#
# Sail gives the project a Docker stack (PHP, database, cache, mail, storage)
# so every machine runs the same versions. `artisan sail:install` generates the
# Compose file and repoints the .env service variables (DB_HOST, REDIS_HOST,
# MAIL_HOST, ...) at the container names.
#
# The service list lives in assets/sail-services.txt — edit that file, not this
# one, to change which containers a project gets.
#
# This step runs last on purpose. The runner decides once, up front, whether to
# route composer/artisan through Sail, and it only does so when containers are
# already running — so installing Sail here cannot strand the rest of the run
# inside a container that does not exist yet.
#
# Starting the stack is left to the user: `sail up -d` pulls images and holds
# ports, which is not something a setup script should do behind someone's back.

SERVICES=()
while IFS= read -r line; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [[ -n $line ]] && SERVICES+=("$line")
done < "$(asset sail-services.txt)"

[[ ${#SERVICES[@]} -gt 0 ]] || { warn "assets/sail-services.txt is empty — nothing to configure"; return 0 2>/dev/null || exit 0; }

WITH_LIST="$(IFS=,; printf '%s' "${SERVICES[*]}")"

# --- 1. the package --------------------------------------------------------

if [[ -x vendor/bin/sail ]]; then
    info "laravel/sail already installed"
else
    info "installing laravel/sail..."
    run $COMPOSER_CMD require --dev -W --no-interaction laravel/sail
fi

# --- 2. the Compose file ---------------------------------------------------
#
# sail:install rewrites the Compose file wholesale, so an existing one is kept
# the way install_asset keeps config files. Which filename Sail writes depends
# on its version (compose.yaml on current ones, docker-compose.yml on older),
# so nothing here hardcodes it.

compose_file() {
    local f
    for f in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
        [[ -f $f ]] && { printf '%s' "$f"; return 0; }
    done
    return 1
}

PREVIOUS="$(compose_file || true)"
[[ ${DRY_RUN:-0} != 1 && -n $PREVIOUS ]] && cp "$PREVIOUS" "${PREVIOUS}.bak"

info "configuring services: ${WITH_LIST}"
run $ARTISAN_CMD sail:install --with="$WITH_LIST" --no-interaction

# Sail re-dumps the YAML with slightly different quoting each time it reads a
# file it wrote earlier. Comparing quote-insensitively means a real change to
# services, images or ports still leaves a .bak to inspect, while a plain
# re-run does not litter the project with one.
same_compose() {
    diff -q <(tr -d "\"'" < "$1") <(tr -d "\"'" < "$2") >/dev/null 2>&1
}

if [[ ${DRY_RUN:-0} != 1 && -n $PREVIOUS && -f ${PREVIOUS}.bak ]]; then
    if [[ -f $PREVIOUS ]] && same_compose "$PREVIOUS" "${PREVIOUS}.bak"; then
        rm -f "${PREVIOUS}.bak"
    else
        warn "${PREVIOUS} existed and differed — previous version saved as ${PREVIOUS}.bak"
    fi
fi

# --- 3. keep .env.example in step ------------------------------------------
#
# sail:install only edits .env. Mirroring what it wrote into .env.example means
# the next person to clone the repo gets a file matching the compose stack. The
# values are read back out of .env rather than hardcoded, so this never drifts
# from whatever the installed Sail version decided.

mirror_to_example() {
    local key value
    for key in "$@"; do
        value="$(sed -n -E "s/^${key}=//p" .env | head -1)"
        [[ -n $value ]] && set_env_var .env.example "$key" "$value"
    done
}

if [[ ${DRY_RUN:-0} == 1 ]]; then
    info "[dry-run] would mirror into .env.example the service variables sail wrote in .env"
elif [[ -f .env && -f .env.example ]]; then
    for service in "${SERVICES[@]}"; do
        case "$service" in
            mysql|mariadb|pgsql|mongodb)
                mirror_to_example DB_CONNECTION DB_HOST DB_PORT DB_DATABASE DB_USERNAME DB_PASSWORD ;;
            redis|valkey)   mirror_to_example REDIS_HOST ;;
            memcached)      mirror_to_example MEMCACHED_HOST ;;
            mailpit)        mirror_to_example MAIL_HOST MAIL_PORT ;;
            meilisearch)    mirror_to_example SCOUT_DRIVER MEILISEARCH_HOST ;;
            typesense)      mirror_to_example SCOUT_DRIVER TYPESENSE_HOST TYPESENSE_PORT ;;
            minio|rustfs)   mirror_to_example AWS_URL AWS_ENDPOINT AWS_USE_PATH_STYLE_ENDPOINT ;;
        esac
    done
fi

# --- 4. report what changed under the user ---------------------------------

if [[ ${DRY_RUN:-0} != 1 ]]; then
    info "$(compose_file || echo 'compose file') written — start the stack with 'vendor/bin/sail up -d'"
    grep -qE '^DB_CONNECTION=(mysql|mariadb|pgsql|mongodb)' .env 2>/dev/null \
        && info ".env now points at the database container (was sqlite on a fresh app) — run 'sail artisan migrate' once it is up"
fi
