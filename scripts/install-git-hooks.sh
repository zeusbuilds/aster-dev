#!/bin/sh
# Install git hooks from scripts/git-hooks/ into .git/hooks/.
# Run once after clone: ./scripts/install-git-hooks.sh

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_SRC="$ROOT/scripts/git-hooks"
HOOKS_DST="$ROOT/.git/hooks"

if [ ! -d "$ROOT/.git" ]; then
  echo "Not a git repo. Run from project root."
  exit 1
fi

for hook in "$HOOKS_SRC"/*; do
  [ -f "$hook" ] || continue
  name="$(basename "$hook")"
  dest="$HOOKS_DST/$name"
  cp "$hook" "$dest"
  chmod +x "$dest"
  echo "Installed hook: $name"
done

echo "Git hooks installed. Pre-commit will run format and analyze."
