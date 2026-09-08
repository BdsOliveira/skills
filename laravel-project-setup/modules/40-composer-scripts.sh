# name: composer-scripts
# desc: Merge composer scripts (stan, pint, coverage, quality)
# default: on
#
# The scripts themselves live in assets/composer-scripts.json. Merging keeps
# any script the project already had; only same-named entries are replaced,
# which is what makes re-running this safe.
#
# One value in that file is per-project rather than house policy — the minimum
# coverage the `coverage` scripts enforce — so it is a placeholder filled in
# here:
#
#   COVERAGE_MIN=0 ./setup.sh --only composer-scripts
#
#   COVERAGE_MIN   minimum coverage percentage (default: 90)
#
# 90 is the house standard and the right number for a project with a suite. A
# freshly scaffolded app has app/ code and no tests covering it, so `composer
# coverage` fails there by definition: that is the number to lower (or the
# command to postpone) until the suite exists.

COVERAGE_MIN="${COVERAGE_MIN:-90}"

[[ $COVERAGE_MIN =~ ^[0-9]+$ ]] \
    || die "COVERAGE_MIN must be a whole percentage, got: $COVERAGE_MIN"

if [[ ${DRY_RUN:-0} == 1 ]]; then
    # Nothing is written, so rendering would only put a temp path in the log
    # where the asset name belongs.
    merge_composer_scripts "$(asset composer-scripts.json)"
else
    RENDERED_SCRIPTS="$(mktemp)"
    sed "s|__COVERAGE_MIN__|${COVERAGE_MIN}|g" "$(asset composer-scripts.json)" > "$RENDERED_SCRIPTS"
    merge_composer_scripts "$RENDERED_SCRIPTS"
    rm -f "$RENDERED_SCRIPTS"
fi

info "coverage threshold: --min=${COVERAGE_MIN} (override with COVERAGE_MIN=<n>)"

# The coverage scripts drive Pest. The pest step normally puts it there; say
# something only when that step was skipped, rather than letting the user find
# out the first time they run `composer coverage`.
if [[ ${DRY_RUN:-0} != 1 && ! -x vendor/bin/pest ]]; then
    warn "vendor/bin/pest not present — the coverage scripts need it (rerun with --only pest)"
fi
