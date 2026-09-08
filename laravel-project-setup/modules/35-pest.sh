# name: pest
# desc: Install Pest and make it the project's test runner
# default: on
#
# Pest is the house test framework. It runs on top of PHPUnit, so phpunit.xml
# and any PHPUnit assertion keep working — what changes is that `pest()` and
# `test()` become available and the coverage scripts have a runner.
#
# Laravel support is built into Pest 5; the old pest-plugin-laravel is not
# needed and is deliberately not installed.
#
# Existing PHPUnit test classes keep running as they are. Rewriting them into
# Pest syntax is a separate, opt-in step — see modules/36-pest-drift.sh.

if [[ -x vendor/bin/pest ]]; then
    info "pest already installed"
else
    # Pest ships a Composer plugin. Without this, `composer require` stops on an
    # interactive trust prompt, which a non-interactive run can never answer.
    run $COMPOSER_CMD config allow-plugins.pestphp/pest-plugin true

    # phpunit comes back as a Pest dependency either way. Dropping the direct
    # requirement keeps composer.json honest about what the project depends on,
    # and matches what Pest's own installation guide does.
    if grep -q '"phpunit/phpunit"' composer.json; then
        info "removing the direct phpunit/phpunit requirement (Pest brings it back as a dependency)..."
        run $COMPOSER_CMD remove --dev --no-interaction phpunit/phpunit
    fi

    info "installing pestphp/pest..."
    run $COMPOSER_CMD require --dev -W --no-interaction pestphp/pest
fi

# `pest --init` writes tests/Pest.php, where the base TestCase and shared traits
# are bound. It asks to be starred on GitHub, hence the redirect: a setup run has
# no one at the keyboard to answer.
if [[ ${DRY_RUN:-0} != 1 && -f tests/Pest.php ]]; then
    info "tests/Pest.php already present — leaving it alone"
else
    info "initialising Pest..."
    run $PHP_CMD vendor/bin/pest --init < /dev/null
fi

# The coverage scripts need a coverage driver in the PHP that runs them: pcov
# or xdebug. Sail's image ships pcov, but an image built before that was true is
# still around on plenty of machines, so "Sail is up" is not the same as "there
# is a driver" — check the PHP that will actually run the tests.
#
# `composer coverage` refuses to run without one and says so; this warns at
# setup time instead of at the first test run.
if [[ ${DRY_RUN:-0} != 1 ]] && ! $PHP_CMD -m 2>/dev/null | grep -qiE '^(pcov|xdebug)$'; then
    warn "no pcov/xdebug in this PHP — 'composer coverage' cannot measure coverage until one is installed"
    warn "on Sail, that usually means a stale image: vendor/bin/sail build --no-cache"
fi
