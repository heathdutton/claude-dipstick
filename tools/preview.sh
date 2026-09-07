#!/bin/bash
# Animated previews of the status line, to watch or to publish.
# Part of claude-dipstick: https://github.com/heathdutton/claude-dipstick
#
#   bash tools/preview.sh                 every scenario, once
#   bash tools/preview.sh --loop          keep cycling until Ctrl-C
#   bash tools/preview.sh context week    just those
#   bash tools/preview.sh --list          the scenario names
#   bash tools/preview.sh --gif           one GIF per scenario in images/
#   bash tools/preview.sh --callout       the annotated still for the README, images/callout.png
#   bash tools/preview.sh --social        the 1280x640 GitHub social card, images/social.png
#
# The README's static icon chips are a separate job: python3 tools/icons.py
#
# Options: --fps N (12), --hold S (1.6, for still scenes), --cols N (ask the terminal to resize to N x 8 for a tight
# recording, put back on exit). GIF options: --gif [DIR], --font FAMILY, --font-size PX, --tail S (the pause before the
# loop restarts), --captions / --no-captions, --keep-cast.
#
# Runs the real statusline.sh against synthetic payloads in a throwaway HOME, with a made-up account ("Heath", Max 20x)
# and a scratch git repo, so nothing on screen is yours. Frames render up front at the window's real width, read from
# the tty, then play back at a steady rate, so render time never paces playback.
#
# CLAUDE_STATUSLINE_NOW pins the clock per frame, so reset times land on the hour and pace markers move with the
# scenario rather than the wall clock.
#
# --gif skips the screen entirely: the same rendered frames are written as an asciicast (exact timings, no capture
# race) and rasterised by agg, in this machine's iTerm2 colors and font, read from its plist. No window, so no title
# bar and no chrome to crop. Needs `brew install agg`; on anything but iTerm2 it falls back to agg's own theme.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SL="$ROOT/statusline.sh"
ALL="context effort models session week tiers cost git agents width"

fps=12; hold=1.6; want_cols=""; loop=0; want=""
gif=0; gif_dir="$ROOT/images"; social=0; social_out="$ROOT/images/social.png"; callout=0; callout_out="$ROOT/images/callout.png"; captions=""; font="${PREVIEW_FONT:-}"; font_size="${PREVIEW_FONT_SIZE:-}"
tail_hold=1.5; keep_cast=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fps)  fps=$2; shift ;;
    --hold) hold=$2; shift ;;
    --cols) want_cols=$2; shift ;;
    --loop) loop=1 ;;
    --gif)  gif=1; case "${2:-}" in ""|-*) ;; *) gif_dir=$2; shift ;; esac ;;
    --callout) callout=1; case "${2:-}" in ""|-*) ;; *) callout_out=$2; shift ;; esac ;;
    --social) social=1; case "${2:-}" in ""|-*) ;; *) social_out=$2; shift ;; esac ;;
    --font) font=$2; shift ;;
    --font-size) font_size=$2; shift ;;
    --tail) tail_hold=$2; shift ;;
    --captions)    captions=1 ;;
    --no-captions) captions=0 ;;
    --keep-cast)   keep_cast=1 ;;
    --list) echo "$ALL" | tr ' ' '\n'; exit 0 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) want="$want $1" ;;
  esac
  shift
done
[ -n "$want" ] || want="$ALL"
for w in $want; do
  case " $ALL " in *" $w "*) ;; *) echo "no scenario '$w' (try --list)" >&2; exit 1 ;; esac
done
# A GIF is one scenario, and the README's prose around it says what the caption would. On screen, where the scenarios
# run back to back, the caption is the only thing announcing which one you are looking at.
[ -n "$captions" ] || { [ "$gif" = 1 ] && captions=0 || captions=1; }

# ---- the window ----
# Width from the tty itself. $COLUMNS and tput repeat whatever the shell exported, stale after a resize.
tty_cols() {
  local sz
  if sz=$(stty size < /dev/tty 2>/dev/null) && [ -n "$sz" ]; then echo "${sz#* }"; return; fi
  tput cols 2>/dev/null || echo 140
}
orig_size=""
if [ "$gif" = 1 ]; then
  # No window involved, so the width is simply asked for rather than negotiated with the terminal.
  cols=${want_cols:-140}
  want_cols=""
else
  if [ -n "$want_cols" ]; then
    orig_size="$(stty size < /dev/tty 2>/dev/null | tr ' ' ';')"
    printf '\e[8;8;%dt' "$want_cols"
    sleep 0.4
  fi
  cols=$(tty_cols)
  if [ -n "$want_cols" ] && [ "$cols" != "$want_cols" ]; then
    printf 'note: the window stayed at %s columns (iTerm2 can refuse session-initiated resizing per profile); rendering to that.\n' "$cols" >&2
    orig_size=""
    sleep 1.5
  fi
fi

