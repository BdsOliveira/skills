# name: composer-scripts
# desc: Merge composer scripts (stan, pint, coverage, quality)
# default: on
#
# The scripts themselves live in assets/composer-scripts.json. Merging keeps
# any script the project already had; only same-named entries are replaced,
# which is what makes re-running this safe.

merge_composer_scripts "$(asset composer-scripts.json)"

# The coverage scripts drive Pest. The pest step normally puts it there; say
# something only when that step was skipped, rather than letting the user find
# out the first time they run `composer coverage`.
if [[ ${DRY_RUN:-0} != 1 && ! -x vendor/bin/pest ]]; then
    warn "vendor/bin/pest not present — the coverage scripts need it (rerun with --only pest)"
fi
