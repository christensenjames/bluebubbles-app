# BlueBubbles autonomous recon

## Remote and deliverable shape

- `git remote -v`:
  ```text
  origin  https://github.com/christensenjames/bluebubbles-app.git (fetch)
  origin  https://github.com/christensenjames/bluebubbles-app.git (push)
  upstream  https://github.com/BlueBubblesApp/bluebubbles-app.git (fetch)
  upstream  https://github.com/BlueBubblesApp/bluebubbles-app.git (push)
  ```
- `origin` is James Christensen's fork; `upstream` exists and is the BlueBubblesApp repository.
- The checked-out James branch is `feat/send-emoji-tapbacks`. `git log -1 --format='%H%n%an%n%ae%n%s'` reported HEAD `aaba4982a7a14c72d40494fb42e0d4043cc29a2e`, author James Christensen, and subject `fix: keep the mark-read button live and ignore deleted rows and tapbacks`.
- `git remote show origin` and `git remote show upstream` report `master` as each remote's HEAD branch. Local `master`, `origin/master`, and `upstream/master` are all `e2eaced6e61eee746757a070475197bf23b671ad`; `origin/development` and `upstream/development` are both `e4148c529ef0b0a06f251131dbdb3efa2fb5c66c`.
- `git branch -vv` shows `master` tracking `origin/master` and `fix/receive-emoji-tapbacks` tracking `origin/fix/receive-emoji-tapbacks`; the current James branch has no configured tracking branch.
- `git status --short --branch --untracked-files=all` reported the current branch and an unrelated untracked `bluebubbles-linux-x86_64.tar.gz`. That archive was not changed.
- A remote exists, so deliverables have PR shape: topic branches can be pushed to `origin`, with the reviewed PR opened on GitHub. `CONTRIBUTING.md` names `BlueBubblesApp/bluebubbles-app` and `development` as the PR base; `.claude/CLAUDE.md` says branches and PRs target `master`.
- `gh auth status` for `github.com` reported active account `christensenjames`, HTTPS Git operations, and `repo` scope. The token value is intentionally omitted.
- `git push --dry-run origin HEAD:refs/heads/autonomous-recon-probe` completed with:
  ```text
  To https://github.com/christensenjames/bluebubbles-app.git
   * [new branch]      HEAD -> autonomous-recon-probe
  ```
  It did not request a prompt or credential, and it was a dry-run only; no branch was pushed.

## Push tier

- `Green (James: all private repos are green, 2026-09-12)`.
- `--push` applies because this checkout has remotes (`origin` and `upstream`).

## Privacy band

- `pwd` returned `/home/james/Projects/bluebubbles-app`.
- This repository is not in the trainer-denied list (Finances, Health, House, Travel, Personal, or Reference). The Claude/GPT-only restriction therefore does not apply to this repo.

## Worktrees

- `git worktree list` currently reports only the primary checkout:
  ```text
  /home/james/Projects/bluebubbles-app aaba4982a [feat/send-emoji-tapbacks]
  ```
- The batch assumption is that the primary may host other live agent instances.
- `.git/info/exclude` contains only Git's commented template. `.gitignore` has no `.claude/worktrees` or overnight-worktree rule. The directory glob for `/home/james/Projects/bluebubbles-app/.claude/worktrees/**` and the sibling glob for `/home/james/Projects/bluebubbles-app-overnight*` returned no entries.
- Path convention: one unit worktree per sibling directory, `/home/james/Projects/bluebubbles-app-overnight/<unit>`.
- Exact creation command:
  ```bash
  git worktree add -b autonomous/<unit> /home/james/Projects/bluebubbles-app-overnight/<unit> master
  ```
- The sibling location is outside the primary repository because neither the parent `.git/info/exclude` nor `.gitignore` ignores an in-repo worktree directory. It keeps generated worktree output and the primary's existing untracked archive out of the primary status view. The command uses local `master`, which is aligned with both remote `master` refs; the PR-base discrepancy is recorded above and again under unknowns.
- Gitignored input a worktree MUST inherit: `.env`. `pubspec.yaml:316` declares it as an
  asset, so a fresh worktree analyzes at 253 issues instead of the 252 baseline, with the
  extra one being `warning • The asset file '.env' doesn't exist • pubspec.yaml:316:7 •
  asset_does_not_exist`. Link it after `flutter pub get`:
  ```bash
  ln -s /home/james/Projects/bluebubbles-app/.env <worktree>/.env
  ```
  Verified 2026-09-22: 253 issues before the symlink, 252 after, on `master` `e2eaced6e`.
- A fresh worktree has no `.dart_tool`, so the first command in it must be `flutter pub get`
  (~13s); `--no-pub` fails without it. `export PATH="/home/james/sdk/flutter/bin:$PATH"` first.

## Nested checkouts

