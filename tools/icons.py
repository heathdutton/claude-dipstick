#!/usr/bin/env python3
"""Render the Nerd Font glyphs as chips for the README.

Part of claude-dipstick: https://github.com/heathdutton/claude-dipstick

GitHub ships no Nerd Font, so every one of these codepoints renders as nothing in a markdown table. Blowing each one
up into a small PNG is the only way the README can show what is actually on the line.

    python3 tools/icons.py                 write images/icons/
    python3 tools/icons.py --font PATH     use a particular .ttf
    python3 tools/icons.py --check         say what it would draw, write nothing

The codepoints come out of statusline.sh's own default table rather than a copy kept here, so a glyph that changes
there changes in the README too and the two cannot drift apart.
"""

import argparse
import re
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("needs Pillow: pip3 install Pillow")

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SIZE, RADIUS, INSET = 128, 26, 26
CHIP_BG = (35, 37, 35, 255)

# Each chip takes the color that element wears on the line, so it reads as a zoomed crop rather than a new palette.
CYAN, GREEN, PLUM, AMBER, BLUE, RED, TRACK = (
    "#4DD0E1", "#66BB6A", "#C77DBB", "#FFA726", "#7986CB", "#EF5350", "#5A6A6E")

# (file name, config key in statusline.sh, color)
FROM_CONFIG = [
    ("model-mythos", "MODEL_MARK_MYTHOS", CYAN),
    ("model-fable", "MODEL_MARK_FABLE", CYAN),
    ("model-opus", "MODEL_MARK_OPUS", CYAN),
    ("model-sonnet", "MODEL_MARK_SONNET", CYAN),
    ("model-haiku", "MODEL_MARK_HAIKU", CYAN),
    ("tier-max", "PROFILE_ICON_MAX", PLUM),
    ("tier-pro", "PROFILE_ICON_PRO", PLUM),
    ("tier-team", "PROFILE_ICON_TEAM", PLUM),
    ("tier-enterprise", "PROFILE_ICON_ENTERPRISE", PLUM),
    ("tier-free", "PROFILE_ICON_FREE", PLUM),
    ("tier-none", "PROFILE_ICON_DEFAULT", PLUM),
    ("bar-session", "USAGE_ICON", GREEN),
    ("bar-week", "WEEKLY_ICON", GREEN),
    ("bar-budget", "BUDGET_ICON", GREEN),
    ("cost", "COST_ICON", GREEN),
    ("branch", "BRANCH_ICON", GREEN),
    ("dirty", "GIT_DIRTY_ICON", AMBER),
    ("unpushed", "UNPUSHED_ICON", AMBER),
    ("pr", "PR_ICON", AMBER),
    ("tasks", "TASK_ICON", BLUE),
    ("cache", "CACHE_ICON", RED),
]

# Not config keys: the powerline chevrons are drawn by hand, and two plain-Unicode marks round the set out.
LITERAL = [
    ("effort-lit", "", CYAN),
    ("effort-unlit", "", TRACK),
    ("clean", "✓", GREEN),
    ("worktree", "⋔", GREEN),
    ("pace", "┃", GREEN),
]


def glyph_for(source, key):
    """The default side of `some_icon="${SOME_KEY-X}"`, or None when the key ships blank."""
    m = re.search(r'^[a-z_]+="\$\{%s-(.*?)\}"$' % re.escape(key), source, re.M)
    return m.group(1) or None if m else None


# A codepoint no font maps, used to recognise what .notdef renders as. Comparing against it is how a missing glyph
# gets caught, since PIL draws the empty box silently and has no fallback of its own.
SENTINEL = "\U000FFFFD"

# Hack carries no plain-Unicode marks (no check mark, no pitchfork), so those fall back exactly as the terminal makes
# them fall back. Verified by rendering: Menlo has the check, Arial Unicode has both.
FALLBACKS = ["/System/Library/Fonts/Menlo.ttc",
             "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
             "/Library/Fonts/Arial Unicode.ttf"]


def draws(font, ch):
    """False when the font has no glyph for ch and would draw .notdef."""
    def ink(c):
        im = Image.new("L", (96, 96), 0)
        ImageDraw.Draw(im).text((10, 10), c, font=font, fill=255)
        return im.tobytes()
    return ink(ch) != ink(SENTINEL)


def pick_font(primary, fonts, ch):
    """The first font that actually has the glyph, primary first."""
    for f in fonts:
        if draws(f, ch):
            return f
    return primary


def find_font(explicit):
    if explicit:
        return Path(explicit)
    # Terminal fonts are installed, not built in, so the two user directories are the whole search.
    for d in (Path.home() / "Library/Fonts", Path("/Library/Fonts")):
        if not d.is_dir():
            continue
        # Hack first: it is what the glyph choices were measured against, and a box that has several Nerd Fonts
        # installed would otherwise pick whichever sorts first.
        for pattern in ("Hack*NerdFontMono-Regular.ttf", "Hack*NerdFont-Regular.ttf",
                        "*NerdFontMono-Regular.ttf", "*NerdFont-Regular.ttf", "*Nerd*Regular.ttf"):
            hit = sorted(d.glob(pattern))
            if hit:
                return hit[0]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font")
    ap.add_argument("--out", default=str(ROOT / "images/icons"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    source = (ROOT / "statusline.sh").read_text()
    font_path = find_font(args.font)
    if not font_path:
        sys.exit("no Nerd Font found in ~/Library/Fonts or /Library/Fonts (pass --font)")

    wanted, missing = list(LITERAL), []
    for name, key, color in FROM_CONFIG:
        g = glyph_for(source, key)
        if g:
            wanted.append((name, g, color))
        else:
            missing.append(key)

    print(f"font  {font_path}")
    print(f"out   {args.out}")
    for key in missing:
        print(f"  skipped {key}, ships blank", file=sys.stderr)
    if args.check:
        for name, g, color in wanted:
            print(f"  {name:16} U+{ord(g[0]):05X}  {color}")
        return

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    px = SIZE - INSET * 2
    primary = ImageFont.truetype(str(font_path), px)
    chain = [primary]
    for fb in FALLBACKS:
        if Path(fb).exists():
            try:
                chain.append(ImageFont.truetype(fb, px))
            except OSError:
                pass

    for name, g, color in wanted:
        font = pick_font(primary, chain, g)
        if font is not primary:
            print(f"  {name}: fell back for U+{ord(g[0]):04X}")
        im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], RADIUS, fill=CHIP_BG)
        # Centre on the glyph's own ink, not on the font's advance box. Nerd Font marks sit all over their em.
        box = d.textbbox((0, 0), g, font=font)
        d.text(((SIZE - (box[2] - box[0])) / 2 - box[0], (SIZE - (box[3] - box[1])) / 2 - box[1]),
               g, font=font, fill=color)
        im.save(out / f"{name}.png")
    print(f"  {len(wanted)} icons written")


if __name__ == "__main__":
    main()
