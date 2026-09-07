#!/usr/bin/env bash
# Check the status line on this machine without touching the real tab.
# Part of claude-dipstick: https://github.com/heathdutton/claude-dipstick
#
#   bash tools/selftest.sh
#
# Prints the wiring, renders a sample payload, checks the width fit, the locale guard, the spend ledger and worktree
# detection against a throwaway repo.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# One clock for every render, so two renders of one payload can't disagree about a reset time because a minute ticked
# over between them.
CLAUDE_STATUSLINE_NOW=$(date +%s); export CLAUDE_STATUSLINE_NOW

payload() {  # $1 = session name ("" to omit), $2 = session id
  local name_field=""
  [ -n "$1" ] && name_field="\"session_name\":\"$1\","
  cat <<EOF
{"hook_event_name":"Status","session_id":"$2","cwd":"$PWD",$name_field
 "model":{"id":"claude-opus-5","display_name":"Opus 5"},
 "workspace":{"current_dir":"$PWD","project_dir":"$PWD"},
 "version":"0.0.0","output_style":{"name":"default"},
 "cost":{"total_cost_usd":0.5},
 "context_window":{"current_usage":{"input_tokens":10000,"cache_creation_input_tokens":20000,"cache_read_input_tokens":20000},"context_window_size":200000},
 "rate_limits":{"five_hour":{"used_percentage":14.000000000000002,"resets_at":$(( $(date +%s) + 9000 ))},
                "seven_day":{"used_percentage":6,"resets_at":$(( $(date +%s) + 400000 ))}},
 "exceeds_200k_tokens":false}
EOF
}

# Plain text, colors and OSC 8 links both stripped. A link's URL isn't on screen and must not count as cells.
strip() { LC_ALL=C perl -pe 's/\e\]8;;[^\a]*\a//g; s/\e\[[0-9;:]*m//g'; }

echo "== wiring =="
link="$HOME/.claude/statusline.sh"
if [ -L "$link" ]; then
  echo "  ~/.claude/statusline.sh -> $(readlink "$link")"
else
  echo "  ~/.claude/statusline.sh -- MISSING (run install.sh)"
fi
# Read it as JSON, not raw text. Anything that rewrites settings.json with an encoder that escapes forward slashes
# ("$HOME\/.claude\/statusline.sh") makes a plain grep report "pointing elsewhere" on a machine that's wired up fine.
statusline_cmd=$(python3 -c 'import json,sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sl = d.get("statusLine")
print(sl.get("command", "") if isinstance(sl, dict) else "")' \
  "$HOME/.claude/settings.json" 2>/dev/null)
case "$statusline_cmd" in
  *".claude/statusline.sh"*) echo "  settings.json -- pointed here" ;;
  "") echo "  settings.json -- no statusLine set (run install.sh)" ;;
  *)  echo "  settings.json -- pointing elsewhere: $statusline_cmd" ;;
esac

# The same two layers statusline.sh reads, in order, so the glyphs these checks look for are the ones this machine
# renders: the default table in statusline.sh, then the local file patching whichever keys it names. The local file is a
# patch, so a key it doesn't mention falls through rather than reading as empty.
config_local="$HOME/.claude/statusline-config.local.txt"
config="the defaults in statusline.sh"
echo "  config -- $config"
[ -f "$config_local" ] && { config="$config_local"; echo "  config -- $config_local (local, layered on top)"; }
cfg() {  # <KEY> -> its value, local winning, else the default beside that key in statusline.sh
  local v hit
  # Table lines read `lower_name="${UPPER_NAME-default}"`, one per key.
  v="$(sed -n 's/^[a-z_0-9]*="\${'"$1"'-\(.*\)}"$/\1/p' "$ROOT/statusline.sh" | tail -1)"
  if [ -f "$config_local" ]; then
    hit="$(grep "^$1=" "$config_local" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"')"
    [ -n "$hit" ] && v="$hit"
  fi
  printf '%s' "$v"
}

# Whatever glyph that config picked is what the worktree check looks for.
icon="$(cfg WORKTREE_ICON)"
[ -n "$icon" ] || icon="⋔"

