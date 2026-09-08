# name: dev-deps
# desc: Install dev dependencies (debugbar, larastan, pint, boost)
# default: on
#
# The package list lives in assets/dev-packages.txt so you can add or drop a
# tool without touching any shell code.

PACKAGES=()
while IFS= read -r line; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [[ -n $line ]] && PACKAGES+=("$line")
done < "$(asset dev-packages.txt)"

[[ ${#PACKAGES[@]} -gt 0 ]] || { warn "assets/dev-packages.txt is empty — nothing to install"; return 0 2>/dev/null || exit 0; }

info "installing: ${PACKAGES[*]}"
run $COMPOSER_CMD require --dev --no-interaction "${PACKAGES[@]}"
