---
name: laravel-project-setup
description: >-
  Bootstrap and standardize a Laravel project with a fixed house toolchain:
  Larastan/PHPStan (level 10), Laravel Pint (psr12 + custom rules), Debugbar,
  Laravel Boost (AI guidelines, agent skills, MCP server), Laravel Sail (Docker
  stack with mysql/redis/mailpit/minio), Pest as the test runner, the composer
  scripts stan/pint/coverage/coverage-html/quality, an optional GitHub Actions
  deploy workflow for shared hosting (FTP sync + SSH post-deploy), and optional
  pt_BR translations. Use this whenever the user starts a
  new Laravel/PHP project, says "setup", "configura o projeto", "bootstrap",
  "scaffold", or asks to add static analysis, code style, linting, coverage
  thresholds, quality scripts, or a Docker/Sail dev environment to a Laravel app — even if they never mention
  PHPStan or Pint by name. Use it as well when they only want the deploy part:
  "adiciona o deploy", "cria o deploy.yml", "deploy pra hospedagem
  compartilhada", "deploy por FTP/cPanel", "GitHub Actions de deploy". Also use when they want the project in Portuguese
  (pt_BR locale/translations), when they ask to redo the setup on an existing
  project, or when they want to change, add, or remove one of these setup steps.
  Sail-aware and safe to re-run.
---

# Laravel project setup

Applies one team's opinionated Laravel toolchain to a project: static analysis,
code style, quality scripts, and optionally Portuguese translations and a
GitHub Actions deploy workflow for shared hosting.

The whole thing is **modular on purpose**. Each step is a separate file in
`modules/`, each config file is a separate file in `assets/`. Adding a step
means writing one file; dropping one means deleting it or passing `--without`.
That matters because the same setup gets applied to projects that want slightly
different things — and the previous incarnation of this was a single script that
got copy-pasted and hand-edited per project, which is exactly what drifts.

## Run it

```bash
<skill>/setup.sh --list                       # what steps exist and what they do
<skill>/setup.sh                              # configure the project in the cwd
<skill>/setup.sh /path/to/project             # ...or somewhere else
<skill>/setup.sh --new minha-app              # create a fresh Laravel app, then configure it
<skill>/setup.sh --dry-run                    # show every action, write nothing
```

Selecting steps:

| Flag | Effect |
| --- | --- |
| `--with a,b` | Turn on a step that is off by default |
| `--without a,b` | Turn off a step that is on by default (alias `--skip`) |
| `--only a,b` | Run exactly these, ignoring defaults |
| `--new <name>` | Create the app first (enables the `new-project` step) |
| `--yes` / `--no` | Answer every step that asks, without prompting |
| `--dry-run` | Print actions instead of performing them |

Steps answer to their number, name, or filename — `50`, `ptbr` and `50-ptbr.sh`
are the same step.

## Always ask about pt_BR

The `ptbr` step publishes Portuguese translations and sets `APP_LOCALE=pt_BR`.
It is **off by default and must never be assumed either way** — some projects
want it, some don't, and getting it wrong means either a half-translated app or
an unwanted `lang/` tree plus a modified `.env`.

So before running, ask the user plainly, in their language, whether this project
should be set up in Portuguese. Then pass the answer explicitly:

```bash
<skill>/setup.sh --with ptbr       # yes
<skill>/setup.sh --without ptbr    # no
```

Passing it explicitly matters because you are running the script
non-interactively: with no flag and no TTY the step is skipped with a warning
rather than silently guessed. Ask first, then run once with the decision baked
in — don't run the setup and offer to add Portuguese afterwards.

## The deploy step needs a path

The `deploy` step writes `.github/workflows/deploy.yml`: on a push to the deploy
branch GitHub Actions builds the app, runs `composer stan` / `pint` / `coverage`
(the runner installs xdebug so the coverage gate has a driver),
syncs the tree to a shared host over FTP and then finishes over SSH (`composer
install --no-dev`, `migrate --force`, `optimize`, `queue:restart`).

The remote directory is different in every project and appears twice in the
workflow — the FTP `server-dir` and the `cd` in the SSH script — so it is never
guessed. Ask the user where the app lives on the server, then pass it:

```bash
DEPLOY_PATH=app/projetos/minha-app <skill>/setup.sh --with deploy      # with the rest of the setup
DEPLOY_PATH=app/projetos/minha-app <skill>/setup.sh --only deploy      # just the workflow
```

`--only deploy` is the whole point of it being a module: a project that was set
up some other way, or set up months ago, gets the deploy workflow and nothing
else. Everything besides the path has a default, overridden the same way:

