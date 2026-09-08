#!/usr/bin/env bash
#
# Shared helpers for setup.sh and every module under modules/.
#
# Modules are sourced with these variables already exported:
#   PROJECT_DIR  absolute path of the Laravel project root (cwd when the module runs)
#   SKILL_DIR    absolute path of this skill directory
#   COMPOSER_CMD / ARTISAN_CMD / PHP_CMD   tool runners (Sail-aware)
#   DRY_RUN      1 when --dry-run was passed
#
# Everything below is a helper the modules use. Keep it dependency-free:
# bash + php are the only things guaranteed to exist in a Laravel project.

# --- output ----------------------------------------------------------------

step() { printf '\n>> %s\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- execution -------------------------------------------------------------

# run <cmd...> — echoes and runs, or only echoes under --dry-run.
run() {
    if [[ ${DRY_RUN:-0} == 1 ]]; then
        printf '   [dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}

# --- assets ----------------------------------------------------------------

# asset <filename> — absolute path to a file in assets/.
asset() {
    local path="$SKILL_DIR/assets/$1"
    [[ -f $path ]] || die "missing asset: assets/$1"
    printf '%s' "$path"
}

# install_asset <asset-name> <destination> — copy a config file into the
# project. An existing file that differs is backed up first, so re-running the
# setup on a project with hand-tuned config never silently destroys work.
install_asset() {
    local src dest
    src="$(asset "$1")"
    dest="$2"

    if [[ -f $dest ]] && ! cmp -s "$src" "$dest"; then
        run cp "$dest" "${dest}.bak"
        warn "$dest existed and differed — previous version saved as ${dest}.bak"
    fi
    run cp "$src" "$dest"
    [[ ${DRY_RUN:-0} == 1 ]] || info "wrote $dest"
}

# --- env files -------------------------------------------------------------

# set_env_var <file> <KEY> <value> — replace the existing line (even if
# commented out) or append. No-op when the file is absent.
set_env_var() {
    local file="$1" key="$2" value="$3"

    [[ -f $file ]] || return 0

    if [[ ${DRY_RUN:-0} == 1 ]]; then
        printf '   [dry-run] %s: %s=%s\n' "$file" "$key" "$value"
        return 0
    fi

    if grep -qE "^[#[:space:]]*${key}=" "$file"; then
        sed -i.bak -E "s|^[#[:space:]]*${key}=.*|${key}=${value}|" "$file"
        rm -f "${file}.bak"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
    info "${file}: ${key}=${value}"
}

# --- composer.json ---------------------------------------------------------

# merge_composer_scripts <json-file> — merge a {"name": [...]} map into the
# "scripts" object of composer.json. Existing unrelated scripts survive;
# same-named ones are replaced, which keeps re-runs idempotent.
merge_composer_scripts() {
    local scripts_file="$1"

    if [[ ${DRY_RUN:-0} == 1 ]]; then
        printf '   [dry-run] merge %s into composer.json scripts\n' "$scripts_file"
        return 0
    fi

    # $PHP_CMD may be Sail, which runs inside a container where only the project
    # directory is mounted — a path under the skill directory simply does not
    # exist there, and the merge would quietly do nothing. Staging the file in
    # the project makes the path valid whichever PHP ends up running.
    local staged='.laravel-project-setup.scripts.json' status=0
    cp "$scripts_file" "$staged"

    $PHP_CMD -r '
        $target  = "composer.json";
        $incoming = $argv[1];

        $json = json_decode(file_get_contents($target), true);
        if (!is_array($json)) {
            fwrite(STDERR, "composer.json is not valid JSON\n");
            exit(1);
        }
        $scripts = json_decode(file_get_contents($incoming), true);
        if (!is_array($scripts)) {
            fwrite(STDERR, "{$incoming} is not valid JSON\n");
            exit(1);
        }

        $json["scripts"] = $json["scripts"] ?? [];
        foreach ($scripts as $name => $cmd) {
            $json["scripts"][$name] = $cmd;
        }

        file_put_contents(
            $target,
            json_encode($json, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n"
        );
    ' "$staged" || status=$?

    rm -f "$staged"
    [[ $status -eq 0 ]] || die "could not merge the composer scripts (php exited $status)"

    # Reported from bash rather than from inside the PHP snippet: when the run
    # goes through Sail, output from the container is not something to rely on
    # for knowing whether the step actually did anything.
    info "composer.json scripts: $(grep -oE '"[a-z-]+":' "$scripts_file" | tr -d '":' | tr '\n' ' ')"
}

# --- gitignore -------------------------------------------------------------

# ensure_gitignore <pattern> [comment] — append a pattern to .gitignore unless
# it is already listed. Used for generated files that are machine-specific and
# would cause noise or breakage if committed.
ensure_gitignore() {
    local pattern="$1" comment="${2:-}"

    if [[ ${DRY_RUN:-0} == 1 ]]; then
        printf '   [dry-run] .gitignore += %s\n' "$pattern"
        return 0
    fi

    [[ -f .gitignore ]] || : > .gitignore
    grep -qxF "$pattern" .gitignore && return 0

    [[ -n $comment ]] && printf '\n# %s\n' "$comment" >> .gitignore
    printf '%s\n' "$pattern" >> .gitignore
    info ".gitignore += $pattern"
}

# --- state -----------------------------------------------------------------

# Modules run in a subshell, so a module that changes where the project lives
# (00-new-project creating a fresh app) reports it back through a state file
# the runner re-reads after every module.
set_state() {
    [[ -n ${SETUP_STATE_FILE:-} ]] || return 0
    printf '%s=%s\n' "$1" "$2" >> "$SETUP_STATE_FILE"
}

# --- capability checks -----------------------------------------------------

# artisan_has <command> — true when the project's artisan exposes <command>.
artisan_has() {
    $ARTISAN_CMD list --format=json 2>/dev/null | grep -q "\"$1\""
}
