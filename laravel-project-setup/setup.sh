#!/usr/bin/env bash
#
# laravel-project-setup — runner
#
# Applies a set of independent setup modules to a Laravel project. Every step
# lives in its own file under modules/, so adding a step means dropping in a new
# file and removing one means deleting it (or passing --without). Nothing in
# this runner knows what the individual steps do.
#
# Usage:
#   ./setup.sh [options] [target-dir]
#
# Options:
#   --list                 Show every module, its default state, and what it does
#   --with    <a,b>        Turn on modules that are off by default
#   --without <a,b>        Turn off modules that are on by default (alias: --skip)
#   --only    <a,b>        Run exactly these modules, ignoring defaults
#   --new     <name>       Create a fresh Laravel app named <name> first, then
#                          configure it (enables the new-project module)
#   --dry-run              Print what would happen without touching anything
#   --yes                  Answer "yes" to every module that asks
#   --no                   Answer "no" to every module that asks
#   -h, --help             This help
#
# Modules are named by number, name, or filename — "50", "ptbr" and
# "50-ptbr.sh" all select the same module.
#
# Detects Laravel Sail automatically and routes composer/artisan/php through it.
# Safe to re-run: config files that differ are backed up before being replaced,
# and composer scripts are merged rather than overwritten.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SKILL_DIR

source "$SKILL_DIR/lib/common.sh"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
TARGET_DIR=""
NEW_PROJECT_NAME=""
DRY_RUN=0
ANSWER_ALL=""
LIST_ONLY=0
WITH_TOKENS=()
WITHOUT_TOKENS=()
ONLY_TOKENS=()

split_tokens() {
    local IFS=','
    read -ra _SPLIT <<< "$1"
}

usage() { sed -n '3,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^#\{1\} \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)     LIST_ONLY=1; shift ;;
        --dry-run)  DRY_RUN=1; shift ;;
        --yes|-y)   ANSWER_ALL="yes"; shift ;;
        --no|-n)    ANSWER_ALL="no"; shift ;;
        --new)      NEW_PROJECT_NAME="${2:?--new needs a project name}"; shift 2 ;;
        --with)     split_tokens "${2:?--with needs a module list}"; WITH_TOKENS+=("${_SPLIT[@]}"); shift 2 ;;
        --without|--skip)
                    split_tokens "${2:?--without needs a module list}"; WITHOUT_TOKENS+=("${_SPLIT[@]}"); shift 2 ;;
        --only)     split_tokens "${2:?--only needs a module list}"; ONLY_TOKENS+=("${_SPLIT[@]}"); shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        -*)         die "unknown option: $1 (try --help)" ;;
        *)          TARGET_DIR="$1"; shift ;;
    esac
done

export DRY_RUN