| Variable | Default |
| --- | --- |
| `DEPLOY_PATH` | *required* |
| `DEPLOY_BRANCH` | `main` |
| `DEPLOY_PHP_VERSION` | `8.5` |
| `DEPLOY_NODE_VERSION` | `24` |
| `DEPLOY_REMOTE_PHP` | `/usr/local/bin/php` |
| `DEPLOY_REMOTE_COMPOSER` | `/opt/cpanel/composer/bin/composer` |

Then tell the user to configure the repository: variables `FTP_HOST`, `FTP_USER`
(optionally `SSH_HOST`, `SSH_PORT`) and the secret `FTP_PASSWORD`.

## What each step does

| # | Name | Default | What it does |
| --- | --- | --- | --- |
| 00 | `new-project` | off | `laravel new <name>` (or `composer create-project`); enabled by `--new` |
| 10 | `dev-deps` | on | Installs the packages listed in `assets/dev-packages.txt` |
| 20 | `phpstan` | on | Writes `phpstan.neon` from `assets/phpstan.neon` |
| 30 | `pint` | on | Writes `pint.json` from `assets/pint.json` |
| 35 | `pest` | on | Installs Pest and initialises `tests/Pest.php` |
| 36 | `pest-drift` | asks | Rewrites existing PHPUnit test classes into Pest syntax |
| 40 | `composer-scripts` | on | Merges `assets/composer-scripts.json` into `composer.json` (`COVERAGE_MIN`, default 90) |
| 50 | `ptbr` | asks | pt_BR translations + `APP_LOCALE` / `APP_FAKER_LOCALE` = `pt_BR` |
| 60 | `boost` | on | Publishes Laravel Boost guidelines, skills and MCP config |
| 70 | `sail` | on | Installs Sail and writes the Compose file from `assets/sail-services.txt` |
| 80 | `deploy` | asks | Writes `.github/workflows/deploy.yml` (FTP sync + SSH post-deploy) |

Run `--list` rather than trusting this table if the skill has been extended —
the modules directory is the real source of truth.

## Behaviour worth knowing

- **Sail-aware, but only when Sail is actually up.** composer/artisan/php are
  routed through Sail when its containers are running, and fall back to the
  local binaries when they are not. Checking for `vendor/bin/sail` alone would
  send every command into a stopped container — which is exactly what happens on
  a project that has Sail installed but not started.
- **Safe to re-run.** A config file that already exists and differs is copied to
  `<file>.bak` before being replaced, and composer scripts are merged, so
  project-specific scripts survive.
- **A failing step does not abort the run.** The runner reports which steps
  failed at the end and exits non-zero. Rerun one with `--only <name>`.
- **`phpstan.neon` is the only place the level is set.** The `stan` composer
  script deliberately passes no `--level`, so editing `assets/phpstan.neon`
  actually changes how strict the analysis is.
- **Coverage needs a driver, not just Pest.** `composer coverage` runs
  `XDEBUG_MODE=coverage vendor/bin/pest --coverage`, which needs pcov or xdebug
  in whichever PHP runs it — with pcov present php-code-coverage picks pcov and
  ignores the variable, without it xdebug takes over. Both scripts start with a
  `coverage-driver` check that fails with a readable message when neither is
  loaded, because the failure it replaces was a silent one: no driver means 0%
  measured, and the run died on `--min` instead of on the missing extension. The
  `pest` step warns about the same thing at setup time.
- **`WARN Failed to set "pcov.enabled=1"` means the extension is missing.** It
  is what the old `-d pcov.enabled=1` printed, and the fix is a driver in that
  PHP, never another Composer package. Sail's image ships pcov, so an image
  built before that was true is the usual culprit: `vendor/bin/sail build
  --no-cache`, then `vendor/bin/sail up -d`.
- **The coverage threshold is a per-project number.** The scripts are written
  with `--min=90`, the house standard; pass `COVERAGE_MIN=<n>` to the setup to
  bake in a different one. A freshly scaffolded app has `app/` code and no tests
  covering it, so 90 fails there by definition — either scaffold with
  `COVERAGE_MIN=0` and raise it once the suite exists, or tell the user
  `composer coverage` is a gate for later, not a smoke test for a new app.
- **pt_BR translations are vendored, not depended on.** The localization package
  is installed, published into `lang/`, then removed.
- **Pest is the test runner, and new apps are created with it.** `--new` passes
  `--pest` to the installer, so a fresh app is born on Pest. On an existing
  PHPUnit project the `pest` step installs Pest and drops the direct
  `phpunit/phpunit` requirement — Pest runs on PHPUnit, so it comes back as a
  dependency and every existing assertion keeps working.
