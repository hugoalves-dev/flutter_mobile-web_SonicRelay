# Release Tags Without Build Number Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Release tags and assets use `v<major>.<minor>.<patch>`; CI bumps the patch when that name is already released.

**Architecture:** Move version resolution out of the `version` job's inline bash into a pure script that reads existing tags on stdin and prints `GITHUB_OUTPUT` lines. A shell test exercises it; the job runs the test, then the script.

**Tech Stack:** Bash, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-19-release-tags-without-build-number-design.md`

## Global Constraints

- Version name format: `^[0-9]+\.[0-9]+\.[0-9]+$` (unchanged error text: `Releases require a versionName in major.minor.patch format, found '<name>'.`).
- Build number: `max(ANDROID_VERSION_CODE_OFFSET + GITHUB_RUN_NUMBER, pubspec build + 1, latest legacy v*+N tag + 1)` — same as today.
- Tag: `v<name>`. A name is "taken" if tag `v<name>` or any `v<name>+<digits>` exists (exact match, dots literal).
- Existing tags are never modified.

## Review Focus

- Regex lookalikes: `v11.10.0`, `v1.10.0-beta`, `v1x10x0` must not mark `1.10.0` as taken → test `taken_name_matching_is_exact`.
- Several consecutive taken patches (`v1.10.0`, `v1.10.1+N`, `v1.10.2`) → resolves `1.10.3` → test `bumps_past_mixed_tag_styles`.
- pubspec version without `+build` → build from run number → test `pubspec_without_build_number`.
- Non-numeric pubspec build (`1.10.0+abc`) → exit 1 → test `rejects_invalid_build_number`.
- No tags at all (fresh clone) → name unchanged → test `no_tags_keeps_pubspec_name`.

---

### Task 1: Version resolution script

**Files:**
- Create: `.github/scripts/resolve-release-version.sh`
- Test: `.github/scripts/resolve-release-version.test.sh`

**Interfaces:**
- Produces: `resolve-release-version.sh <pubspec_version> <offset> <run_number>`; existing tags one per line on stdin; prints exactly three lines `version_name=<name>`, `version_code=<code>`, `tag=v<name>`; exit 1 with message on stderr for invalid input.

- [ ] **Step 1: Write the failing test** — bash test runner with `assert_resolves <pubspec> <offset> <run> <tags> <expected name> <expected code>` and `assert_fails`. Cases:
  - `no_tags_keeps_pubspec_name`: `1.10.0+100165`, 100000, 70, no tags → `1.10.0`, `100166`, tag `v1.10.0`
  - `bumps_past_legacy_tag`: tags `v1.10.0+100165` → `1.10.1`, `100166`
  - `bumps_past_mixed_tag_styles`: tags `v1.10.0`, `v1.10.1+100170`, `v1.10.2` → `1.10.3`, `100171`
  - `run_number_baseline_wins`: run 300 → code `100300`
  - `legacy_tag_code_wins`: tags `v1.9.0+100170`, pubspec `1.10.0+100165` → `1.10.0`, `100171`
  - `taken_name_matching_is_exact`: tags `v11.10.0`, `v1.10.0-beta`, `v1x10x0` → `1.10.0`
  - `pubspec_without_build_number`: `1.10.0`, run 5 → `100005`
  - `rejects_invalid_name`: `1.10+5` → fails
  - `rejects_invalid_build_number`: `1.10.0+abc` → fails
- [ ] **Step 2: Run** `bash .github/scripts/resolve-release-version.test.sh` — Expected: FAIL (script missing).
- [ ] **Step 3: Implement the script** — logic ported from the current `version` job; name loop: `while grep -Eq "^v${escaped}(\+[0-9]+)?$"; do patch++`.
- [ ] **Step 4: Run test** — Expected: all cases PASS, exit 0.
- [ ] **Step 5: Commit** `ci: resolve release version in a tested script`

### Task 2: Wire into workflow and document

**Files:**
- Modify: `.github/workflows/flutter-ci.yml` (`version` job, "Resolve version and release eligibility" step)
- Modify: `AGENTS.md` (versioning section)

**Interfaces:**
- Consumes: Task 1 script. Job outputs `version_name`, `version_code`, `tag` keep their names, so `release` and `deploy-play` need no change.

- [ ] **Step 1:** Replace inline resolution with: run the test script, then `git tag --list | resolve-release-version.sh "$VERSION_DECLARATION" "$ANDROID_VERSION_CODE_OFFSET" "$GITHUB_RUN_NUMBER" >> "$GITHUB_OUTPUT"`; keep `should_release` logic and the "Resolved release" log line.
- [ ] **Step 2:** `AGENTS.md`: tag format `v<major>.<minor>.<patch>`; CI bumps patch if the name is already released (including CI/docs-only pushes); legacy `v*+*` tags still feed the build number.
- [ ] **Step 3: Verify** — run the test script; run the step's command locally against `git tag --list` with current pubspec → expect `version_name=1.10.1`, `tag=v1.10.1`; YAML parses (`python -c yaml.safe_load` or `actionlint` if available).
- [ ] **Step 4: Commit** `ci: tag releases without the build number`
