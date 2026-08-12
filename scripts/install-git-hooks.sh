#!/bin/sh
# Configure this repository to use its versioned hook directory.

set -eu
ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
HOOKS_PATH="scripts/git-hooks"
CURRENT="$(git -C "$ROOT" config --local --get core.hooksPath || true)"

if [ -n "$CURRENT" ] && [ "$CURRENT" != "$HOOKS_PATH" ]; then
  echo "Refusing to replace existing local core.hooksPath: $CURRENT" >&2
  exit 1
fi

git -C "$ROOT" config --local core.hooksPath "$HOOKS_PATH"
echo "Git hooks path configured for this repository: $HOOKS_PATH"
