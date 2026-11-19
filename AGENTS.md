# AGENTS.md

Repository-wide instructions for coding agents working on **SonicRelay**.

## Release versioning

Keep the semantic version name in `pubspec.yaml` under manual control:

```yaml
version: <major>.<minor>.<patch>+<buildNumber>
```

Before finishing any application `feat`, `fix`, or `refactor`, increment the semantic version name exactly once according to Semantic Versioning:

- `MAJOR`: incompatible or breaking application changes.
- `MINOR`: backward-compatible features or new user-facing capabilities.
- `PATCH`: backward-compatible fixes, refactors, performance improvements, or internal application changes.

When a change fits more than one category, use the highest applicable level. Reset the lower components normally: `MAJOR` resets `MINOR` and `PATCH` to `0`; `MINOR` resets `PATCH` to `0`.

Change only `<major>.<minor>.<patch>`. Preserve `<buildNumber>` exactly as it is and never increment it manually — the `CI/CD` workflow owns it. It resolves a build number greater than both the current `pubspec.yaml` build number and the latest legacy `v*+*` release tag, using the `100000 + GITHUB_RUN_NUMBER` baseline (see `.github/scripts/resolve-release-version.sh`).

Release tags and release assets carry only the version name: `v<major>.<minor>.<patch>` (for example `v1.10.1`), never the build number. F-Droid's metadata builds its reference-APK URLs from that name. Every push to `main` releases; when `pubspec.yaml`'s version name is already released (as `v<name>` or a legacy `v<name>+<build>` tag), CI bumps the patch until the name is free. Pushes that follow the rule below and leave the version unchanged therefore still publish a patch release.

Then the workflow:

1. persists the resolved version in `pubspec.yaml`;
2. commits it to `main` as `github-actions[bot]`;
3. creates the release tag on that exact version commit;
4. publishes the GitHub Release;
5. calls `.github/workflows/android-play-deploy.yml` with that same version name, build number, and release commit.

Do not increment the semantic version for documentation-only, test-only, CI/workflow-only, changelog-only, or agent-instruction-only changes that do not modify the application.

## Changelog

Follow the localization and Google Play release-note requirements in `.claude/CLAUDE.md`. Keep `CHANGELOG.xml` as the single source of truth for release notes.

For every user-visible `feat`, `fix`, or `refactor`, replace the entire previous content of `CHANGELOG.xml` with notes for the new change. Never append the new notes to older release notes. The file must remain directly copyable into the Google Play Console release notes field.

When publishing a GitHub Release, the `CI/CD` workflow converts the locale blocks from `CHANGELOG.xml` to Markdown headings and preserves the localized bullet text. Do not maintain a second hand-written changelog.