# Everything is self-sourced, so the only wiring left to report is which account ~/.claude.json says is signed in.
cj="$HOME/.claude.json"
if [ -f "$cj" ]; then
  acct=$(sed -n 's/.*"displayName": *"\([^"]*\)".*/\1/p' "$cj" | head -1)
  [ -n "$acct" ] || acct=$(sed -n 's/.*"emailAddress": *"\([^"]*\)".*/\1/p' "$cj" | head -1)
  otype=$(sed -n 's/.*"organizationType": *"\([^"]*\)".*/\1/p' "$cj" | head -1)
  if [ -n "$acct" ]; then
    echo "  account -- $acct (${otype:-no plan reported})"
  else
    echo "  account -- no oauthAccount in ~/.claude.json (profile hidden, usage hidden)"
  fi
else
  echo "  account -- no ~/.claude.json (profile hidden, usage hidden)"
fi
echo ""
echo "== render =="
echo -n "  "
bash "$ROOT/statusline.sh" < <(payload "selftest session" "selftest-1")

# bash 3.2 has no \u escape in $'...', so a glyph written that way ships as six literal characters. That shipped once.
case "$(bash "$ROOT/statusline.sh" < <(payload "" "esc"))" in
  *'\u'*) echo "  FAIL -- literal \\u in the output (bash 3.2 cannot expand it; embed the glyph)"; exit 1 ;;
  *)       echo "  OK -- no unexpanded escapes in the rendered line" ;;
esac

# Claude Code discards the output of a status line that exits non-zero, so the line vanishes. Both shapes of render have
# to end clean.
bash "$ROOT/statusline.sh" < <(payload "" "rc") > /dev/null 2>&1
rc=$?
if [ "$rc" = 0 ]; then
  echo "  OK -- exits 0"
else
  echo "  FAIL -- exits $rc, so Claude Code shows nothing"; exit 1
fi

echo ""
echo "== width =="
# The bars size themselves to COLUMNS, which Claude Code exports. The footer keeps BAR_FIT_MARGIN columns of it, and the
# line must never run into them but should come within a bar's rounding. Cells are characters, so this needs UTF-8.
cells() { strip | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '; }
bw="$(cfg BAR_WIDTH)"
margin="$(cfg BAR_FIT_MARGIN)"
case "$margin" in ''|*[!0-9]*) margin=5 ;; esac
# Rendered against a throwaway repo on a short branch, so this measures the layout rather than today's branch name.
# Checked out as `statusline-account-scope` the live repo put the line 6 cells over at COLUMNS=110, which is a real
# overrun (the bars bottom out at BAR_WIDTH_MIN and Ink clips the tail) but says nothing about the fit.
git init -q -b main "$WORK/fitrepo" 2>/dev/null
git -C "$WORK/fitrepo" -c user.name=selftest -c user.email=selftest@example.invalid \
  commit -q --allow-empty -m init 2>/dev/null
fit_payload="$(cd "$WORK/fitrepo" && payload "" "fit")"   # one payload for every render, or the reset times straddle a minute
# With a warm prompt cache, the steady state after the first response. Without one the line holds a cell for a flame
# that never comes.
fit_payload="${fit_payload/\"exceeds_200k_tokens\":false/\"exceeds_200k_tokens\":false,\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"ttl\":\"1h\",\"expires_at\":$((CLAUDE_STATUSLINE_NOW + 1800))}}"
if [ "${bw:-auto}" != "auto" ]; then
  echo "  skipped -- BAR_WIDTH pinned to $bw in $config"
else
  for cols in 110 160; do
    w=$(( $(COLUMNS=$cols bash "$ROOT/statusline.sh" <<< "$fit_payload" | cells) - 1 ))   # minus the newline
    if [ "$w" -gt $((cols - margin)) ]; then
      echo "  FAIL -- $w cells at COLUMNS=$cols runs into the footer's $margin-column margin"; exit 1
    elif [ "$w" -lt $((cols - margin - 3)) ]; then
      echo "  FAIL -- $w cells at COLUMNS=$cols leaves the right side empty"; exit 1
    else
      echo "  OK -- $w cells at COLUMNS=$cols"
    fi
  done
fi
# A C locale counts bytes, which makes every glyph three or four cells and the fit come out short. statusline.sh
# switches itself to UTF-8.
utf="$(COLUMNS=160 bash "$ROOT/statusline.sh" <<< "$fit_payload")"
c="$(env -i HOME="$HOME" PATH="$PATH" LANG=C COLUMNS=160 CLAUDE_STATUSLINE_NOW="$CLAUDE_STATUSLINE_NOW" bash "$ROOT/statusline.sh" <<< "$fit_payload" 2>&1)"
if [ "$utf" = "$c" ]; then
  echo "  OK -- same line under LANG=C"
