#!/usr/bin/env bash
# Resolves the release version name, build number and tag.
#
# Usage: git tag --list | resolve-release-version.sh <pubspec_version> <offset> <run_number>
#
# Prints GITHUB_OUTPUT lines: version_name, version_code, tag.
# Tags are v<major>.<minor>.<patch>; when that name is already released (as v<name> or a
# legacy v<name>+<build> tag), the patch is bumped until the name is free.
set -euo pipefail

VERSION_DECLARATION="$1"
OFFSET="$2"
RUN_NUMBER="$3"
EXISTING_TAGS=$(cat)

VERSION_NAME="${VERSION_DECLARATION%%+*}"

if [[ ! "$VERSION_NAME" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Releases require a versionName in major.minor.patch format, found '$VERSION_NAME'." >&2
  exit 1
fi
MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

CURRENT_VERSION_CODE=0
if [[ "$VERSION_DECLARATION" == *+* ]]; then
  CURRENT_VERSION_CODE="${VERSION_DECLARATION##*+}"
fi

if [[ ! "$CURRENT_VERSION_CODE" =~ ^[0-9]+$ ]]; then
  echo "Invalid build number in pubspec.yaml: '$CURRENT_VERSION_CODE'." >&2
  exit 1
fi

LATEST_TAG_VERSION_CODE=$(
  printf '%s\n' "$EXISTING_TAGS" \
    | sed -nE 's/^v[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)$/\1/p' \
    | sort -n \
    | tail -n 1
)
LATEST_TAG_VERSION_CODE="${LATEST_TAG_VERSION_CODE:-0}"

VERSION_CODE=$((OFFSET + RUN_NUMBER))

if (( VERSION_CODE <= CURRENT_VERSION_CODE )); then
  VERSION_CODE=$((CURRENT_VERSION_CODE + 1))
fi

if (( VERSION_CODE <= LATEST_TAG_VERSION_CODE )); then
  VERSION_CODE=$((LATEST_TAG_VERSION_CODE + 1))
fi

is_released() {
  # Here-string, not a pipe: with pipefail, grep -q exiting early would SIGPIPE the writer
  # on large tag lists and make a taken name look free.
  grep -Eq "^v${MAJOR}\.${MINOR}\.$1(\+[0-9]+)?$" <<< "$EXISTING_TAGS"
}

while is_released "$PATCH"; do
  PATCH=$((PATCH + 1))
done

VERSION_NAME="${MAJOR}.${MINOR}.${PATCH}"

echo "version_name=$VERSION_NAME"
echo "version_code=$VERSION_CODE"
echo "tag=v$VERSION_NAME"
