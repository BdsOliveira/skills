# name: pest-drift
# desc: Rewrite existing PHPUnit test classes into Pest syntax
# default: off
# ask: Rewrite the existing PHPUnit tests into Pest syntax? (edits files under tests/)
#
# Drift rewrites test files in place: a PHPUnit class becomes a set of `test()`
# closures. It is asked about rather than assumed because it edits code the user
# wrote, and a project can perfectly well run Pest while keeping its existing
# classes — Pest executes both styles.
#
# The plugin exists only to perform this one conversion, so it is removed
# afterwards, the same way the pt_BR localization package is.

[[ -x vendor/bin/pest ]] || { warn "pest is not installed — run the pest step first"; return 0 2>/dev/null || exit 0; }

LEGACY="$(grep -rlE 'extends\s+(\\?PHPUnit\\Framework\\)?TestCase' tests 2>/dev/null || true)"
if [[ -z $LEGACY && ${DRY_RUN:-0} != 1 ]]; then
    info "no PHPUnit-style test classes found — nothing to convert."
    return 0 2>/dev/null || exit 0
fi

info "converting: $(printf '%s ' $LEGACY)"
run $COMPOSER_CMD require --dev -W --no-interaction pestphp/pest-plugin-drift

# PAO_DISABLE matters here. laravel/pao wraps tool output for AI agents and
# rewrites the arguments it forwards, which makes `--drift` reject its own
# directory argument. Since this skill is normally driven by an agent, that is
# the common case, not the edge case.
info "running drift over tests/..."
PAO_DISABLE=1 run $PHP_CMD vendor/bin/pest --drift tests < /dev/null

info "removing the drift plugin (it is only needed for the conversion)..."
run $COMPOSER_CMD remove --dev --no-interaction pestphp/pest-plugin-drift

# Drift converts most files but not all, and it is better to name the leftovers
# than to let the user assume the suite is fully migrated.
if [[ ${DRY_RUN:-0} != 1 ]]; then
    REMAINING="$(grep -rlE 'extends\s+(\\?PHPUnit\\Framework\\)?TestCase' tests 2>/dev/null || true)"
    if [[ -n $REMAINING ]]; then
        warn "still in PHPUnit syntax, convert by hand: $(printf '%s ' $REMAINING)"
    else
        info "all test classes converted."
    fi
fi
