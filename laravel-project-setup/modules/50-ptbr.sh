# name: ptbr
# desc: Publish pt_BR translations and set APP_LOCALE=pt_BR
# default: off
# ask: Install pt_BR translations and set APP_LOCALE=pt_BR?
#
# Whether an app is Portuguese is a per-project decision, never a default, so
# this module always asks (or is named explicitly with --with ptbr / --without ptbr).
#
# lucascudo/laravel-pt-BR-localization is used as a one-shot source of files:
# it is installed as a dev dep, its translations are published into lang/, and
# then it is removed — the published files are all the app needs at runtime, so
# there is no reason to carry the dependency forward.

LOCALE="${SETUP_LOCALE:-pt_BR}"
# Faker takes the same locale string, so it follows APP_LOCALE by default —
# override it only if a project needs seeded data in a different language.
FAKER_LOCALE="${SETUP_FAKER_LOCALE:-$LOCALE}"
PACKAGE="lucascudo/laravel-pt-br-localization"

info "scaffolding lang/ directory..."
run $ARTISAN_CMD lang:publish --no-interaction

info "installing $PACKAGE..."
run $COMPOSER_CMD require --dev --no-interaction "$PACKAGE"

info "publishing $LOCALE translations..."
run $ARTISAN_CMD vendor:publish --tag=laravel-pt-br-localization --no-interaction

set_env_var .env APP_LOCALE "$LOCALE"
set_env_var .env.example APP_LOCALE "$LOCALE"

# Seeders and factories read APP_FAKER_LOCALE, not APP_LOCALE. Leaving it at
# en_US gives a Portuguese app seeded with English names and addresses, which
# is a confusing thing to discover halfway through building the UI.
set_env_var .env APP_FAKER_LOCALE "$FAKER_LOCALE"
set_env_var .env.example APP_FAKER_LOCALE "$FAKER_LOCALE"

# Laravel >= 11 reads the locale from APP_LOCALE, so config/app.php only needs
# patching on older skeletons where the value is hardcoded.
if [[ ${DRY_RUN:-0} != 1 && -f config/app.php ]] && grep -qE "^\s*'locale'\s*=>\s*'[^']*'\s*," config/app.php; then
    sed -i.bak -E "s|^(\s*)'locale'\s*=>\s*'[^']*'\s*,|\1'locale' => '${LOCALE}',|" config/app.php
    rm -f config/app.php.bak
    info "config/app.php: 'locale' => '${LOCALE}'"
fi

info "removing $PACKAGE (translations stay published under lang/)..."
run $COMPOSER_CMD remove --dev --no-interaction "$PACKAGE"

# Drop any stale compiled config so the new locale takes effect. Clearing beats
# re-caching here: a cached config in development freezes .env, which makes the
# next edit look like it did nothing.
run $ARTISAN_CMD config:clear --no-interaction