- `git submodule status --recursive` and `git config --get-regexp '^submodule\.'` produced no output.
- `git ls-files --stage | cut -d ' ' -f1 | sort | uniq -c` reported only `1195 100644` and `2 100755`; `git ls-files --stage | sed -n '/^160000/p'` produced no output, so there are no tracked submodule gitlinks.
- The recursive `.git` and `.gitmodules` globs returned no nested entries. The only Git directory is the primary repository's `.git`.
- A worktree therefore sees the complete tracked app tree with no nested checkout. Git-based Dart dependencies in `pubspec.yaml` resolve into the user package cache, not nested repositories in this checkout.

## Primary-checkout-only tooling

- No primary-checkout-only install, deploy, daemon, or symlink-farm tool was identified in the tracked script/config scan.
- `git ls-files --stage | sed -n '/^120000/p'` produced no output, so no tracked symlink resolves into `~/bin`, `~/.config`, or another deployed path. The tracked install/service filename scan (`install.sh`, `*.service`, `linux/build.sh`, `windows/build.ps1`, and `scripts/*`) found the build/release scripts but no install script or service unit.
- `linux/build.sh` derives the project root from its own script path. `windows/build.ps1` changes to the directory derived from `$PSScriptRoot`. `scripts/bump_desktop_versions.dart` is documented as runnable from any cwd. These scripts do not require the primary checkout and can resolve their paths from a worktree.
- The app's runtime `launch_at_startup.dart` can write a user autostart entry under `$HOME/.config/autostart`; this is application behavior, not a repo setup/deploy command.

## Worktree symlinks

- `stat -c '%F %N' .env .dart_tool` reported a regular `.env` file and a `.dart_tool` directory. `git check-ignore -v .env .dart_tool .dart_tool/package_config.json .flutter-plugins-dependencies build` reported `.env` ignored by `.gitignore:52:*.env`, `.dart_tool/*` ignored by `.gitignore:49:.dart_tool/*`, `.flutter-plugins-dependencies` ignored by `.gitignore:27:.flutter-plugins-dependencies`, and `build` ignored by `.gitignore:31:/build/`.
- `.env` is a required config/build input: `pubspec.yaml` lists it as an asset and `lib/main.dart` loads dotenv on desktop. The value is not recorded here. Link the primary file into each worktree without copying it:
  ```bash
  ln -s /home/james/Projects/bluebubbles-app/.env /home/james/Projects/bluebubbles-app-overnight/<unit>/.env
  ```
- `.dart_tool` is an approximately 870M generated tree. It is not a safe shared worktree symlink: `.dart_tool/flutter_build/32359ed28144451271b8330b2e371281/dart_build_result.json` contains an absolute dependency reference to `/home/james/Projects/bluebubbles-app/.dart_tool/package_config.json`. Regenerate `.dart_tool` in each worktree with the lockfile-enforced Pub command instead of sharing the primary's generated build state.
- `.flutter-plugins-dependencies` and `build/` are generated and ignored; they are regenerated by the same dependency/build flow, not symlinked. No ignored virtualenv, `node_modules`, or test-fixture directory was found.

## Build / lint / test

All Flutter builds below are long and were intentionally not run for this recon; each is **unverified**.

- Flutter/FVM setup from `.github/actions/setup-flutter/action.yml`: `dart pub global activate fvm 4.1.2`, `dart pub global run fvm:main use 3.44.6 --force`, and `dart pub global run fvm:main flutter pub get --enforce-lockfile` — unverified.
- Dependency commands documented in `CONTRIBUTING.md`: `fvm flutter pub get` or `flutter pub get` — unverified.
- CI analyzer: `fvm flutter analyze --no-pub --no-fatal-infos` — unverified. The repo's `analysis_options.yaml` includes `flutter_lints` and sets the line width to 120.
- Formatting: `dart format ./ --line-length=120` — unverified.
- Common fixer: `bash scripts/dart-fix-common-issues.sh` — unverified; it applies edits and is not an audit-only read.
- ObjectBox generation after editing an entity: `dart run build_runner build` — unverified.
- Linux release workflow: `FLUTTER_CMD=flutter bash linux/build.sh` — unverified. The script runs lockfile-enforced Pub, `flutter build linux --release -v --no-pub`, then packages the release tarball. The direct CI compile command is `fvm flutter build linux --release -v --no-pub` — unverified.
- Windows CI compile: `fvm flutter build windows --release -v --no-pub` — unverified. Windows release phases are `.\windows\build.ps1 -Phase Build` and `.\windows\build.ps1 -Phase Package` from a Windows shell; both are unverified here.
- Android CI compile: `fvm flutter build apk --release --flavor prod --no-pub` — unverified. The tag workflow also expands its matrix to `fvm flutter build appbundle --release --flavor prodNoAa --no-pub` — unverified.
- Manual runtime verification documented by `CONTRIBUTING.md`: `fvm flutter run` or `flutter run` — unverified.
- `.claude/CLAUDE.md` states there is no automated test suite and requires target-platform verification. The command `test -d test && printf 'test directory exists\n' || printf 'no test directory\n'; test -d integration_test && printf 'integration_test directory exists\n' || printf 'no integration_test directory\n'; git ls-files -- 'test/**' 'integration_test/**'` returned `no test directory` and `no integration_test directory` with no tracked test paths. No test command is recorded.

