# name: deploy
# desc: Write the GitHub Actions deploy workflow for shared hosting (FTP + SSH)
# default: off
# ask: Add the shared-hosting deploy workflow (.github/workflows/deploy.yml)?
#
# Installs assets/deploy.yml as .github/workflows/deploy.yml: a push to the
# deploy branch runs the quality gate (stan, pint, coverage), syncs the built
# tree over FTP and then finishes the deploy over SSH (composer install --no-dev,
# migrate, optimize, queue:restart).
#
# The remote path is the one thing that is different in every project, so it is
# never guessed: pass DEPLOY_PATH, or answer the prompt. Everything else has a
# default that matches a cPanel host and can be overridden the same way:
#
#   DEPLOY_PATH=app/projetos/minha-app ./setup.sh --only deploy
#
#   DEPLOY_PATH              remote directory the app lives in (required)
#   DEPLOY_BRANCH            branch that triggers the deploy   (default: main)
#   DEPLOY_PHP_VERSION       PHP on the runner    (default: 8.5)
#   DEPLOY_NODE_VERSION      Node on the runner   (default: 24)
#   DEPLOY_REMOTE_PHP        PHP binary on the host      (default: /usr/local/bin/php)
#   DEPLOY_REMOTE_COMPOSER   composer on the host        (default: /opt/cpanel/composer/bin/composer)
#
# This is the step to run on its own when a project only needs deploying and
# was set up some other way — nothing here depends on the other modules beyond
# the stan/pint/coverage composer scripts the workflow calls.

# --- 1. the remote path ----------------------------------------------------

REMOTE_PATH="${DEPLOY_PATH:-}"

if [[ -z $REMOTE_PATH && -t 0 ]]; then
    read -r -p "?? Remote directory of the app on the server (e.g. app/projetos/minha-app): " REMOTE_PATH
fi

[[ -n $REMOTE_PATH ]] \
    || die "no remote path — rerun with DEPLOY_PATH=<dir on the server> (see modules/80-deploy.sh)"

# The FTP action treats server-dir as a directory and wants it to end in a
# slash; the ssh script cds into the same string, where a trailing slash is
# harmless. Normalising once keeps both usages of the placeholder correct.
REMOTE_PATH="${REMOTE_PATH#./}"
REMOTE_PATH="${REMOTE_PATH%/}/"

# --- 2. the rest of the knobs ----------------------------------------------

# Every placeholder in assets/deploy.yml is filled from here, so the workflow is
# never written with a blank or a leftover token: pass the variable to change a
# value, pass nothing and the default below is used.
BRANCH="${DEPLOY_BRANCH:-main}"
PHP_VERSION="${DEPLOY_PHP_VERSION:-8.5}"
NODE_VERSION="${DEPLOY_NODE_VERSION:-24}"
REMOTE_PHP="${DEPLOY_REMOTE_PHP:-/usr/local/bin/php}"
REMOTE_COMPOSER="${DEPLOY_REMOTE_COMPOSER:-/opt/cpanel/composer/bin/composer}"

# --- 3. render and install -------------------------------------------------

WORKFLOW='.github/workflows/deploy.yml'

render_workflow() {
    sed -e "s|__REMOTE_PATH__|${REMOTE_PATH}|g" \
        -e "s|__BRANCH__|${BRANCH}|g" \
        -e "s|__PHP_VERSION__|${PHP_VERSION}|g" \
        -e "s|__NODE_VERSION__|${NODE_VERSION}|g" \
        -e "s|__REMOTE_PHP__|${REMOTE_PHP}|g" \
        -e "s|__REMOTE_COMPOSER__|${REMOTE_COMPOSER}|g" \
        "$(asset deploy.yml)"
}

info "deploying ${BRANCH} → ${REMOTE_PATH} (php ${PHP_VERSION}, node ${NODE_VERSION})"

if [[ ${DRY_RUN:-0} == 1 ]]; then
    info "[dry-run] would write $WORKFLOW"
else
    mkdir -p "$(dirname "$WORKFLOW")"
    RENDERED="$(mktemp)"
    render_workflow > "$RENDERED"

    # Same contract as install_asset: a hand-edited workflow is never dropped
    # silently, it is left next to the new one as .bak.
    if [[ -f $WORKFLOW ]] && ! cmp -s "$RENDERED" "$WORKFLOW"; then
        cp "$WORKFLOW" "${WORKFLOW}.bak"
        warn "$WORKFLOW existed and differed — previous version saved as ${WORKFLOW}.bak"
    fi

    cp "$RENDERED" "$WORKFLOW"
    rm -f "$RENDERED"
    info "wrote $WORKFLOW"
fi

# --- 4. what the repository still has to be told ---------------------------
#
# The workflow authenticates with repository variables and one secret. Without
# them it fails on the first push, so they are spelled out rather than left in
# the YAML for someone to discover.

info "set in the GitHub repo — variables: FTP_HOST, FTP_USER (optional: SSH_HOST, SSH_PORT); secret: FTP_PASSWORD"
