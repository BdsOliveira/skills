# name: new-project
# desc: Create a fresh Laravel application
# default: off
#
# Enabled by `setup.sh --new <name>`. Creates the app inside the target
# directory and hands the new path back to the runner, so every module after
# this one operates on the app that was just created.

: "${NEW_PROJECT_NAME:?new-project module needs NEW_PROJECT_NAME (use --new <name>)}"

DEST="$PROJECT_DIR/$NEW_PROJECT_NAME"

if [[ -e $DEST ]]; then
    if [[ -f $DEST/composer.json ]]; then
        info "$DEST already exists and looks like a project — reusing it."
        set_state PROJECT_DIR "$DEST"
        return 0 2>/dev/null || exit 0
    fi
    die "$DEST already exists and is not a project root"
fi

# The official installer gives the current starter skeleton; composer's
# create-project is the fallback when it isn't installed.
# --pest asks the installer for a Pest-based skeleton, so a new app never needs
# the PHPUnit-to-Pest conversion the pest-drift step exists for.
if command -v laravel >/dev/null 2>&1; then
    info "using the laravel installer"
    run laravel new "$NEW_PROJECT_NAME" --pest --no-interaction
else
    info "laravel installer not found — falling back to composer create-project"
    run composer create-project laravel/laravel "$NEW_PROJECT_NAME" --no-interaction
fi

# The installer can report failure while still exiting 0, so check the result
# rather than the exit code — every later module assumes a working project.
if [[ ${DRY_RUN:-0} != 1 ]]; then
    [[ -f $DEST/composer.json && -f $DEST/vendor/autoload.php ]] \
        || die "the installer did not produce a working project at $DEST — see its output above"
    set_state PROJECT_DIR "$DEST"
fi