- **Converting test files is a separate question.** Installing Pest does not
  rewrite anything: PHPUnit classes and Pest closures run side by side. The
  `pest-drift` step does the rewrite, and it asks first, because it edits code
  the user wrote. Worth offering even on a brand-new app — `laravel new --pest`
  installs Pest but still ships PHPUnit-style example tests.
- **Sail is installed but never started.** The step writes `compose.yaml` and
  repoints the `.env` service variables at the containers; `sail up -d` pulls
  images and holds ports, so it stays the user's call. Tell them the command.
- **A database service moves the project off sqlite.** `sail:install --with=mysql`
  rewrites `DB_CONNECTION` and `DB_*` in `.env`, so a fresh Laravel app that was
  on sqlite now needs `sail artisan migrate` against the container. Say so
  rather than letting them find out when a query fails.
- **Anything handed to `$PHP_CMD` must live inside the project.** When the run
  goes through Sail, PHP executes in a container that mounts only the project
  directory — a path under the skill directory does not exist there. Stage the
  file in the project first (`merge_composer_scripts` shows the pattern).
- **Boost is published, not just installed.** The step runs `boost:install`
  (guidelines + skills + MCP) rather than `boost:update`, because a
  non-interactive install does not write the agent list that `boost:update`
  requires. It also adds `.mcp.json` and `boost.json` to `.gitignore` — both
  hold absolute machine paths and are regenerated on every install.
- **The deploy workflow depends on the composer scripts, not on the modules.**
  It calls `composer stan`, `composer pint` and `composer coverage`, so on a
  project set up elsewhere those three have to exist or the job fails at the
  quality gate — check `composer.json` before running `--only deploy` on a
  project this skill has never touched.
- **SSH and FTP share one credential.** `vars.FTP_USER` and
  `secrets.FTP_PASSWORD` are used for both, which is how cPanel-style hosts
  work. `vars.SSH_HOST` and `vars.SSH_PORT` exist only as overrides and fall
  back to `vars.FTP_HOST` and `22`.
- **`vendor/` is not uploaded and `.env` is never touched.** The FTP sync
  excludes both; dependencies are installed on the server by the SSH step, and
  the production `.env` stays whatever the host already has.

## Changing the setup

This is the part to reach for when the user says "add X to my setup" or
"I don't want Y anymore" — edit the skill, don't hand-edit the output.

**Change a config value** (a PHPStan level, a Pint rule, a composer script):
edit the matching file in `assets/`. No shell code involved. The one value that
is per-project rather than house policy is the coverage minimum — it is the
`__COVERAGE_MIN__` placeholder in `assets/composer-scripts.json`, filled in by
`modules/40-composer-scripts.sh` from `COVERAGE_MIN` (default 90):

```bash
COVERAGE_MIN=0 <skill>/setup.sh --new minha-app     # fresh app, no suite yet
COVERAGE_MIN=75 <skill>/setup.sh                    # project with its own bar
```

**Add or remove a dev package**: edit `assets/dev-packages.txt`, one package per
line. Sail's containers are the same idea in `assets/sail-services.txt`.

**Change the deploy pipeline** (a new CI step, another excluded path, a
different post-deploy command): edit `assets/deploy.yml`. The per-project bits
are placeholders (`__REMOTE_PATH__`, `__BRANCH__`, `__PHP_VERSION__`,
`__NODE_VERSION__`, `__REMOTE_PHP__`, `__REMOTE_COMPOSER__`) filled in by
`modules/80-deploy.sh` — add a placeholder there when something else turns out
to differ per project, rather than telling the user to hand-edit the workflow.

**Add a whole new step**: copy `modules/TEMPLATE.sh.example` to
`modules/NN-name.sh`, where `NN` orders it against the existing steps. It is
picked up automatically — there is no registry to update. The template documents
the helpers available (`run`, `install_asset`, `set_env_var`,
`merge_composer_scripts`, `artisan_has`, …) and the two rules that matter: call
tools through `$COMPOSER_CMD`/`$ARTISAN_CMD`/`$PHP_CMD` so Sail keeps working, and wrap side
effects in `run` so `--dry-run` stays honest.

**Remove a step**: delete its file, or set `# default: off` in its header if it
should stay available on demand.

**Make a step a per-project question**: add an `# ask:` line to its header. The
runner then refuses to decide it silently — exactly how `ptbr` works.

After changing anything, `--dry-run` on a real project is the cheap check.

## Reporting back

After a run, tell the user which steps ran, which were skipped and why, and what
to do next — normally `composer quality` (pint → stan → test). If any step
failed, say which and give the `--only <name>` command to retry it rather than
suggesting the whole setup be run again.