else
  echo "  FAIL -- LANG=C renders differently:"; printf '    %s\n' "$(printf '%s' "$c" | strip)"; exit 1
fi

echo ""
echo "== cost =="
# The payload carries $0.50. It's a bill only on an API key (no oauthAccount), so it shows there and not on a
# subscription. Whole dollars, nearest, and under 50c rounds to zero and hides along with a true zero. Both accounts
# come from throwaway HOMEs, so this says nothing about the real one.
cost_icon="$(cfg COST_ICON)"
[ -n "$cost_icon" ] || cost_icon="󰇁"
mkdir -p "$WORK/api" "$WORK/sub"
printf '{"oauthAccount":{"displayName":"Heath","emailAddress":"heath@example.com","organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_20x"}}\n' > "$WORK/sub/.claude.json"
cost_at() {  # <usd> -> the API-key line at that cost
  HOME="$WORK/api" bash "$ROOT/statusline.sh" \
    <<< "${fit_payload/\"total_cost_usd\":0.5/\"total_cost_usd\":$1}" | strip
}
api="$(HOME="$WORK/api" bash "$ROOT/statusline.sh" <<< "$fit_payload" | strip)"
sub="$(HOME="$WORK/sub" bash "$ROOT/statusline.sh" <<< "$fit_payload" | strip)"
case "$api" in
  *"$cost_icon 1"*) echo "  OK -- API key: \$0.50 rounds up to $cost_icon 1" ;;
  *) echo "  FAIL -- API key: cost missing from: $api"; exit 1 ;;
esac
case "$(cost_at 12.4)" in
  *"$cost_icon 12"*) echo "  OK -- \$12.40 rounds down to $cost_icon 12" ;;
  *) echo "  FAIL -- \$12.40 did not render as $cost_icon 12"; exit 1 ;;
esac
case "$(cost_at 0.49)" in
  *"$cost_icon"*) echo "  FAIL -- 49c showed instead of rounding to nothing"; exit 1 ;;
  *) echo "  OK -- under 50c hidden rather than shown as 0" ;;
esac
case "$(cost_at 0)" in
  *"$cost_icon"*) echo "  FAIL -- API key: zero cost still shows"; exit 1 ;;
  *) echo "  OK -- API key: zero cost hidden" ;;
esac
case "$sub" in
  *"$cost_icon"*) echo "  FAIL -- personal Max: the notional figure shows"; exit 1 ;;
  *) echo "  OK -- personal Max: notional cost hidden" ;;
esac
# An org seat is where somebody accounts for the spend, so "billed" shows it there and follows a swap on its own.
# Pinning SHOW_COST=always instead is what put a meaningless $49 on a personal login after switching accounts.
mkdir -p "$WORK/ent" "$WORK/team"
printf '{"oauthAccount":{"displayName":"Heath","emailAddress":"heath@acme.test","organizationType":"claude_enterprise","organizationRateLimitTier":"default_enterprise"}}\n' > "$WORK/ent/.claude.json"
printf '{"oauthAccount":{"displayName":"Heath","emailAddress":"heath@acme.test","organizationType":"claude_team","organizationRateLimitTier":"default_team"}}\n' > "$WORK/team/.claude.json"
for org in ent team; do
  case "$(HOME="$WORK/$org" bash "$ROOT/statusline.sh" <<< "$fit_payload" | strip)" in
    *"$cost_icon 1"*) echo "  OK -- $org seat: cost shows without SHOW_COST=always" ;;
    *) echo "  FAIL -- $org seat: cost hidden, so a work login needs the flag again"; exit 1 ;;
  esac
done