# ---------------------------------------------------------------------------
# Module discovery
#
# Each module declares itself in comment headers on its first lines:
#   # name:    short handle used by --with/--without/--only
#   # desc:    one line shown by --list
#   # default: on | off
#   # ask:     question to put to the user when the module was not named
#              explicitly (off-by-default modules that are a real choice,
#              not a mistake to forget)
# ---------------------------------------------------------------------------
MODULE_FILES=()
while IFS= read -r f; do MODULE_FILES+=("$f"); done < <(
    find "$SKILL_DIR/modules" -maxdepth 1 -name '[0-9][0-9]-*.sh' | sort
)
[[ ${#MODULE_FILES[@]} -gt 0 ]] || die "no modules found in $SKILL_DIR/modules"

header_value() {
    sed -n "1,20p" "$1" | sed -n "s/^#[[:space:]]*$2:[[:space:]]*//p" | head -1
}

mod_id()      { basename "$1" | cut -c1-2; }
mod_name()    { header_value "$1" name || true; }
mod_desc()    { header_value "$1" desc || true; }
mod_default() { local d; d="$(header_value "$1" default)"; printf '%s' "${d:-on}"; }
mod_ask()     { header_value "$1" ask || true; }

# matches <file> <token> — a module answers to its number, its name, or its filename.
matches() {
    local file="$1" token="$2" base
    base="$(basename "$file")"
    [[ $token == "$(mod_id "$file")" ]] && return 0
    [[ $token == "$(mod_name "$file")" ]] && return 0
    [[ $token == "$base" || $token == "${base%.sh}" ]] && return 0
    return 1
}

in_list() {
    local file="$1"; shift
    local token
    for token in "$@"; do
        [[ -n $token ]] || continue
        matches "$file" "$token" && return 0
    done
    return 1
}

if [[ $LIST_ONLY == 1 ]]; then
    printf '%-4s %-18s %-8s %s\n' ID NAME DEFAULT DESCRIPTION
    for f in "${MODULE_FILES[@]}"; do
        state="$(mod_default "$f")"
        [[ -n "$(mod_ask "$f")" ]] && state="asks"
        printf '%-4s %-18s %-8s %s\n' "$(mod_id "$f")" "$(mod_name "$f")" "$state" "$(mod_desc "$f")"
    done
    exit 0
fi

# --new is sugar for "--with new-project" plus the project name.
if [[ -n $NEW_PROJECT_NAME ]]; then
    WITH_TOKENS+=("new-project")
    export NEW_PROJECT_NAME
fi

# ---------------------------------------------------------------------------
# Decide which modules run
# ---------------------------------------------------------------------------
SELECTED=()
for f in "${MODULE_FILES[@]}"; do
    if [[ ${#ONLY_TOKENS[@]} -gt 0 ]]; then
        in_list "$f" "${ONLY_TOKENS[@]}" && SELECTED+=("$f")
        continue
    fi

    explicit_on=0;  in_list "$f" "${WITH_TOKENS[@]+"${WITH_TOKENS[@]}"}" && explicit_on=1
    explicit_off=0; in_list "$f" "${WITHOUT_TOKENS[@]+"${WITHOUT_TOKENS[@]}"}" && explicit_off=1

    [[ $explicit_off == 1 ]] && continue
    if [[ $explicit_on == 1 ]]; then SELECTED+=("$f"); continue; fi

    question="$(mod_ask "$f")"
    if [[ -n $question ]]; then
        # A module with a question is a genuine per-project choice, so never
        # decide it silently: ask, or take the answer from --yes/--no.
        case "$ANSWER_ALL" in
            yes) SELECTED+=("$f"); continue ;;
            no)  continue ;;
        esac
        if [[ -t 0 ]]; then
            read -r -p "?? ${question} [y/N] " reply
            [[ $reply =~ ^[YySs] ]] && SELECTED+=("$f")
            continue
        fi
        warn "skipping $(mod_name "$f"): '$question' was never answered (pass --with $(mod_name "$f") or --yes)"
        continue
    fi

    [[ $(mod_default "$f") == on ]] && SELECTED+=("$f")
done

[[ ${#SELECTED[@]} -gt 0 ]] || die "no modules selected"

# ---------------------------------------------------------------------------
# Resolve the project directory and tool runners
# ---------------------------------------------------------------------------
PROJECT_DIR="$(cd "${TARGET_DIR:-$(pwd)}" 2>/dev/null && pwd)" \
    || die "target directory does not exist: ${TARGET_DIR}"

creating_project=0
for f in "${SELECTED[@]}"; do
    [[ $(mod_name "$f") == new-project ]] && creating_project=1
done

# Sail is only usable when its containers are actually up. Testing for the
# binary alone is not enough: a project can have Sail installed with everything
# stopped — including right after a step that installs it — and routing every
# composer/artisan call into a dead container fails the whole run.
sail_is_running() {
    [[ -x $PROJECT_DIR/vendor/bin/sail ]] || return 1
    command -v docker >/dev/null 2>&1 || return 1
    [[ -n "$(cd "$PROJECT_DIR" && docker compose ps --status running -q 2>/dev/null)" ]]
}

detect_runners() {
    if sail_is_running; then
        info "Laravel Sail is up — routing composer/artisan/php through Sail."
        COMPOSER_CMD="$PROJECT_DIR/vendor/bin/sail composer"
        ARTISAN_CMD="$PROJECT_DIR/vendor/bin/sail artisan"
        PHP_CMD="$PROJECT_DIR/vendor/bin/sail php"
    else
        [[ -x $PROJECT_DIR/vendor/bin/sail ]] \
            && info "Sail is installed but no containers are running — using local composer/php."
        COMPOSER_CMD="composer"
        ARTISAN_CMD="php artisan"
        PHP_CMD="php"
    fi
    export COMPOSER_CMD ARTISAN_CMD PHP_CMD
}

require_laravel_root() {
    [[ -f $PROJECT_DIR/composer.json ]] \
        || die "no composer.json in $PROJECT_DIR — not a PHP/Laravel project root (use --new <name> to create one)"
}

[[ $creating_project == 1 ]] || require_laravel_root
detect_runners

SETUP_STATE_FILE="$(mktemp)"
export SETUP_STATE_FILE
trap 'rm -f "$SETUP_STATE_FILE"' EXIT

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
printf '>> Project: %s\n' "$PROJECT_DIR"
printf '>> Modules: %s\n' "$(for f in "${SELECTED[@]}"; do printf '%s ' "$(mod_name "$f")"; done)"
[[ $DRY_RUN == 1 ]] && printf '>> DRY RUN — nothing will be written\n'

FAILED=()
for f in "${SELECTED[@]}"; do
    step "[$(mod_id "$f")] $(mod_desc "$f")"
    export PROJECT_DIR
    : > "$SETUP_STATE_FILE"

    if ! ( cd "$PROJECT_DIR" && set -euo pipefail && source "$SKILL_DIR/lib/common.sh" && source "$f" ); then
        warn "module $(mod_name "$f") failed — continuing with the rest"
        FAILED+=("$(mod_name "$f")")
        continue
    fi

    # A module may relocate the project (creating a new app); pick that up.
    if grep -q '^PROJECT_DIR=' "$SETUP_STATE_FILE" 2>/dev/null; then
        PROJECT_DIR="$(sed -n 's/^PROJECT_DIR=//p' "$SETUP_STATE_FILE" | tail -1)"
        require_laravel_root
        detect_runners
        info "project directory is now $PROJECT_DIR"
    fi
done

printf '\n'
if [[ ${#FAILED[@]} -gt 0 ]]; then
    warn "finished with failures in: ${FAILED[*]}"
    printf ">> Project ready at %s (rerun a failed module with --only <name>)\n" "$PROJECT_DIR"
    exit 1
fi

printf ">> Done. Project at %s — run 'composer quality' to lint + analyse + test.\n" "$PROJECT_DIR"
