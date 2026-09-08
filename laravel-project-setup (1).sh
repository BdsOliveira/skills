#!/usr/bin/env bash
#
# laravel-project-setup.sh
#
# Bootstraps a Laravel project with the tooling/config setup I like:
#   - dev deps: fruitcake/laravel-debugbar, larastan/larastan, laravel/pint
#   - phpstan.neon (larastan, level max via the composer script)
#   - pint.json    (psr12 + custom rules)
#   - composer scripts: stan, pint, coverage, coverage-html, quality
#   - pt_BR translations via lucascudo/laravel-pt-BR-localization
#     (installed as a dev dep, published, then removed — the published
#     files under lang/ are all the app needs at runtime)
#   - runs `artisan boost:update` if the command is available
#
# Usage:
#   ./laravel-project-setup.sh [target-project-dir]
#
# Runs from the target project root (defaults to the current directory).
# Auto-detects Laravel Sail; falls back to local composer/php.
# Safe to re-run: config files are overwritten, scripts merged idempotently.

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve target dir + tool runners
# ---------------------------------------------------------------------------
PROJECT_DIR="${1:-$(pwd)}"
cd "$PROJECT_DIR"

if [[ ! -f composer.json ]]; then
    echo "error: no composer.json found in $PROJECT_DIR — not a PHP/Laravel project root." >&2
    exit 1
fi

if [[ -x vendor/bin/sail ]]; then
    echo ">> Laravel Sail detected — running tooling through Sail."
    COMPOSER="vendor/bin/sail composer"
    ARTISAN="vendor/bin/sail artisan"
    PHP="vendor/bin/sail php"
else
    echo ">> Sail not found — using local composer/php."
    COMPOSER="composer"
    ARTISAN="php artisan"
    PHP="php"
fi

# ---------------------------------------------------------------------------
# 1. Dev dependencies
# ---------------------------------------------------------------------------
echo ">> Installing dev dependencies..."
$COMPOSER require --dev --no-interaction \
    fruitcake/laravel-debugbar \
    larastan/larastan \
    laravel/pint

# ---------------------------------------------------------------------------
# 2. phpstan.neon
# ---------------------------------------------------------------------------
echo ">> Writing phpstan.neon..."
cat > phpstan.neon <<'NEON'
includes:
    - vendor/larastan/larastan/extension.neon
    - vendor/nesbot/carbon/extension.neon

parameters:

    paths:
        - app/

    # Level 10 is the highest level
    level: 10

    # These traits are consumed exclusively by Livewire v4 single-file
    # components under resources/views, which PHPStan does not scan, so it
    # cannot see the `use` statements and reports them as unused.
    ignoreErrors:
        -
            identifier: trait.unused
            path: app/Livewire/Concerns/*.php

#    excludePaths:
#        - ./*/*/FileToBeExcluded.php
NEON

# ---------------------------------------------------------------------------
# 3. pint.json
# ---------------------------------------------------------------------------
echo ">> Writing pint.json..."
cat > pint.json <<'PINT'
{
    "preset": "psr12",
    "rules": {
        "simplified_null_return": true,
        "array_indentation": true,
        "binary_operator_spaces": {
            "operators": {
                "=>": "align_single_space_minimal",
                "=": "align_single_space_minimal"
            }
        },
        "new_with_parentheses": {
            "anonymous_class": true,
            "named_class": true
        },
        "no_unused_imports": true,
        "ordered_imports": {
            "sort_algorithm": "alpha"
        },
        "single_quote": true,
        "declare_strict_types": true
    }
}
PINT

# ---------------------------------------------------------------------------
# 4. Merge composer scripts (idempotent, preserves existing scripts)
# ---------------------------------------------------------------------------
echo ">> Merging composer scripts (stan, pint, coverage, coverage-html, quality)..."
$PHP -r '
$file = "composer.json";
$json = json_decode(file_get_contents($file), true);
if ($json === null) {
    fwrite(STDERR, "error: composer.json is not valid JSON\n");
    exit(1);
}
$json["scripts"] = ($json["scripts"] ?? []) + [];
$scripts = [
    "stan" => [
        "vendor/bin/phpstan analyse --memory-limit=2G --configuration=phpstan.neon --level=max",
    ],
    "pint" => [
        "vendor/bin/pint --config=pint.json --verbose",
    ],
    "coverage" => [
        "Composer\\Config::disableProcessTimeout",
        "XDEBUG_MODE=off vendor/bin/pest -d pcov.enabled=1 --coverage --min=90",
    ],
    "coverage-html" => [
        "Composer\\Config::disableProcessTimeout",
        "XDEBUG_MODE=off vendor/bin/pest -d pcov.enabled=1 --coverage --min=90 --coverage-html=storage/coverage",
    ],
    "quality" => [
        "@composer pint",
        "@composer stan",
        "@composer test",
    ],
];
foreach ($scripts as $name => $cmd) {
    $json["scripts"][$name] = $cmd;
}
$out = json_encode($json, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n";
file_put_contents($file, $out);
echo "   composer.json updated\n";
'

# ---------------------------------------------------------------------------
# 5. pt_BR localization (lucascudo/laravel-pt-BR-localization)
# ---------------------------------------------------------------------------
echo ">> Setting up pt_BR localization..."

echo "   scaffolding lang/ directory..."
$ARTISAN lang:publish --no-interaction

echo "   installing lucascudo/laravel-pt-br-localization..."
$COMPOSER require --dev --no-interaction lucascudo/laravel-pt-br-localization

echo "   publishing pt_BR translations..."
$ARTISAN vendor:publish --tag=laravel-pt-br-localization --no-interaction

# Sets KEY=VALUE in an env file: replaces the existing line, or appends it.
set_env_var() {
    local file="$1" key="$2" value="$3"

    [[ -f $file ]] || return 0

    if grep -qE "^[#[:space:]]*${key}=" "$file"; then
        sed -i.bak -E "s|^[#[:space:]]*${key}=.*|${key}=${value}|" "$file"
        rm -f "${file}.bak"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
    echo "   ${file}: ${key}=${value}"
}

set_env_var .env APP_LOCALE pt_BR
set_env_var .env.example APP_LOCALE pt_BR

# Laravel >= 11 reads the locale from APP_LOCALE, so config/app.php only needs
# patching on older skeletons where the value is hardcoded.
if [[ -f config/app.php ]] && grep -qE "^\s*'locale'\s*=>\s*'[^']*'\s*," config/app.php; then
    sed -i.bak -E "s|^(\s*)'locale'\s*=>\s*'[^']*'\s*,|\1'locale' => 'pt_BR',|" config/app.php
    rm -f config/app.php.bak
    echo "   config/app.php: 'locale' => 'pt_BR'"
fi

echo "   removing the package (translations stay published under lang/)..."
$COMPOSER remove --dev --no-interaction lucascudo/laravel-pt-br-localization

echo "   rebuilding config cache..."
$ARTISAN config:cache --no-interaction

# ---------------------------------------------------------------------------
# 6. boost:update if available
# ---------------------------------------------------------------------------
echo ">> Checking for boost:update..."
if $ARTISAN list --format=json 2>/dev/null | grep -q '"boost:update"'; then
    echo ">> Running boost:update..."
    $ARTISAN boost:update --no-interaction || $ARTISAN boost:update
else
    echo ">> boost:update not available — skipping."
fi

echo ""
echo ">> Done. Run '\$COMPOSER quality' to lint + analyse + test."
