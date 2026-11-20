#!/usr/bin/env python3
"""Point ~/.claude/settings.json at the claude-dipstick status line, and install the mod that draws the agent rows.

Part of claude-dipstick: https://github.com/heathdutton/claude-dipstick

Called by install.sh, so a checkout picks up the status line without
anyone touching settings by hand. Idempotent: prints "already set" and exits when it's already ours.
--status prints one line on the mod and changes nothing.

Claude Code deprecates subagentStatusLine in favor of mods, so the agent panel's rows come from the mod in mod/. It's
installed from this checkout as a folder marketplace, which Claude Code reads from the folder itself, so a git pull
reaches the next session. Our subagentStatusLine goes only once the mod is installed. A machine that can't install it
(no claude command, a policy against folder marketplaces) keeps styled rows for as long as Claude Code honors it.

Escape hatch: touch ~/.claude/.no-repo-statusline and this leaves settings
and plugins alone forever.

Exit codes: 0 changed/no-op, 1 couldn't (bad JSON, missing file...), 2 an argument it doesn't know.
"""

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

COMMAND = 'bash "$HOME/.claude/statusline.sh"'
# refreshInterval re-runs the line on a timer as well as on events, so the reset clocks, pace markers and cache flame
# keep moving while a session idles. One render a minute, ~80ms of it.
DESIRED = {"type": "command", "command": COMMAND, "refreshInterval": 60}
# Only where the mod can't be installed: the same script draws the agent-panel rows when it sees "tasks" on stdin.
DESIRED_SUBAGENT = {"type": "command", "command": COMMAND}

PLUGIN = "dipstick"
ROOT = Path(__file__).resolve().parent.parent
# Where Claude Code's installers put it, for a caller whose PATH doesn't reach it (a LaunchAgent's is bare).
CLAUDE_FALLBACKS = (
    "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "~/.local/bin/claude", "~/.claude/local/claude",
)
# A folder install takes seconds. This only bounds a claude that hangs.
INSTALL_TIMEOUT_S = 120


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def marketplace_name():
    """The name this checkout's marketplace file gives, or None for a checkout from before the mod."""
    data = read_json(ROOT / ".claude-plugin" / "marketplace.json")
    name = data.get("name") if isinstance(data, dict) else None
    return name if isinstance(name, str) and name else None


def marketplace_entry(claude_dir, marketplace):
    known = read_json(claude_dir / "plugins" / "known_marketplaces.json")
    entry = known.get(marketplace) if isinstance(known, dict) else None
    return entry if isinstance(entry, dict) else None


def is_this_checkout(entry):
    source = entry.get("source") if isinstance(entry, dict) else None
    if not isinstance(source, dict) or source.get("source") != "directory" or not isinstance(source.get("path"), str):
        return False
    return Path(source["path"]).expanduser().resolve() == ROOT


def source_of(entry):
    """The folder, GitHub repo or URL a marketplace entry reads from."""
    source = entry.get("source") if isinstance(entry, dict) else None
    if not isinstance(source, dict):
        return "an unknown source"
    return str(source.get("path") or source.get("repo") or source.get("url") or source.get("source"))


def plugin_installed(claude_dir, marketplace):
    """Installed at user scope, from whichever copy of the marketplace Claude Code knows by that name."""
    installed = read_json(claude_dir / "plugins" / "installed_plugins.json")
    plugins = installed.get("plugins") if isinstance(installed, dict) else None
    entries = plugins.get(f"{PLUGIN}@{marketplace}") if isinstance(plugins, dict) else None
    return isinstance(entries, list) and any(isinstance(e, dict) and e.get("scope") == "user" for e in entries)


def mod_installed(claude_dir, marketplace):
    return is_this_checkout(marketplace_entry(claude_dir, marketplace)) and plugin_installed(claude_dir, marketplace)


def load_settings(path):
    """(settings, None), or (None, why it can't be read). A missing file reads as an empty object."""
    if not path.exists():
        return {}, None
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        return None, f"cannot read settings.json ({exc})"
    if not isinstance(data, dict):
        return None, "settings.json is not an object"
    return data, None


def find_claude():
    found = shutil.which("claude")
    if found:
        return found
    for candidate in CLAUDE_FALLBACKS:
        path = Path(candidate).expanduser()
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
    return None