echo ""
echo "== weekly budget =="
# The ledger is the only state this script owns, so it gets checked for everything that would quietly corrupt a week: a
# session counted twice, a resume reporting zero, last week's rows, a torn line from a simultaneous render, and
# unbounded growth.
bud_home="$WORK/budget"; mkdir -p "$bud_home/.claude"
printf 'WEEKLY_BUDGET_USD=1000\nSHOW_BUDGET_LABEL=1\n' > "$bud_home/.claude/statusline-config.local.txt"
bud_ledger="$bud_home/.claude/statusline-spend.tsv"
# BAR_DIGITS=sub draws bar labels in subscript digits, so they come back to ASCII before anything compares them.
desub() { perl -CSD -pe 's/([\x{2080}-\x{2089}])/chr(ord($1)-0x2080+0x30)/ge'; }
bud() {  # <session> <usd> -> the rendered line
  local p="${fit_payload/\"total_cost_usd\":0.5/\"total_cost_usd\":$2}"
  HOME="$bud_home" bash "$ROOT/statusline.sh" <<< "${p/\"session_id\":\"fit\"/\"session_id\":\"$1\"}" | strip | desub
}
bud_want() {  # <expected dollars> <what it is checking>
  case "$1" in
    *"B: $2"*) echo "  OK -- $3" ;;
    *) echo "  FAIL -- $3 (wanted B: $2) in: ${1##*  }"; exit 1 ;;
  esac
}
bud a 10  > /dev/null
bud_want "$(bud a 25)"  25 "one session's later figure replaces its earlier one"
bud_want "$(bud b 30)"  55 "a second session adds to it"
bud_want "$(bud a 0)"   55 "a resumed session reporting 0 does not walk it back"
# Last week's rows, a line with no tabs, and a non-numeric stamp all get dropped.
printf 'lastweek\t%s\t99999\n' "$((CLAUDE_STATUSLINE_NOW - 14 * 86400))" >> "$bud_ledger"
printf 'no-tabs-at-all\n' >> "$bud_ledger"
printf 'bad\tNOTANUMBER\t500\n' >> "$bud_ledger"
bud_want "$(bud b 30)" 55 "last week's rows and malformed ones ignored"
# Twenty windows rendering at once. Append-only is what makes this safe... read-modify-write loses rows here, and an
# ended session never re-adds itself.
rm -f "$bud_ledger"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do bud "s$i" 1 > /dev/null & done
wait
torn=$(awk -F'\t' 'NF!=4 || $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/' "$bud_ledger" | wc -l | tr -d ' ')
distinct=$(cut -f2 "$bud_ledger" | sort -u | wc -l | tr -d ' ')
if [ "$torn" = 0 ] && [ "$distinct" = 20 ]; then
  echo "  OK -- 20 concurrent sessions, no torn or lost rows"
else
  echo "  FAIL -- concurrent writes lost rows ($distinct/20 sessions, $torn torn)"; exit 1
fi
bud_want "$(bud probe 0)" 20 "and they add up"
# A session ticking up past LEDGER_MAX has to compact rather than grow forever. Seeded rather than rendered 70 times,
# since the growth is what is under test and 70 renders is 6 seconds.
rm -f "$bud_ledger"
bud grow 1 > /dev/null                        # one real render, so the seeded rows carry the key this build writes
bud_acct_key="$(cut -f1 "$bud_ledger" | head -1)"
i=2
while [ "$i" -le 70 ]; do
  printf '%s\tgrow\t%s\t%s00\n' "$bud_acct_key" "$CLAUDE_STATUSLINE_NOW" "$i" >> "$bud_ledger"
  i=$((i + 1))
done
bud_want "$(bud grow 70)" 70 "compaction keeps the total"
rows=$(wc -l < "$bud_ledger" | tr -d ' ')
if [ "$rows" -le 64 ]; then
  echo "  OK -- ledger compacts instead of growing ($rows rows, was 70)"
else
  echo "  FAIL -- ledger grew to $rows rows unchecked"; exit 1
fi
# A read-only ~/.claude must still render and still exit 0, or the line vanishes.
chmod a-w "$bud_home/.claude"
bud_ro="$(bud ro 5)"; bud_rc=$?
chmod u+w "$bud_home/.claude"
if [ "$bud_rc" = 0 ]; then
  bud_want "$bud_ro" 75 "an unwritable ledger still renders the week"
else
  echo "  FAIL -- unwritable ledger exited $bud_rc, so the line disappears"; exit 1
