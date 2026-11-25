#!/usr/bin/env bash
# Point this checkout at your own Apple Developer team and your own bundle ids.
#
#   scripts/set-signing.sh <TEAM_ID> <bundle-prefix>
#   scripts/set-signing.sh ABCDE12345 com.example.mercurio
#
# Why: an App ID and an App Group are unique across all of Apple. The ids this
# repository ships belong to its maintainers, so your team cannot register them.
# This rewrites the ids and the team in the files that name them, then you run
# `make install` (it regenerates Mercurio.xcodeproj from project.yml). Keep the
# result on a local branch and do not commit it to a pull request.
#
# It uses perl, not sed -i, so it behaves the same on macOS and Linux.
set -euo pipefail

OLD="solutions.ormus.mercurio"
team="${1:-}"
prefix="${2:-}"
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || { echo "TEAM_ID must be 10 letters or digits (Apple Developer > Membership)" >&2; exit 2; }
[[ "$prefix" =~ ^[a-z0-9]+(\.[a-z0-9-]+)+$ ]] || { echo "bundle prefix must look like com.example.mercurio (lowercase, dot-separated)" >&2; exit 2; }
[[ "$prefix" != "$OLD" ]] || { echo "choose a prefix of your own, not the shipped one" >&2; exit 2; }

cd "$(cd "$(dirname "$0")" && pwd)/.."
[[ -f project.yml ]] || { echo "run from a Mercurio checkout" >&2; exit 1; }

# Every file that holds the shipped prefix, as a bundle id, an app group, a
# keychain service or a log label. They must all change together: the app
# group in the entitlements has to match the one in NotificationKeyStore.swift.
files=$(grep -rlF "$OLD" project.yml Makefile Sources Packages Tests \
    --include='*.yml' --include='Makefile' --include='*.swift' --include='*.plist' \
    --include='*.entitlements' --include='*.c' || true)
[[ -n "$files" ]] || { echo "nothing to rewrite: already done?" >&2; exit 1; }

OLD="$OLD" NEW="$prefix" xargs perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' <<<"$files"
TEAM="$team" perl -pi -e 's/^(\s*DEVELOPMENT_TEAM:\s*).*$/$1"$ENV{TEAM}"/' project.yml

echo "team $team and prefix $prefix written to $(wc -l <<<"$files" | tr -d ' ') files (project.yml included)."
echo "Next: make install   (or make test)"