# ---- a world of its own ----
WORK="$(mktemp -d)"
cleanup() {
  printf '\e[?25h\e[0m\n'
  [ -n "$orig_size" ] && printf '\e[8;%st' "$orig_size"
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT

mkdir -p "$WORK/home/.claude"
account() {  # <displayName> <organizationType> <tier>; "" "" "" for an API key
  if [ -n "$2" ]; then
    printf '{"oauthAccount":{"displayName":"%s","emailAddress":"heath@example.com","organizationType":"%s","organizationRateLimitTier":"%s"}}\n' \
      "$1" "$2" "$3" > "$WORK/home/.claude.json"
  else
    rm -f "$WORK/home/.claude.json"
  fi
}
account Heath claude_max default_claude_max_20x

APP="$WORK/preview-app"
git init -q -b main "$APP" 2>/dev/null
git -C "$APP" -c user.name=preview -c user.email=preview@example.com commit -q --allow-empty -m init 2>/dev/null

# The scenario clock. hour0 is the top of the current hour, so the session window opens there and closes five hours on
# and its reset reads "4pm" not "3:52pm". A frame's "now" is hour0 plus however far in the scenario says it is.
hour0=$(( $(date +%s) / 3600 * 3600 ))
frame_delay=$(awk "BEGIN { printf \"%.4f\", 1 / $fps }")

# ---- frames: parallel arrays, rendered up front ----
FRAMES=(); HOLDS=(); CAPTIONS=()
caption=""
# frame <model_id> <effort|""> <ctx%> <session%|""> <session_elapsed_s> <week%> <week_elapsed_s> <cost> <dir> [cols] [hold]
frame() {
  local model=$1 effort=$2 ctx=$3 spct=$4 sel=$5 wpct=$6 wel=$7 cost=$8 dir=$9
  local fcols=${10:-$cols} fhold=${11:-$frame_delay}
  local now=$(( hour0 + sel )) tokens=$(( ctx * 2000 )) effort_json="" rl="" payload out
  [ -n "$effort" ] && effort_json=",\"effort\":{\"level\":\"$effort\"}"
  if [ -n "$spct" ]; then
    # Both resets are anchored to hour0, never to `now`. A window's reset is a fixed instant that the clock walks
    # toward... derive it from `now` and it slides by however far the scenario has run, which walks the reset label
    # backwards through the week.
    #
    # So `sel` is the clock and it alone moves the fill and the pace markers. `wel` only says where in its week hour0
    # sits, and holding it still is what pins the reset.
    #
    # The 5-hour window has to roll, or a scenario spanning days would point at a reset long past. Every existing
    # scenario stays inside the first window and gets hour0 + 18000 exactly as before.
    local five_end=$(( hour0 + (sel / 18000 + 1) * 18000 ))
    local week_end=$(( (hour0 + 604800 - wel) / 3600 * 3600 ))
    rl=",\"rate_limits\":{\"five_hour\":{\"used_percentage\":$spct,\"resets_at\":$five_end},\"seven_day\":{\"used_percentage\":$wpct,\"resets_at\":$week_end}}"
  fi
  payload=$(printf '{"hook_event_name":"Status","session_id":"preview","cwd":"%s","model":{"id":"%s","display_name":"%s"},"workspace":{"current_dir":"%s","project_dir":"%s"}%s,"cost":{"total_cost_usd":%s},"context_window":{"current_usage":{"input_tokens":%d,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"context_window_size":200000}%s}' \
    "$dir" "$model" "$model" "$dir" "$dir" "$effort_json" "$cost" "$tokens" "$rl")
  out=$(cd "$dir" && printf '%s' "$payload" | HOME="$WORK/home" COLUMNS="$fcols" CLAUDE_STATUSLINE_NOW="$now" bash "$SL")
  frame_line_out=$out
  [ "${frame_render_only:-0}" = 1 ] && return 0
  FRAMES+=("$out"); HOLDS+=("$fhold"); CAPTIONS+=("$caption")
  # Only where a \r can erase itself. Piped, it would glue the whole progress run onto the next line printed.
  if [ -t 2 ]; then printf '\r  rendering %d frames at %d columns...' "${#FRAMES[@]}" "$cols" >&2; fi
}

# frame() with the recording suppressed, for a caller that wants the rendered line to put somewhere of its own.
frame_line() {
  frame_render_only=1 frame "$@"
  frame_render_only=0
  printf '%s' "$frame_line_out"
}

# The agent panel. Claude Code sends one payload carrying a tasks array and takes back one JSON row per agent, which
# it draws under the prompt. Nothing here draws that panel, so previewing a fan-out means rendering the coordinator's
# own line and then the rows underneath it, exactly where Claude Code puts them.
#
# frame() cannot do this: it renders one line from one payload, and a row set is a second payload of a different
# shape. Hence its own builder.
# Dim, and the same shape Claude Code prints: the permission mode, then what is running.
sa_hint=$'\033[38;2;122;134;138m  ⏵⏵ bypass permissions on · 3 agents\033[0m'
agent_frame() {
  local ctx=$1 fhold=$2; shift 2
  local main rows tasks="" a name model effort tokens
  main=$(frame_line claude-opus-5 high "$ctx" 34 6300 22 $((2 * 86400)) 0 "$APP" "$cols")
  for a in "$@"; do
    IFS=: read -r name model effort tokens <<EOF
$a
EOF
    [ -n "$tasks" ] && tasks="$tasks,"
    tasks="$tasks{\"id\":\"$name\",\"name\":\"$name\",\"status\":\"running\",\"description\":\"\",\"model\":\"$model\""
    [ -n "$effort" ] && tasks="$tasks,\"effort\":\"$effort\""
    tasks="$tasks,\"contextWindowSize\":200000,\"tokenCount\":$tokens}"
  done
  rows=$(printf '{"hook_event_name":"SubagentStatus","session_id":"preview","columns":%d,"tasks":[%s]}' \
           $(( cols - 8 )) "$tasks" \
         | HOME="$WORK/home" bash "$SL" \
         | python3 -c '
import json, sys
# Two spaces in front of each row, the way Claude Code insets the panel under the prompt. Flush against the status
# line they read as part of it rather than as a list hanging off it.
print("\n".join("  " + json.loads(l)["content"] for l in sys.stdin if l.strip()))')
  # Status line first, then what is running under it. The panel sits above the footer in the real UI, but reading top
  # to bottom the line is the subject and the agents are the detail, so leading with the line is what makes sense of it.
  FRAMES+=("$main"$'\n'"$sa_hint"$'\n'"$rows"); HOLDS+=("$fhold"); CAPTIONS+=("$caption")
  if [ -t 2 ]; then printf '\r  rendering %d frames at %d columns...' "${#FRAMES[@]}" "$cols" >&2; fi
}

s_agents() {
  caption="A fan-out: the coordinator's line, then a row per running agent with its own model and meter."
  local i r b e
  for i in $(seq 0 6 96); do
    r=$(( 14000 + i * 900 )); b=$(( 30000 + i * 1500 )); e=$(( 6000 + i * 400 ))
    frame_caption_hold=$frame_delay
    agent_frame $(( 20 + i / 3 )) "$frame_delay" \
      "reviewer:claude-sonnet-5:high:$r" "builder:claude-opus-5:max:$b" "explorer:claude-haiku-4-5::$e"
  done
  agent_frame 52 "$hold" "reviewer:claude-sonnet-5:high:100400" "builder:claude-opus-5:max:174000" \
                          "explorer:claude-haiku-4-5::44400"
}

s_context() {
  caption="Every element at once, then a session from its first response: context fills, cyan to red."
  local i
  # A populated frame first, held. Anything that flattens a GIF to one image keeps frame one, and the state this
  # scenario genuinely opens on is a line with half its elements still absent... a poor thing to be judged by.
  frame claude-opus-5 high 58 34 6300 22 $((2 * 86400)) 0 "$APP" "" "$hold"
  for i in 1 2 3 4; do frame claude-opus-5 high 0 "" 0 0 0 0 "$APP" "" 0.5; done
  for i in $(seq 0 2 100); do
    frame claude-opus-5 high "$i" $((12 + i / 6)) $((600 + i * 90)) 33 $((3 * 86400)) 0 "$APP"
  done
  frame claude-opus-5 high 100 28 9600 33 $((3 * 86400)) 0 "$APP" "" "$hold"
}
# These two are the key to the two most obscure marks on the line, so the caption names each frame rather than the
# scenario. Under --captions that makes the GIF label itself, which is what the README needs of it.
s_effort() {
  local e n=0
  for e in low medium high xhigh max; do
    n=$(( n + 1 ))
    caption="effort $e, $n of 5 chevrons lit"
    frame claude-opus-5 "$e" 25 14 3000 6 $((2 * 86400)) 0 "$APP" "" "$hold"
  done
  caption=""
}
s_models() {
  local m
  for m in "claude-mythos-1 max Mythos, a circle" \
           "claude-fable-5-1 max Fable, a hexagon" \
           "claude-opus-5 high Opus, a square" \
           "claude-sonnet-5 medium Sonnet, a triangle" \
           "claude-haiku-4-5 - Haiku, a dot (and no effort dial, so no chevrons)"; do
    set -- $m
    caption="${*:3}"
    frame "$1" "$([ "$2" = - ] || echo "$2")" 25 14 3000 6 $((2 * 86400)) 0 "$APP" "" "$hold"
  done
  caption=""
}
s_session() {
  caption="The five-hour window: fill is usage, the marker is the clock, and the color is how they compare."
  local i pct
  for i in $(seq 0 2 98); do
    pct=$(( i * 13 / 10 )); [ "$pct" -gt 100 ] && pct=100
    frame claude-opus-5 high 40 "$pct" $((i * 180)) 30 $((3 * 86400)) 0 "$APP"
  done
  frame claude-opus-5 high 40 100 17900 30 $((3 * 86400)) 0 "$APP" "" "$hold"
}
s_week() {
  caption="A week, a day at a time. The marker is the clock, the fill is usage, and it goes over pace near the end."
  local d
  # A day per held frame, not a smooth fill. Time and usage have to move together or neither reads: a frozen clock
  # means usage accruing while no time passes, and a rolling clock at video frame rates spins the 5-hour window
  # dozens of times. A day is the smallest step where that window legitimately showing a different reset each frame
  # is the truth rather than noise.
  #
  # wel stays 0 so the week's own reset is pinned seven days out from hour0. sel is the clock walking toward it.
  local use="2 10 20 33 50 78 96" sess="18 42 9 66 27 51 88" i=0 u s
  for d in 0 1 2 3 4 5 6; do
    u=$(echo "$use" | cut -d' ' -f$((d + 1)))
    s=$(echo "$sess" | cut -d' ' -f$((d + 1)))
    frame claude-opus-5 high 32 "$s" $(( d * 86400 + 3000 )) "$u" 0 0 "$APP" "" 0.9
  done
  frame claude-opus-5 high 32 88 $(( 6 * 86400 + 3000 )) 96 0 0 "$APP" "" "$hold"
}
s_tiers() {
  caption="Account tier as a glyph: Max, Pro, Team, Enterprise, Free, and an API key, which has no windows."
  local t
  for t in "claude_max default_claude_max_20x" "claude_pro default_claude_pro" "claude_team default_claude_team" \
           "claude_enterprise default_enterprise" "claude_free default_free"; do
    account Heath $t
    frame claude-opus-5 high 25 14 3000 6 $((2 * 86400)) 0 "$APP" "" "$hold"
  done
  account "" "" ""
  frame claude-opus-5 high 25 "" 0 0 0 9.4 "$APP" "" "$hold"
  account Heath claude_max default_claude_max_20x
}
s_cost() {
  caption="Cost shows only where it is a bill: hidden on a subscription, shown on an API key, which has no windows."
  frame claude-opus-5 high 45 38 7200 41 $((3 * 86400)) 27.4 "$APP" "" "$hold"
  account "" "" ""
  frame claude-opus-5 high 45 "" 0 0 0 27.4 "$APP" "" "$hold"
  account Heath claude_max default_claude_max_20x
}
s_git() {
  caption="Clean, then edits in flight, then a worktree, then a task folder whose checkout is somewhere else."
  frame claude-opus-5 high 25 14 3000 6 $((2 * 86400)) 0 "$APP" "" "$hold"
  printf 'x\n' > "$APP/one.txt"; printf 'y\n' > "$APP/two.txt"; printf 'z\n' > "$APP/three.txt"
  frame claude-opus-5 high 25 14 3000 6 $((2 * 86400)) 0 "$APP" "" "$hold"
  rm -f "$APP/one.txt" "$APP/two.txt" "$APP/three.txt"
  git -C "$APP" worktree add -q "$WORK/preview-app-PROJ-123" -b PROJ-123 2>/dev/null
  frame claude-opus-5 high 25 14 3000 6 $((2 * 86400)) 0 "$WORK/preview-app-PROJ-123" "" "$hold"

  # The case the repo label exists for. A task folder is not itself a checkout, it symlinks out to the repos it works
  # on, so the branch has to name which repo it belongs to or "stage" is a guess.
  local task="$WORK/PROJ-742" api="$WORK/api"
  if [ ! -d "$api" ]; then
    git init -q -b stage "$api" 2>/dev/null
    git -C "$api" -c user.name=preview -c user.email=preview@example.com commit -q --allow-empty -m init 2>/dev/null
    printf 'pending\n' > "$api/schema.sql"
    mkdir -p "$task/repos" && ln -sfn "$api" "$task/repos/api"
  fi
  frame claude-opus-5 high 25 14 3000 6 $((2 * 86400)) 0 "$task" "" "$hold"
}
s_width() {
  caption="The bars fit the terminal: the same session at 90, 110, 130 columns, then the full width."
  local c
  for c in 90 110 130 "$cols"; do
    [ "$c" -le "$cols" ] || continue
    frame claude-opus-5 high 45 38 7200 41 $((3 * 86400)) 0 "$APP" "$c" "$hold"
  done
}

# ---- GIFs ----
# The look is this machine's, read out of iTerm2's own plist: sixteen ANSI colors, foreground, background, and the
# profile's font. iTerm2 stores the font by PostScript name ("HackNFM-Regular 12") and agg matches on family name, so
# the name table of every user-installed font is read to translate it. Anything unresolved is simply left out and agg
# uses its own defaults, which is what a non-iTerm2 machine gets.
resolve_style() {
  python3 - <<'PY' > "$WORK/theme.json" 2>/dev/null || printf '{}\n' > "$WORK/theme.json"
import json, os, plistlib, struct
from pathlib import Path

def sfnt_names(path):
    """(PostScript name, family) from a TTF/OTF name table, or None."""
    with open(path, "rb") as fh:
        tag = fh.read(4)
        if tag not in (b"\x00\x01\x00\x00", b"OTTO", b"true"):
            return None
        count = struct.unpack(">H", fh.read(2))[0]
        fh.seek(12)
        off = 0
        for _ in range(count):
            rec = fh.read(16)
            if len(rec) < 16:
                return None
            if rec[:4] == b"name":
                off = struct.unpack(">I", rec[8:12])[0]
                break
        if not off:
            return None
        fh.seek(off)
        _, n, str_off = struct.unpack(">HHH", fh.read(6))
        recs = fh.read(n * 12)
        found = {}
        for i in range(n):
            pid, _eid, _lid, nid, ln, o = struct.unpack(">HHHHHH", recs[i * 12:(i + 1) * 12])
            if nid not in (1, 6, 16) or nid in found:
                continue
            fh.seek(off + str_off + o)
            try:
                found[nid] = fh.read(ln).decode("utf-16-be" if pid == 3 else "mac-roman").strip("\x00")
            except Exception:
                pass
        ps, fam = found.get(6), found.get(16) or found.get(1)
        return (ps, fam) if ps and fam else None

def family_of(ps_name):
    """Terminal fonts are installed, not built in, so the two user font directories are the whole search."""
    for d in (Path.home() / "Library/Fonts", Path("/Library/Fonts")):
        if not d.is_dir():
            continue
        for f in sorted(d.iterdir()):
            if f.suffix.lower() not in (".ttf", ".otf"):
                continue
            try:
                got = sfnt_names(f)
            except Exception:
                continue
            if got and got[0] == ps_name:
                return got[1]
    return None

def profile():
    name = os.environ.get("ITERM_PROFILE")
    if not name or os.environ.get("TERM_PROGRAM") != "iTerm.app":
        return None
    with open(Path.home() / "Library/Preferences/com.googlecode.iterm2.plist", "rb") as fh:
        prefs = plistlib.load(fh)
    for e in prefs.get("New Bookmarks", []):
        if e.get("Name") == name:
            return e
    return None

def hexcolor(entry, key):
    # "(Dark)" is the variant a dark-mode Mac renders, when the profile carries one.
    c = entry.get(key + " (Dark)") or entry.get(key)
    if not isinstance(c, dict):
        return None
    try:
        return "#%02X%02X%02X" % tuple(
            round(c[k] * 255) for k in ("Red Component", "Green Component", "Blue Component"))
    except (KeyError, TypeError):
        return None

out = {}
p = profile()
if p:
    fg, bg = hexcolor(p, "Foreground Color"), hexcolor(p, "Background Color")
    ansi = [hexcolor(p, "Ansi %d Color" % i) for i in range(16)]
    if fg and bg and all(ansi):
        out.update(fg=fg, bg=bg, palette=":".join(ansi))
    fonts, size = [], None
    for key, on in (("Normal Font", True), ("Non Ascii Font", p.get("Use Non-ASCII Font"))):
        spec = p.get(key)
        if not on or not spec or " " not in spec:
            continue
        ps, _, px = spec.rpartition(" ")
        size = size or (int(float(px)) if px.replace(".", "", 1).isdigit() else None)
        fonts.append(family_of(ps) or ps)
    if fonts:
        # Menlo last: Hack carries no subscript digits, and the bars' numbers fall back to it on a Mac the same way the
        # real terminal does.
        out["font"] = ",".join(fonts + ["Menlo"])
    if size:
        out["size"] = size
print(json.dumps(out))
PY
  agg_font=$font agg_size=$font_size
  [ -n "$agg_font" ] || agg_font=$(python3 -c 'import json,sys;print(json.load(sys.stdin).get("font",""))' < "$WORK/theme.json")
  # Twice the profile's point size, so a GitHub page showing the GIF at half width lands on the pixel grid iTerm2 draws
  # it at rather than a resample of it.
  [ -n "$agg_size" ] || agg_size=$(python3 -c 'import json,sys;print(json.load(sys.stdin).get("size",0)*2 or "")' < "$WORK/theme.json")
  [ -n "$agg_size" ] || agg_size=24
}

# Straight from the rendered frames to an asciicast: exact per-frame timings, no capture, no window.
emit_gif() {
  local name=$1 cast="$WORK/$1.cast" out="$gif_dir/$1.gif" i
  : > "$WORK/frames.bin"
  for i in $(seq 0 $(( ${#FRAMES[@]} - 1 ))); do
    # NUL between records, tab between fields: a rendered line holds neither.
    printf '%s\t%s\t%s\0' "${HOLDS[$i]}" "${CAPTIONS[$i]}" "${FRAMES[$i]}" >> "$WORK/frames.bin"
  done
  CAST_COLS=$cols CAST_CAPTIONS=$captions CAST_FRAMES="$WORK/frames.bin" \
  CAST_THEME="$WORK/theme.json" CAST_OUT="$cast" python3 - <<'PY' || return 1
import json, os

E = "\x1b"
cols = int(os.environ["CAST_COLS"])
capped = os.environ["CAST_CAPTIONS"] == "1"
with open(os.environ["CAST_FRAMES"], "rb") as fh:
    recs = [r.decode("utf-8", "replace").split("\t", 2) for r in fh.read().split(b"\0") if r]

# A frame is usually one line, but the agent panel is a coordinator plus a row per running agent. Size the cast to the
# tallest frame in the scenario, or the rows past the first scroll the screen instead of drawing.
tall = max(len(frame.split("\n")) for _, _, frame in recs)
line_row = 4 if capped else 2
rows = line_row + tall            # a blank row above and below, since agg draws no margin of its own

hdr = {"version": 2, "width": cols, "height": rows, "env": {"TERM": "xterm-256color", "SHELL": "/bin/bash"}}
theme = json.load(open(os.environ["CAST_THEME"]))
if "palette" in theme:
    hdr["theme"] = {"fg": theme["fg"], "bg": theme["bg"], "palette": theme["palette"]}

with open(os.environ["CAST_OUT"], "w", encoding="utf-8") as out:
    out.write(json.dumps(hdr, ensure_ascii=False) + "\n")
    at, shown, first = 0.0, None, True
    for held, caption, frame in recs:
        data = f"{E}[?25l{E}[2J{E}[H" if first else ""
        first = False
        if capped and caption != shown:
            shown = caption
            data += f"{E}[2;1H{E}[K  {E}[2m{caption}{E}[0m"
        body = frame.split("\n")
        for n, ln in enumerate(body):
            data += f"{E}[{line_row + n};1H{E}[K  {ln}"
        # A shorter frame after a taller one leaves its tail on screen otherwise.
        for n in range(len(body), tall):
            data += f"{E}[{line_row + n};1H{E}[K"
        out.write(json.dumps([round(at, 4), "o", data], ensure_ascii=False) + "\n")
        at += float(held)
PY
  # 1.32, not agg's 1.4. A bar is painted across the whole line box while the glyph riding inside it is centred on the
  # em box, so leading pushes the model mark off centre. Measured at both font sizes used here: 1.4 leaves the mark a
  # pixel high, 1.32 lands it dead centre. Every other effect on the spacing is too small to see.
  local lh=1.32
  local args=(--last-frame-duration "$tail_hold" -q)
  [ -n "$agg_font" ] && args+=(--text-font-family "$agg_font")
  agg "${args[@]}" --line-height "$lh" --font-size "$agg_size" "$cast" "$out" || return 1
  [ "$keep_cast" = 1 ] && cp "$cast" "$gif_dir/$name.cast"
  printf '  %-8s %5s  %s\n' "$name" "$(du -h "$out" | cut -f1 | tr -d ' \t')" "$out" >&2
}

# GitHub's social preview card, 1280x640. Real renders, not a mockup: the same statusline.sh, the same font and theme as
# the GIFs, three fills so the cyan-to-red ramp is the thing you see first. One agg frame, then ffmpeg pads it to
# exactly the size GitHub wants.
emit_social() {
  # The lines render narrower than the card holds. statusline.sh already keeps BAR_FIT_MARGIN back, but the card indents
  # by three on top of that, and an overrun wraps onto the next row rather than clipping.
  local out=$1 cast="$WORK/social.cast" card_cols=96 line_cols=86
  FRAMES=(); HOLDS=(); CAPTIONS=()
  frame claude-opus-5   high   18 12 2400 22 $((2 * 86400)) 0 "$APP" "$line_cols"
  frame claude-sonnet-5 medium 54 47 8100 48 $((3 * 86400)) 0 "$APP" "$line_cols"
  frame claude-opus-5   max    91 88 15300 79 $((5 * 86400)) 0 "$APP" "$line_cols"
  printf '\r\e[K' >&2

  : > "$WORK/frames.bin"
  local i
  for i in 0 1 2; do printf '%s\0' "${FRAMES[$i]}" >> "$WORK/frames.bin"; done

  CARD_FRAMES="$WORK/frames.bin" CARD_THEME="$WORK/theme.json" CARD_OUT="$cast" \
  python3 - <<'PY' || return 1
import json, os, re
from pathlib import Path

E = "\x1b"
vis = lambda s: re.sub(r"\x1b\[[0-9;:]*[a-zA-Z]|\x1b\]8;[^\x07]*\x07", "", s)
theme = json.load(open(os.environ["CARD_THEME"]))
with open(os.environ["CARD_FRAMES"], "rb") as fh:
    lines = [r.decode("utf-8", "replace") for r in fh.read().split(b"\0") if r]

# 14 rows against 88 columns lands near 2:1 before padding, which is the card's aspect.
rows = 13
# Measured, not assumed. statusline.sh stops shrinking once the bars hit BAR_WIDTH_MIN, so a long folder name pushes
# the line past whatever COLUMNS it was given and a fixed card width wraps it onto the next row.
cols = max([len(vis(l)) for l in lines] + [63]) + 6
hdr = {"version": 2, "width": cols, "height": rows, "env": {"TERM": "xterm-256color", "SHELL": "/bin/bash"}}
if "palette" in theme:
    hdr["theme"] = {"fg": theme["fg"], "bg": theme["bg"], "palette": theme["palette"]}

CYAN, DIM, BOLD, OFF = f"{E}[38;2;77;208;225m", f"{E}[2m", f"{E}[1m", f"{E}[0m"
body = f"{E}[?25l{E}[2J{E}[H"
def put(row, text):
    global body
    body += f"{E}[{row};1H{E}[K   {text}"

put(2,  f"{BOLD}{CYAN}claude-dipstick{OFF}")
put(3,  f"{DIM}Context, model, session usage, week usage, budget/cost and more.{OFF}")
put(6,  lines[0])
put(8,  lines[1])
put(10, lines[2])
put(12, f"{DIM}One bash file. No dependencies.{OFF}")

with open(os.environ["CARD_OUT"], "w", encoding="utf-8") as fh:
    fh.write(json.dumps(hdr, ensure_ascii=False) + "\n")
    fh.write(json.dumps([0.0, "o", body], ensure_ascii=False) + "\n")
PY

  local args=(--last-frame-duration 1 -q)
  [ -n "$agg_font" ] && args+=(--text-font-family "$agg_font")
  agg "${args[@]}" --line-height 1.32 --font-size 26 "$cast" "$WORK/social.gif" || return 1

  # Fit inside 1280x640 and pad the rest in the terminal's own background, so the card has no seam.
  local bg
  bg=$(python3 -c 'import json,sys;print(json.load(sys.stdin).get("bg","#232523").lstrip("#"))' < "$WORK/theme.json")
  ffmpeg -y -v error -i "$WORK/social.gif" -frames:v 1 \
    -vf "scale=1280:640:force_original_aspect_ratio=decrease,pad=1280:640:(ow-iw)/2:(oh-ih)/2:color=0x$bg" \
    "$out" || return 1
  printf '  %-8s %5s  %s  (%s)\n' social "$(du -h "$out" | cut -f1 | tr -d ' \t')" "$out" \
    "$(python3 -c "from PIL import Image;im=Image.open('$out');print('x'.join(map(str,im.size)))" 2>/dev/null || echo '?')" >&2
}

# The annotated still under the README's opening animation. Labels sit above the line with a stem dropping onto the
# thing each one names, which is the only way a reader learns the glyphs... the animation shows them moving, this says
# what they are.
#
# Columns are measured off the rendered line rather than guessed, so the stems stay attached when an element changes
# width. Labels pack upward: each takes the lowest row where its own text and the stem under it are both clear.
emit_callout() {
  local out=$1 line
  # The unpushed mark is real but it crowds the left, and the diagram is about the parts that are always there.
  line=$(SHOW_UNPUSHED=0 frame_line claude-opus-5 high 28 34 6300 22 $((2 * 86400)) 0 "$APP" 140)

  printf '%s' "$line" > "$WORK/callout.line"
  CALLOUT_LINE="$WORK/callout.line" CALLOUT_THEME="$WORK/theme.json" CALLOUT_OUT="$WORK/callout.cast" \
  CALLOUT_SRC="$SL" \
  python3 - <<'CALLOUTPY' || return 1
import json, os, re
from pathlib import Path

E = "\x1b"
raw = open(os.environ["CALLOUT_LINE"], encoding="utf-8").read().rstrip("\n")
plain = re.sub(r"\x1b\[[0-9;:]*[a-zA-Z]|\x1b\]8;[^\x07]*\x07", "", raw)

def col(needle, start=0):
    i = plain.find(needle, start)
    return i if i >= 0 else None

# Anchored on what the line actually renders, left to right.
folder = col("app")
branch = col("main")
clean  = col("✓")
acct   = col("\U000f01a5")                     # the tier glyph, so the label covers the mark and the name after it
model  = col("\U000f0764")                     # the family shape, first cell of the meter
ctx    = col("₂₈")                   # the context number, so the stem lands mid-meter
eff    = col("") and col("", (model or 0) + 2)
sess   = col("\U000f0150")                     # the 5-hour bar's clock
week   = col("\U000f0a33")                     # the week bar's calendar

# The two reset times. A bare time closes the 5-hour bar and a day-prefixed one closes the week, in that order.
stamps = [m.start() for m in re.finditer(
    r"(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) \d{1,2}(?::\d{2})?[ap]m|\d{1,2}(?::\d{2})?[ap]m", plain)]

pace = col("┃")                      # the pace marker in the 5-hour bar, where the clock has got to

TARGETS = [(folder, "folder"), (branch, "branch, or worktree"), (clean, "changes"),
           (acct, "account & type"), (model, "model"), (ctx, "context used"), (eff, "effort"),
           (sess, "5-hour usage"), (pace, "pace marker"), (stamps[0] if stamps else None, "next session"),
           (week, "week usage"), (stamps[1] if len(stamps) > 1 else None, "next week")]
TARGETS = [(c, s) for c, s in TARGETS if c is not None]

# Pack upward. A label owns its own cells on its row, and the stem under it owns that column on every row below, so
# nothing ever crosses anything else.
# Left to right, top to bottom. A label keeps the current row when it clears the previous one, otherwise it steps down
# a row. That ordering is what makes crossings impossible: every stem hangs below its own label, and everything to the
# right of it sits lower still, so no stem can ever run through text.
#
# A label near the end would otherwise run off the line and drag the whole image wider than the thing it annotates, so
# it flips and hangs to the left of its stem instead. The rule still holds either way, because the next label starts
# clear of wherever this one ends.
line_w = len(plain)
rows, r, cursor = [], 0, -99
for c, label in sorted(TARGETS):
    text, start = "┌─ " + label, c
    if c + len(text) > line_w:
        text = label + " ─┐"
        start = c - len(text) + 1
    if start < cursor + 2:
        r += 1
    rows.append((c, r, text, start))
    cursor = start + len(text)

depth = max(x[1] for x in rows) + 1
width = max([s + len(x) for _, _, x, s in rows] + [line_w]) + 4
grid = [[" "] * width for _ in range(depth + 1)]
for c, r, text, start in rows:
    for i, ch in enumerate(text):
        grid[r][start + i] = ch
    for rr in range(r + 1, depth):
        grid[rr][c] = "│"
    grid[depth][c] = "▼"

DIM = f"{E}[38;2;122;134;138m"
body = [DIM + "".join(r).rstrip() + f"{E}[0m" for r in grid]
body = [b for b in body if b.strip(DIM + f"{E}[0m")]

# The model key hangs below the line, off the same column its arrow points at. Above the line there is no room for it
# without pushing every other label up; below, it has the whole row. Marks come out of statusline.sh's own defaults.
src = Path(os.environ["CALLOUT_SRC"]).read_text()
def mark(name):
    m = re.search(r'^model_mark_%s="\$\{MODEL_MARK_[A-Z]+-(.*?)\}"$' % name, src, re.M)
    return m.group(1) if m else "?"
under = []
if model is not None:
    pad = " " * model
    # No connector of any kind. The marks sit in the same column as the shape they explain and the "model" label is
    # already pointing at it from above, so a caret here pointed at something that was spoken for, in a glyph that
    # reads as Sonnet's own mark.
    under.append("")
    for n in ["mythos", "fable", "opus", "sonnet", "haiku"]:
        under.append(f"{pad}{mark(n)}  {n.capitalize()}")

frame = "\n".join(body) + "\n" + raw + "".join(
    "\n" + DIM + u.rstrip() + f"{E}[0m" for u in under)

theme = json.load(open(os.environ["CALLOUT_THEME"]))
# OSC 8 carries a file:// URL that is never drawn. Measuring it inflated the cast to well over twice the width
# the content needs, which agg then rendered as a wall of empty background.
vis = lambda s: re.sub(r"\x1b\[[0-9;:]*[a-zA-Z]|\x1b\]8;[^\x07]*\x07", "", s)
width = max(len(vis(l)) for l in frame.split("\n")) + 4
hdr = {"version": 2, "width": width, "height": len(frame.split("\n")) + 2,
       "env": {"TERM": "xterm-256color", "SHELL": "/bin/bash"}}
if "palette" in theme:
    hdr["theme"] = {"fg": theme["fg"], "bg": theme["bg"], "palette": theme["palette"]}

data = f"{E}[?25l{E}[2J{E}[H"
for n, ln in enumerate(frame.split("\n")):
    data += f"{E}[{n + 2};1H{E}[K  {ln}"
with open(os.environ["CALLOUT_OUT"], "w", encoding="utf-8") as fh:
    fh.write(json.dumps(hdr, ensure_ascii=False) + "\n")
    fh.write(json.dumps([0.0, "o", data], ensure_ascii=False) + "\n")
CALLOUTPY

  local args=(--last-frame-duration 1 -q)
  [ -n "$agg_font" ] && args+=(--text-font-family "$agg_font")
  agg "${args[@]}" --line-height 1.32 --font-size 26 "$WORK/callout.cast" "$WORK/callout.gif" || return 1
  local bg
  bg=$(python3 -c 'import json,sys;print(json.load(sys.stdin).get("bg","#232523").lstrip("#"))' < "$WORK/theme.json")
  ffmpeg -y -v error -i "$WORK/callout.gif" -frames:v 1 -vf "pad=iw+40:ih+24:20:12:color=0x$bg" "$out" || return 1
  printf '  %-8s %5s  %s  (%s)\n' callout "$(du -h "$out" | cut -f1 | tr -d ' \t')" "$out" \
    "$(python3 -c "from PIL import Image;im=Image.open('$out');print('x'.join(map(str,im.size)))")" >&2
}

if [ "$callout" = 1 ]; then
  command -v agg >/dev/null || { echo "preview.sh --callout needs agg" >&2; exit 1; }
  mkdir -p "$(dirname "$callout_out")"
  resolve_style
  emit_callout "$callout_out" || exit 1
  exit 0
fi

if [ "$social" = 1 ]; then
  command -v agg >/dev/null || { echo "preview.sh --social needs agg: brew install agg" >&2; exit 1; }
  command -v ffmpeg >/dev/null || { echo "preview.sh --social needs ffmpeg" >&2; exit 1; }
  mkdir -p "$(dirname "$social_out")"
  resolve_style
  emit_social "$social_out" || exit 1
  exit 0
fi

if [ "$gif" = 1 ]; then
  command -v agg >/dev/null || { echo "preview.sh --gif needs agg: brew install agg" >&2; exit 1; }
  command -v python3 >/dev/null || { echo "preview.sh --gif needs python3" >&2; exit 1; }
  mkdir -p "$gif_dir"
  resolve_style
  printf 'font %s at %spx, %s columns\n' "${agg_font:-agg default}" "$agg_size" "$cols" >&2
  for w in $want; do
    FRAMES=(); HOLDS=(); CAPTIONS=()
    "s_$w"
    printf '\r\e[K' >&2
    emit_gif "$w" || exit 1
  done
  exit 0
fi

for w in $want; do "s_$w"; done
printf '\r\e[K' >&2

# ---- playback ----
printf '\e[?25l\e[2J\e[H'
play() {
  local i last=""
  for i in $(seq 0 $(( ${#FRAMES[@]} - 1 ))); do
    if [ "$captions" = 1 ] && [ "${CAPTIONS[$i]}" != "$last" ]; then
      last=${CAPTIONS[$i]}
      printf '\e[2J\e[H\n  \e[2m%s\e[0m\n\n' "$last"
    fi
    printf '\e[4;1H\e[K  %s' "${FRAMES[$i]}"
    sleep "${HOLDS[$i]}"
  done
}
play
while [ "$loop" = 1 ]; do play; done