fi
# The money is per account, so the ledger is. A work seat's week must not follow you to a personal login, and must still
# be there when you switch back.
rm -f "$bud_ledger"
bud_acct() {  # <organizationType> <email>
  printf '{"oauthAccount":{"displayName":"A","emailAddress":"%s","organizationType":"%s","organizationRateLimitTier":"t"}}\n' \
    "$2" "$1" > "$bud_home/.claude.json"
}
bud_acct claude_enterprise work@acme.test
bud w1 40 > /dev/null
bud_want "$(bud w2 30)" 70 "a work seat accumulates its own week"
bud_acct claude_max personal@example.test
bud_want "$(bud p1 5)" 5 "switching accounts does not carry that spend over"
bud_acct claude_enterprise work@acme.test
bud_want "$(bud w2 30)" 70 "and the work week survives the round trip"
if grep -q '@' "$bud_ledger"; then
  echo "  FAIL -- an email address landed in the ledger"; exit 1
else
  echo "  OK -- accounts keyed by hash, no address in the file"
fi
rm -f "$bud_home/.claude.json"

# And none of it happens without a budget set.
rm -f "$bud_home/.claude/statusline-config.local.txt" "$bud_ledger"
HOME="$bud_home" bash "$ROOT/statusline.sh" <<< "$fit_payload" > /dev/null
if [ -e "$bud_ledger" ]; then
  echo "  FAIL -- ledger written with no WEEKLY_BUDGET_USD set"; exit 1
else
  echo "  OK -- no budget, no bar, no file"
fi

