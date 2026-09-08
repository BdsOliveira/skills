# name: composer-scripts
# desc: Merge composer scripts (stan, pint, coverage, quality)
# default: on
#
# The scripts themselves live in assets/composer-scripts.json. Merging keeps
# any script the project already had; only same-named entries are replaced,
# which is what makes re-running this safe.

merge_composer_scripts "$(asset composer-scripts.json)"

# The coverage scripts drive Pest. Say so early rather than letting the user
# discover it the first time they run `composer coverage` on a PHPUnit project.
if [[ ${DRY_RUN:-0} != 1 && ! -x vendor/bin/pest ]]; then
    warn "vendor/bin/pest not present — the coverage scripts need Pest (composer require --dev pestphp/pest)"
fi
