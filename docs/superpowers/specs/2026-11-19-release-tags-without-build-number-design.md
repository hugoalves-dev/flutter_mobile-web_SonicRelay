# Release tags without the build number

## Why

F-Droid asked (fdroiddata!58182) to drop the build number from release tags. F-Droid's
`checkupdates` copies each build's `binary:` URL verbatim to the next version; only `%v`
(versionName) and `%c` (F-Droid versionCode) are expanded at build time. With tags like
`v1.8.0+100159` the reference-APK URL cannot be expressed with `%v`/`%c`, so every update
points at the previous release and the reproducible-build check fails (issue #67).
With `v1.10.1` tags, `.../download/v%v/sonic-relay-<abi>-fdroid-v%v.apk` stays correct forever.

## Goals / non-goals

- Goal: tags and release asset names contain only `v<major>.<minor>.<patch>`.
- Goal: every push to `main` still produces a release (current behavior) with a unique tag.
- Non-goal: changing how the build number (versionCode) is computed; it stays
  `max(100000 + run number, pubspec build + 1, latest legacy tag build + 1)`.
- Non-goal: rewriting or deleting existing `v*+*` tags.
- Anti-goal: two releases sharing a tag, or a release reusing a version name already
  published under a legacy `v<name>+<build>` tag.

## Approaches

1. **Auto-bump patch when the version name is already released** (chosen). Every push still
   releases; versions advance without manual action. Trade-off: CI/docs-only pushes produce a
   patch release.
2. Release only when the version name changes. Rejected: pushes without a bump publish nothing,
   including to Google Play.
3. Fail CI when the tag exists. Rejected: blocks every push that doesn't bump.

## Design

- Version resolution moves from inline YAML to `.github/scripts/resolve-release-version.sh`
  (pure function of: pubspec `version:` value, existing tag list, run number, offset), with a
  shell test `.github/scripts/resolve-release-version.test.sh` run by the `version` job before use.
- Version name: start from pubspec `major.minor.patch`; while `v<name>` or any `v<name>+*` tag
  exists, increment patch.
- Tag: `v<name>`. Release assets inherit it (`sonic-relay-armeabi-v7a-fdroid-v1.10.1.apk`, ...).
- The bumped name flows unchanged into the persisted `pubspec.yaml`, the release and Play deploy.
- `AGENTS.md`: document the new tag format and that CI auto-bumps the patch when the version
  name is already released.
- fdroiddata (separate MR update, after the first new-style release):
  `UpdateCheckMode: Tags ^v[0-9]+\.[0-9]+\.[0-9]+$`,
  `UpdateCheckData: pubspec.yaml|version:\s.+\+(\d+)|.|version:\s(.+)\+`,
  `binary: .../releases/download/v%v/sonic-relay-<abi>-fdroid-v%v.apk`.

## Left to the builder

- Exact script interface and test layout, as long as the workflow behavior above holds.
