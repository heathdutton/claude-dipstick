#!/usr/bin/env python3
"""Point ~/.claude/settings.json at the claude-dipstick status line.

Part of claude-dipstick: https://github.com/heathdutton/claude-dipstick

Called by install.sh, so a checkout picks up the status line without
anyone touching settings by hand. Idempotent: prints "already set" and exits when it's already ours.

Escape hatch: touch ~/.claude/.no-repo-statusline and this leaves settings
alone forever.

Exit codes: 0 changed/no-op, 1 couldn't (bad JSON, missing file...).
"""

import json
import shutil
import sys
import time
from pathlib import Path

COMMAND = 'bash "$HOME/.claude/statusline.sh"'
# refreshInterval re-runs the line on a timer as well as on events, so the reset clocks, pace markers and cache flame
# keep moving while a session idles. One render a minute, ~80ms of it.
DESIRED = {"type": "command", "command": COMMAND, "refreshInterval": 60}
# The same script draws the agent-panel rows: it sees "tasks" on stdin and answers one JSON line per row.
DESIRED_SUBAGENT = {"type": "command", "command": COMMAND}


def main() -> int:
    claude_dir = Path.home() / ".claude"
    settings = claude_dir / "settings.json"

    if (claude_dir / ".no-repo-statusline").exists():
        print("opted out (.no-repo-statusline)")
        return 0

    if settings.exists():
        try:
            data = json.loads(settings.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            print(f"cannot read settings.json ({exc})", file=sys.stderr)
            return 1
        if not isinstance(data, dict):
            print("settings.json is not an object", file=sys.stderr)
            return 1
    else:
        data = {}

    current = data.get("statusLine")
    if current == DESIRED and data.get("subagentStatusLine") == DESIRED_SUBAGENT:
        print("already set")
        return 0

    # Clobber someone else's status line once, keeping a copy of the file so the old command is recoverable.
    if settings.exists():
        stamp = time.strftime("%Y%m%d-%H%M%S")
        shutil.copy2(settings, settings.with_suffix(f".json.bak.{stamp}"))

    data["statusLine"] = DESIRED
    data["subagentStatusLine"] = DESIRED_SUBAGENT
    settings.write_text(json.dumps(data, indent=2) + "\n")

    if current:
        print(f"replaced {current.get('command', current)!r}")
    else:
        print("enabled")
    return 0


if __name__ == "__main__":
    sys.exit(main())
