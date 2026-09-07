#!/bin/bash
# Install the status line for Claude Code.
# Part of claude-dipstick: https://github.com/heathdutton/claude-dipstick
#
#   bash install.sh          link it and point settings.json at it
#   bash install.sh --check   say what is wired, change nothing
#
# Two halves, both idempotent:
#   1. ~/.claude/statusline.sh is symlinked at statusline.sh in this checkout,
#      so a `git pull` here takes effect on the next render with no re-install.
#   2. enable.py points statusLine (and subagentStatusLine) in
#      ~/.claude/settings.json at that link, backing the file up first if it
#      held someone else's command.
#
# Opt a machine out of the settings half with: touch ~/.claude/.no-repo-statusline
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SRC="$ROOT/statusline.sh"
LINK="$HOME/.claude/statusline.sh"
check=0
[ "${1:-}" = "--check" ] && check=1

if [ ! -f "$SRC" ]; then
  echo "no statusline.sh above tools/ -- run this from inside the checkout" >&2
  exit 1
fi

if [ "$check" = 1 ]; then
  printf 'source    %s\n' "$SRC"
  printf 'link      %s\n' "$([ -L "$LINK" ] && readlink "$LINK" || echo 'not a symlink')"
  printf 'settings  %s\n' "$(python3 - <<'PY' 2>/dev/null || echo '?'
import json, pathlib
p = pathlib.Path.home() / ".claude/settings.json"
try:
    print(json.loads(p.read_text()).get("statusLine", {}).get("command", "unset"))
except Exception:
    print("unset")
PY
)"
  exit 0
fi

mkdir -p "$HOME/.claude"

# A real file here is someone's own status line, not ours to delete.
if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
  backup="$LINK.bak.$(date +%Y%m%d-%H%M%S)"
  mv "$LINK" "$backup"
  echo "  statusline.sh -- moved existing file to $(basename "$backup")"
fi

if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$SRC" ]; then
  echo "  statusline.sh -- already linked"
else
  ln -sfn "$SRC" "$LINK"
  echo "  statusline.sh -- linked"
fi

if command -v python3 >/dev/null 2>&1; then
  echo "  settings.json -- $(python3 "$HERE/enable.py" 2>&1 || echo 'left alone (see above)')"
else
  echo "  no python3 -- add this to ~/.claude/settings.json by hand:"
  echo '      "statusLine": { "type": "command", "command": "bash \"$HOME/.claude/statusline.sh\"" }'
fi

echo
echo "Check it with: bash $HERE/selftest.sh"