## Issue tracker and MCP surfaces

- Repo documentation names GitHub Issues as the issue tracker (`README.md` links to `https://github.com/BlueBubblesApp/bluebubbles-app/issues`; `CONTRIBUTING.md` sends contributors to that issues page) and GitHub Pull Requests for delivery.
- GitHub mutations visible in repo configuration are pushes to `origin`, PR creation/review on GitHub, and tag-triggered release workflows that upload/attach artifacts. The desktop workflow's `gh release view` check is read-only. No repo-owned Linear/MCP, Home Assistant, Radarr, mail, deployment, or daemon CLI surface was found in the targeted docs/scripts/config search.
- `$HOME/bin/linear-chr` is available for raw GraphQL and is a CHR-workspace tool, but no repo document maps this checkout to CHR. The read-only CHR query in the ledger section returned 41 open/backlog issues, `hasNextPage: false`, and no title/description/URL match for `bluebubbles-app` or `BlueBubbles`.
- No analytics, error-tracker, coverage, or log endpoint is named in the repo docs/workflows. The PR workflow provides analyzer and unsigned compile signals only.

## Ledgers to seed the queue from

Ranked sources, with paths and rationale; ledger content is not copied here:

1. `/home/james/Projects/bluebubbles-app/handoff.md` — highest priority because its `Continue` and `Waiting On` sections contain the current session's open work and external dependencies.
2. `/home/james/Projects/bluebubbles-app/plans/` (`README.md`, `001-shorten-received-message-insertion.md`, `002-typing-indicator-scale-from-zero.md`, `003-ease-in-on-text-field-pickers.md`, `004-reaction-details-route-duration.md`) — dedicated animation ledger; the README table marks all four plans `DONE`, so it is primarily a stale-gap check rather than an open queue.
3. `/home/james/Projects/bluebubbles-app/CHANGELOG.md` — current decisions and recently landed work; useful for avoiding duplicate proposals and preserving deliberate non-changes.
4. `https://github.com/BlueBubblesApp/bluebubbles-app/issues` — the repo-named external issue ledger. `gh issue list --repo BlueBubblesApp/bluebubbles-app --state open --limit 100 --json number,title,url | jq 'length'` returned `100`, which is the requested list cap rather than a total.
5. `~/.claude/papercuts.md:286` — the only matching `bluebubbles-app` entry from a `functions.grep` call with pattern `bluebubbles-app` and path `/home/james/.claude/papercuts.md`; it records recent workflow friction and is lower priority than product work.
6. `TODOS.md` — **None**. `git ls-files -- TODOS.md PRODUCT.md DESIGN.md '**/TODOS.md' '**/PRODUCT.md' '**/DESIGN.md'` produced no output, and the corresponding file globs found no files.
7. `PRODUCT.md` / `DESIGN.md` — **None** in this checkout; the same tracked-file command and globs returned no files.
8. CHR open issues — **None matched**. The read-only command was:
   ```bash
   $HOME/bin/linear-chr 'query { issues(first: 100, filter: { team: { key: { eq: "CHR" } }, state: { type: { nin: ["completed", "canceled"] } } }) { nodes { identifier title description url } pageInfo { hasNextPage endCursor } } }' | jq '{count:(.data.issues.nodes|length), pageInfo:.data.issues.pageInfo, matches:[.data.issues.nodes[] | select((.title + " " + (.description // "") + " " + .url) | test("bluebubbles-app|BlueBubbles"; "i")) | {identifier,title,url}]}'
   ```
   It returned `count: 41`, `hasNextPage: false`, and an empty `matches` array.
9. In-code TODO/FIXME scan — lowest-ranked until each placeholder is classified: `git grep -n -E 'TODO|FIXME' -- '*.dart' '*.cc' '*.cpp' '*.h' '*.kt' '*.swift' | wc -l` returned `12`; the corresponding `FIXME` scan returned `0`.

## Unable to determine

- The PR base branch is unresolved because `.claude/CLAUDE.md` says `master` while `CONTRIBUTING.md` says upstream `development`; both refs exist and `master` is each remote's HEAD.
- Build success, manual target-platform behavior, and actual build duration are unverified because Flutter builds were intentionally not run. The repo documents no automated test suite.
- The GitHub issue list command was capped at 100, so its total open-issue count and repo-specific issue mapping were not determined. No CHR issue matched the exhaustive 41-item query. No repo-defined quality/usage signal endpoint was determined.