echo ""
echo "== task line and agent rows =="
# A task list with work left puts a second line under the first, and all done it goes. The agent panel comes back as one
# JSON line per task.
mkdir -p "$WORK/api/.claude/tasks/selftest-tasks"
printf '{\n  "id": "1",\n  "subject": "Read the spec",\n  "activeForm": "Reading the spec",\n  "status": "completed"\n}\n' > "$WORK/api/.claude/tasks/selftest-tasks/1.json"
printf '{\n  "id": "2",\n  "subject": "Write it",\n  "activeForm": "Writing the migration",\n  "status": "in_progress"\n}\n' > "$WORK/api/.claude/tasks/selftest-tasks/2.json"
task_out="$(HOME="$WORK/api" bash "$ROOT/statusline.sh" <<< "${fit_payload/\"session_id\":\"fit\"/\"session_id\":\"selftest-tasks\"}" | strip)"
case "$(printf '%s\n' "$task_out" | wc -l | tr -d ' ')/$task_out" in
  2/*"Writing the migration"*) echo "  OK -- second line with the task in progress" ;;
  *) echo "  FAIL -- expected two lines and the active task:"; printf '    %s\n' "$task_out"; exit 1 ;;
esac
printf '{\n  "id": "2",\n  "status": "completed"\n}\n' > "$WORK/api/.claude/tasks/selftest-tasks/2.json"
n=$(HOME="$WORK/api" bash "$ROOT/statusline.sh" <<< "${fit_payload/\"session_id\":\"fit\"/\"session_id\":\"selftest-tasks\"}" | wc -l | tr -d ' ')
[ "$n" = 1 ] && echo "  OK -- one line once every task is done" || { echo "  FAIL -- $n lines with every task done"; exit 1; }
rows="$(printf '%s' '{"hook_event_name":"SubagentStatus","session_id":"x","columns":100,"tasks":[{"id":"a1","name":"reviewer","status":"running","description":"checking the tests","model":"claude-sonnet-5","effort":"high","contextWindowSize":200000,"tokenCount":50000},{"id":"a2","name":"builder","status":"running","description":"writing it","model":"claude-opus-5","contextWindowSize":200000,"tokenCount":120000}]}' | bash "$ROOT/statusline.sh")"
if printf '%s\n' "$rows" | python3 -c '
import json, sys
rows = [json.loads(l) for l in sys.stdin if l.strip()]
ok = len(rows) == 2 and [r["id"] for r in rows] == ["a1", "a2"] and all("\x1b[" in r["content"] and "reviewer" in rows[0]["content"] for r in rows)
sys.exit(0 if ok else 1)'; then
  echo "  OK -- two agent rows, valid JSON, styled"
else
  echo "  FAIL -- agent rows:"; printf '    %s\n' "$rows"; exit 1
fi

# A repo git cannot read must not read as clean. Empty --porcelain output also comes back with no git on PATH, on a
# checkout git refuses for dubious ownership, and on a corrupt index... a green tick over any of those is a claim the
# script is in no position to make.
mkdir -p "$WORK/unreadable/.git"
unreadable_payload="$(cd "$WORK/unreadable" && payload "" "unreadable")"
unreadable_out="$(cd "$WORK/unreadable" && printf '%s' "$unreadable_payload" | bash "$ROOT/statusline.sh" | strip)"
case "$unreadable_out" in
  *"$(printf '\xe2\x9c\x93')"*) echo "  FAIL -- claims clean on a repo git exits 128 on:"; printf '    %s\n' "$unreadable_out"; exit 1 ;;
  *) echo "  OK -- says nothing when git cannot read the repo" ;;
esac

echo ""
echo "== worktree =="
# A throwaway repo, so this says nothing about the repo the test runs from. Its own identity, so a machine without a
# global user.email still gets a commit rather than a branchless repo.
git init -q -b main "$WORK/repo" 2>/dev/null
git -C "$WORK/repo" -c user.name=selftest -c user.email=selftest@example.invalid \
  commit -q --allow-empty -m init 2>/dev/null
git -C "$WORK/repo" worktree add -q "$WORK/repo-TICKET-1" -b TICKET-1 2>/dev/null
# Assert the setup before anything leans on it. Without this a repo that failed to get a commit reports itself as
# "unpushed mark missing", which sends you looking at the wrong file... it was an intermittent mystery for a while.
if ! git -C "$WORK/repo" rev-parse --verify -q refs/heads/main > /dev/null; then
  echo "  FAIL -- setup: throwaway repo has no refs/heads/main, so the git checks below mean nothing"; exit 1
fi

wt_render() { (cd "$1" && bash "$ROOT/statusline.sh" < <(payload "" "wt")) | strip; }
mkdir -p "$WORK/repo/sub/deep"
main_line="$(wt_render "$WORK/repo")"
sub_line="$(wt_render "$WORK/repo/sub/deep")"
wt_line="$(wt_render "$WORK/repo-TICKET-1")"

echo ""
echo "== links and unpushed =="
# With an origin the branch links to its page, and till the remote has the commit the unpushed mark follows the name. No
# network... the remote ref is written by hand.
unpushed="$(cfg UNPUSHED_ICON)"
[ -n "$unpushed" ] || unpushed="󰅧"
git -C "$WORK/repo" remote add origin git@github.com:acme/app.git 2>/dev/null
raw="$(cd "$WORK/repo" && bash "$ROOT/statusline.sh" < <(payload "" "lnk"))"
case "$raw" in
  *$'\e]8;;https://github.com/acme/app/tree/main\a'*) echo "  OK -- branch links to https://github.com/acme/app/tree/main" ;;
  *) echo "  FAIL -- no branch link in: $(printf '%s' "$raw" | strip)"; exit 1 ;;
esac
case "$(printf '%s' "$raw" | strip)" in
  *"main $unpushed"*) echo "  OK -- unpushed mark while origin lacks the branch" ;;
  *) echo "  FAIL -- unpushed mark missing"; exit 1 ;;
esac
git -C "$WORK/repo" update-ref refs/remotes/origin/main HEAD
case "$(wt_render "$WORK/repo")" in
  *"$unpushed"*) echo "  FAIL -- unpushed mark still shows once origin has the commit"; exit 1 ;;
  *) echo "  OK -- mark gone once origin has the commit" ;;
esac
# The link's escape must not count toward the width, or the fit comes out short.
lw=$(( $(printf '%s' "$raw" | strip | LC_ALL=en_US.UTF-8 wc -m) ))
[ "$lw" -gt 40 ] && echo "  OK -- linked line still measures as text ($lw cells)"

echo ""
echo "== cache =="
cache_icon="$(cfg CACHE_ICON)"
[ -n "$cache_icon" ] || cache_icon="󰈸"

# The flame is a cost warning, not a health light, so the ordinary warm session shows nothing. fit_payload expires
# halfway through a 1h TTL.
cache_at() {  # <seconds of TTL left, or "cold"> -> a rendered line
  local p
  if [ "$1" = "cold" ]; then
    p="${fit_payload/\"warm\":true/\"warm\":false}"
  else
    p="${fit_payload/\"expires_at\":$((CLAUDE_STATUSLINE_NOW + 1800))/\"expires_at\":$((CLAUDE_STATUSLINE_NOW + $1))}"
  fi
  bash "$ROOT/statusline.sh" <<< "$p"
}
case "$(cache_at 1800 | strip)" in
  *"$cache_icon"*) echo "  FAIL -- flame lit while the cache is comfortably warm"; exit 1 ;;
  *) echo "  OK -- nothing while the cache holds" ;;
esac
# Inside the last CACHE_WARN_AT (25%) of a 1h TTL: lit, but not yet the cold tier.
warn_raw="$(cache_at 300)"
case "$(printf '%s' "$warn_raw" | strip)" in
  *"$cache_icon"*) echo "  OK -- flame lights as the TTL runs out" ;;
  *) echo "  FAIL -- no flame inside the warning window"; exit 1 ;;
esac
case "$warn_raw" in
  *$'\033[1m'*) echo "  FAIL -- warning tier used the cold tier's bold"; exit 1 ;;
  *) echo "  OK -- warning tier is amber, not bold" ;;
esac
cold_raw="$(cache_at cold)"
case "$(printf '%s' "$cold_raw" | strip)" in
  *"$cache_icon"*) echo "  OK -- cold cache shows the flame" ;;
  *) echo "  FAIL -- no flame for a cold cache"; exit 1 ;;
esac
case "$cold_raw" in
  *$'\033[1m'*) echo "  OK -- cold tier is bold, so it survives monochrome" ;;
  *) echo "  FAIL -- cold tier was not bold"; exit 1 ;;
esac
case "$(bash "$ROOT/statusline.sh" < <(payload "" "nocache") | strip)" in
  *"$cache_icon"*) echo "  FAIL -- flame shows with no prompt_cache in the payload"; exit 1 ;;
  *) echo "  OK -- no flame before caching is observed" ;;
esac
# Both lit tiers, since a cold cache is exactly when someone asks what the thing means.
cache_url="$(cfg CACHE_URL)"
[ -n "$cache_url" ] || cache_url="https://platform.claude.com/docs/en/build-with-claude/prompt-caching"
for tier in warn cold; do
  eval "tier_raw=\$${tier}_raw"
  case "$tier_raw" in
    *$'\e]8;;'"$cache_url"$'\a'*) echo "  OK -- $tier flame links to the prompt-caching docs" ;;
    *) echo "  FAIL -- $tier flame carries no link"; exit 1 ;;
  esac
done
# The URL must not cost cells, and a blank CACHE_URL keeps the glyph without the link.
[ "$(printf '%s' "$cold_raw" | strip | LC_ALL=en_US.UTF-8 wc -m)" -lt 200 ] &&
  echo "  OK -- the linked flame still measures as one glyph"
nolink_home="$(mktemp -d)"; mkdir -p "$nolink_home/.claude"
echo 'CACHE_URL=' > "$nolink_home/.claude/statusline-config.local.txt"
# Match the cache URL, not any URL... the folder and branch links are on this line too.
nolink_raw="$(HOME="$nolink_home" cache_at cold)"
case "$nolink_raw" in
  *"$cache_url"*) echo "  FAIL -- blank CACHE_URL still linked the flame"; exit 1 ;;
  *) echo "  OK -- blank CACHE_URL drops the link" ;;
esac
case "$(printf '%s' "$nolink_raw" | strip)" in
  *"$cache_icon"*) echo "  OK -- and keeps the flame" ;;
  *) echo "  FAIL -- blank CACHE_URL lost the glyph too"; exit 1 ;;
esac
rm -rf "$nolink_home"
# The held mark is opt-in, and a local config patches the default, so the one key is the whole file.
held_home="$(mktemp -d)"; mkdir -p "$held_home/.claude"
echo 'CACHE_HELD_ICON=󰆼' > "$held_home/.claude/statusline-config.local.txt"
case "$(HOME="$held_home" bash "$ROOT/statusline.sh" <<< "$fit_payload" | strip)" in
  *"󰆼"*) echo "  OK -- CACHE_HELD_ICON marks a holding cache when asked for" ;;
  *) echo "  FAIL -- CACHE_HELD_ICON did not render"; exit 1 ;;
esac
rm -rf "$held_home"

echo ""
echo "== local config =="
# The local file patches the defaults in statusline.sh rather than replacing them, so one unrelated key must leave the
# rest of the line alone. Under the first-hit-wins ordering this blanked the branch, the meter and the bars in one go.
lay_home="$(mktemp -d)"; mkdir -p "$lay_home/.claude"
lay_config="$lay_home/.claude/statusline-config.local.txt"
echo 'PROFILE_NAME=TESTACCT' > "$lay_config"
branch_icon="$(cfg BRANCH_ICON)"; [ -n "$branch_icon" ] || branch_icon="󰘬"
lay="$(cd "$WORK/repo" && HOME="$lay_home" bash "$ROOT/statusline.sh" <<< "$fit_payload" | strip)"
case "$lay" in
  *"$branch_icon"*) echo "  OK -- a one-key local config keeps the rest of the default" ;;
  *) echo "  FAIL -- one-key local config wiped the branch: $lay"; exit 1 ;;
esac
case "$lay" in
  *TESTACCT*) echo "  OK -- and still wins on the key it does set" ;;
  *) echo "  FAIL -- local key ignored: $lay"; exit 1 ;;
esac
# Blank is a value, not a miss. Several keys are documented as "blank one to drop it", which only works if an empty
# assignment beats the default instead of falling through to it.
usage_icon="$(sed -n 's/^usage_icon="\${USAGE_ICON-\(.*\)}"$/\1/p' "$ROOT/statusline.sh")"
echo 'USAGE_ICON=' > "$lay_config"
blanked="$(cd "$WORK/repo" && HOME="$lay_home" bash "$ROOT/statusline.sh" <<< "$fit_payload" | strip)"
if [ -z "$usage_icon" ]; then
  echo "  skipped -- USAGE_ICON has no default to blank"
else
  case "$blanked" in
    *"$usage_icon"*) echo "  FAIL -- USAGE_ICON= left the default glyph in place: $blanked"; exit 1 ;;
    *) echo "  OK -- a blank in the local config blanks the key" ;;
  esac
fi
rm -rf "$lay_home"

echo ""
echo "== profile link =="
# A throwaway HOME has no ~/.claude.json, so the account reads as an API key and the link points at the Console.
# PROFILE_NAME is forced because the real label comes from whoever is signed in.
prof_home="$(mktemp -d)"; mkdir -p "$prof_home/.claude"
prof_config() { { echo "PROFILE_NAME=TESTACCT"; echo "$1"; } \
  > "$prof_home/.claude/statusline-config.local.txt"; }
prof_config ""
case "$(HOME="$prof_home" bash "$ROOT/statusline.sh" <<< "$fit_payload")" in
  *"https://console.anthropic.com/settings/usage"*)
    echo "  OK -- an API-key account links to the Console" ;;
  *) echo "  FAIL -- no Console usage link for an API-key account"; exit 1 ;;
esac
prof_config "PROFILE_URL=https://example.test/team"
case "$(HOME="$prof_home" bash "$ROOT/statusline.sh" <<< "$fit_payload")" in
  *"https://example.test/team"*) echo "  OK -- PROFILE_URL overrides it" ;;
  *) echo "  FAIL -- PROFILE_URL was ignored"; exit 1 ;;
esac
prof_config "LINKS=0"
case "$(HOME="$prof_home" bash "$ROOT/statusline.sh" <<< "$fit_payload")" in
  *"settings/usage"*) echo "  FAIL -- profile linked with LINKS=0"; exit 1 ;;
  *TESTACCT*) echo "  OK -- LINKS=0 leaves the label unlinked" ;;
  *) echo "  FAIL -- profile label missing entirely"; exit 1 ;;
esac
rm -rf "$prof_home"

# A subdirectory of a plain repo is the case that used to false-positive. Below the root git returns an absolute
# --git-dir but a relative --git-common-dir, so a raw string compare called every subdir a worktree.
case "$sub_line" in
  *"$icon"*) echo "  FAIL -- subdirectory of a plain repo showed a worktree marker"; echo "    $sub_line"; exit 1 ;;
  *)         echo "  OK -- plain repo subdirectory unmarked (${sub_line%%  *})" ;;
esac
case "$main_line" in
  *"$icon"*) echo "  FAIL -- main checkout showed a worktree marker"; echo "    $main_line"; exit 1 ;;
  *)         echo "  OK -- main checkout unmarked" ;;
esac
# Second element of the line, between the double-space separators, is the repo mark.
wt_repo=${wt_line#*  }; wt_repo=${wt_repo%%  *}
case "$wt_line" in
  *"$icon"*) echo "  OK -- linked worktree marked: $wt_repo" ;;
  *)         echo "  FAIL -- linked worktree unmarked"; echo "    $wt_line"; exit 1 ;;
esac
