# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A status line for Claude Code. The product is one file, `statusline.sh`: no build, no dependencies, installed by
copying or symlinking it to `~/.claude/statusline.sh`. `tools/` holds the installer, the test, and the generators for
the README's images. README.md documents every element for users.

## Commands

- `bash tools/selftest.sh` is the test suite. Sequential, stops at the first `FAIL`, fast enough that there's no
  per-test runner. After reporting the real wiring it sandboxes `HOME`, so its renders never write to `~/.claude`.
- Render by hand in a throwaway home, clock and width pinned:
  `HOME=$(mktemp -d) COLUMNS=160 CLAUDE_STATUSLINE_NOW=1790000000 bash statusline.sh < payload.json`.
  Payload shapes are `payload()` and `fit_payload` in `tools/selftest.sh`. Export any config key for one run
  (`BAR_WIDTH=20`). Read it plain with `perl -pe 's/\e\]8;;[^\a]*\a//g; s/\e\[[0-9;:]*m//g'`.
- `bash tools/preview.sh [scenario...]` plays the README animations; `--gif` (needs `agg`), `--callout` and `--social`
  rewrite `images/`. `python3 tools/icons.py` rewrites `images/icons/` (needs Pillow). A change to what an element
  draws usually means regenerating its scenario's GIF.

## How a render flows

- **Config table** at the top: one key per line, `lower_name="${UPPER_NAME-default}"`, after
  `~/.claude/statusline-config.local.txt` is sourced. `-` rather than `:-`, so a blank is a real setting. `cfg()` in
  the selftest and `tools/icons.py` read defaults straight out of these lines, so a new key takes exactly that form.
- **Account** from `~/.claude.json` `oauthAccount`, read every render so a login swap shows at once. One `case` on
  `organizationType` (plus the rate-limit tier) decides the plan label and glyph. Ultra arrives as `claude_max` on
  `default_claude_max_20x`.
- **Payload** parsed in a single `grep -oE` pass into `payload_*` globals. A new field extends that regex and its
  `case`, never a second grep.
- **Two modes.** A `"tasks":[` in the payload means `subagentStatusLine`: one JSON line per agent row, then exit.
  Otherwise elements are built, `fit_bars` gives the bars whatever `COLUMNS` leaves after everything else, and the
  bottom of the file assembles them in order, plus a task line from `~/.claude/tasks/<session_id>/`.
- **Git** comes from reading `.git` files (HEAD, commondir, refs, packed-refs, origin URL) in `find_git` and after it.
  `git status` for the dirty count is the only subprocess, plus `symbolic-ref` on a reftable repo, whose HEAD is a stub.
- **Spend ledger** `~/.claude/statusline-spend.tsv` is the only state the script writes, and only with
  `WEEKLY_BUDGET_USD` set. Append-only because sessions render concurrently, compacted through temp file and rename,
  rows keyed by a hash of the account so no address lands on disk.

## Constraints that bite

- bash 3.2, what macOS ships. No associative arrays, no `${x,,}`, no `\u` in `$'...'` (paste the glyph itself; the
  selftest fails on a literal `\u`).
- Forks are the budget, ~2ms each on macOS. Helpers set a global rather than print (`tint` sets `tinted`, `to_bg` sets
  `bg_of`, `plain_width` sets `pw`) because `$(fn)` forks even for pure bash. Call `fn args`, then read the global.
- Exit 0 always. Claude Code discards a status line that fails, so a `[ ... ] && ...` as the last statement blanks it.
- JSON strings arrive escaped. Match them as `"([^"\\]|\\.)*"` and run `json_unescape` before showing one: `"[^"]*"`
  stops at the first `\"`.
- Measure cells with `plain_width`, which strips SGR and OSC 8. The UTF-8 guard at the top keeps `${#var}` counting
  characters rather than bytes.
- Claude Code re-serializes the line through its own model: one underline boolean, SGR `4:4` and `58` dropped. Only a
  truecolor `38;2;` can be tinted, and a plain `0;NN` code resets attributes, wiping a background set before it
  (`to_bg`).
- New Nerd Font glyphs come from U+F0000 and up (`md-*`). macOS fonts shadow the BMP private-use range, and a glyph
  there can render as nothing.
