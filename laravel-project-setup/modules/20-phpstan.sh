# name: phpstan
# desc: Write phpstan.neon (larastan, level 10)
# default: on
#
# The level and the ignore rules live in assets/phpstan.neon — edit that file,
# not this one. Nothing else sets the level, so the neon file is the single
# source of truth for how strict the analysis is.

install_asset phpstan.neon phpstan.neon