def install_mod(claude_dir, marketplace):
    """Install the mod from this checkout at user scope. Returns (installed, note)."""
    claude = find_claude()
    if claude is None:
        return False, "mod not installed: no claude command"

    def plugin(*args):
        return subprocess.run([claude, "plugin", *args], capture_output=True, text=True, stdin=subprocess.DEVNULL,
                              timeout=INSTALL_TIMEOUT_S)

    try:
        # Claude Code refuses an install from this folder while the name points at another copy (the sync app's
        # clone, a moved checkout, GitHub), so that one goes first.
        entry = marketplace_entry(claude_dir, marketplace)
        if entry is not None and not is_this_checkout(entry):
            plugin("marketplace", "remove", marketplace)
        result = plugin("install", PLUGIN, "--marketplace", str(ROOT), "--scope", "user")
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, f"mod not installed: {exc}"

    if mod_installed(claude_dir, marketplace):
        return True, "installed the agent-row mod"
    said = (result.stderr or result.stdout).strip().splitlines()
    return False, f"mod not installed: {said[-1] if said else f'claude exited {result.returncode}'}"


def describe(line):
    return line.get("command", line) if isinstance(line, dict) else repr(line)


def status():
    """One line on the mod, for install.sh --check and the selftest."""
    marketplace = marketplace_name()
    if marketplace is None:
        return "none in this checkout"
    claude_dir = Path.home() / ".claude"
    if not plugin_installed(claude_dir, marketplace):
        return "not installed"
    entry = marketplace_entry(claude_dir, marketplace)
    line = f"{PLUGIN}@{marketplace}, read from {ROOT / 'mod' if is_this_checkout(entry) else source_of(entry)}"
    settings, _ = load_settings(claude_dir / "settings.json")
    enabled = settings.get("enabledPlugins") if settings else None
    if isinstance(enabled, dict) and enabled.get(f"{PLUGIN}@{marketplace}") is False:
        line += ", disabled"
    return line


def main() -> int:
    if sys.argv[1:] == ["--status"]:
        print(status())
        return 0
    if sys.argv[1:]:
        print("usage: enable.py [--status]", file=sys.stderr)
        return 2

    claude_dir = Path.home() / ".claude"
    settings = claude_dir / "settings.json"

    if (claude_dir / ".no-repo-statusline").exists():
        print("opted out (.no-repo-statusline)")
        return 0

    # Read before the install too. claude writes this file, and one that won't parse is its owner's to fix first.
    _, error = load_settings(settings)
    if error:
        print(error, file=sys.stderr)
        return 1

    notes = []
    marketplace = marketplace_name()
    mod_on = marketplace is not None and mod_installed(claude_dir, marketplace)
    if marketplace is not None and not mod_on:
        mod_on, note = install_mod(claude_dir, marketplace)
        notes.append(note)

    # Read again, since `claude plugin install` writes enabledPlugins here and the first copy would lose it.
    data, error = load_settings(settings)
    if data is None:
        print(error, file=sys.stderr)
        return 1

    changes = []
    current = data.get("statusLine")
    if current != DESIRED:
        data["statusLine"] = DESIRED
        changes.append(f"replaced {describe(current)}" if current else "enabled")

    subagent = data.get("subagentStatusLine")
    if mod_on:
        if subagent == DESIRED_SUBAGENT:
            del data["subagentStatusLine"]
            changes.append("dropped subagentStatusLine")
        elif subagent is not None:
            notes.append(f"kept a subagentStatusLine that isn't ours ({describe(subagent)})")
    elif subagent != DESIRED_SUBAGENT:
        data["subagentStatusLine"] = DESIRED_SUBAGENT
        changes.append("added subagentStatusLine")

    if changes:
        # Someone else's line gets clobbered, so keep a copy of the file and the old command stays recoverable.
        if settings.exists():
            stamp = time.strftime("%Y%m%d-%H%M%S")
            shutil.copy2(settings, settings.with_suffix(f".json.bak.{stamp}"))
        settings.write_text(json.dumps(data, indent=2) + "\n")

    print(", ".join(notes + changes) or "already set")
    return 0


if __name__ == "__main__":
    sys.exit(main())
