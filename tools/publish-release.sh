#!/bin/sh
# Publishes the RPM built for the version in the spec as a GitHub release, which the app's own update check finds.
# The tag is "<version>-<release>" (e.g. 0.3.0-8). Refuses when the source of the RPM is not on GitHub: the working
# tree must be clean and the current commit must be the head of main there.
set -e
cd "$(dirname "$0")/.."
REPO=VeniVidiMorti/psa_remote
SPEC=sailfish/rpm/stellamaris.spec
TAG="$(sed -n 's/^Version: *//p' $SPEC)-$(sed -n 's/^Release: *//p' $SPEC)"
RPM="sailfish/RPMS/stellamaris-$TAG.aarch64.rpm"
COMMIT="$(git rev-parse HEAD)"

if [ ! -f "$RPM" ]; then
  echo "$RPM does not exist; build it first." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "The working tree has uncommitted changes; commit and push them first." >&2
  exit 1
fi
if [ "$(gh api "repos/$REPO/commits/main" --jq .sha)" != "$COMMIT" ]; then
  echo "The current commit is not the head of main on GitHub; push it first." >&2
  exit 1
fi

gh release create "$TAG" "$RPM" --repo "$REPO" --target "$COMMIT" --title "PSA Remote $TAG" --generate-notes
