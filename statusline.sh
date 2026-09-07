#!/bin/bash
#
#   ▁▂▃▄▅▆▇█  claude-dipstick
#
#   A status line for Claude Code. Shows context, model, session usage, week usage, budget/cost
#   (if applicable) and more. No dependencies.
#
#   https://github.com/heathdutton/claude-dipstick
#
# Everything comes from the stdin payload and the credentials Claude Code already keeps. If install.sh did not wire it:
#
#   "statusLine": { "type": "command", "command": "bash \"$HOME/.claude/statusline.sh\"", "refreshInterval": 60 }
#
# Two config layers. The defaults below, then $HOME/.claude/statusline-config.local.txt for this machine, which is a
# patch... one key in it, the rest inherited. A blank counts as a setting, so USAGE_ICON= gives that bar its cell back.

# ${#var} and ${var:i:1} count characters under UTF-8 and bytes under C, and every glyph here is 3 or 4 bytes. Bar
# labels and the width fit both need the character count. A stripped environment gets no LANG... bash 3.2 honours the
# switch mid-script.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
  *) unset LC_ALL; export LC_CTYPE=en_US.UTF-8 ;;
esac

# Sourced first, so each line of the table below is that key's default and nothing else has to hold one. An exported key
# wins over both, which falls out of the same form and makes a one-off `BAR_WIDTH=20 bash statusline.sh` work.
[ -f "$HOME/.claude/statusline-config.local.txt" ] && source "$HOME/.claude/statusline-config.local.txt"

show_model="${SHOW_MODEL-1}"
# glyph = the family as a shape (MODEL_MARK_* below) riding in the context meter, effort growing out of its end.
# Unreadable over a shoulder on purpose... "OM" announces Opus at max, a shape and a run announce nothing.
# icon/name/both/full are the old styles.
model_style="${MODEL_STYLE-glyph}"
# Effort multiplies the model and the context, so it draws as a scale in the meter's color, shifting cyan to red with
# it.
#   chevrons  the meter's arrow cap five times over, one per level. Lit ones are solid bands fading outward, unlit
#             ones the arrow's outline in a dim tint, so all five are countable. EFFORT_CHEVRON_FADE is the shade
#             (percent) the fifth lit band fades to, EFFORT_CHEVRON_DIM the shade of an unlit outline.
#   pill      four EFFORT_RAMP steps in a capsule, closing hemisphere the fifth. Also the fallback with no arrow
#             cap or background to hand off.
effort_style="${EFFORT_STYLE-chevrons}"
effort_chevron_fade="${EFFORT_CHEVRON_FADE-45}"
effort_chevron_dim="${EFFORT_CHEVRON_DIM-35}"
# Space separated so splitting never indexes into a multibyte glyph.
effort_ramp_glyphs="${EFFORT_RAMP-▁ ▃ ▅ ▆}"
# Pill is pure black so lit steps read as lit. Unlit steps and hemisphere sit in the dim grey. EFFORT_LIT_COLOR takes
# context (default), family, or a hex.
effort_pill_color="${EFFORT_PILL_COLOR-#000000}"
effort_lit_color="${EFFORT_LIT_COLOR-context}"
effort_dim_color="${EFFORT_DIM_COLOR-#555555}"
# Family marks: sides descend with capability. Circle is the limit of polygons, then hexagon, square, triangle, then a
# dot a quarter the area of the rest. Abstract on purpose... a square says nothing about which model, let alone which
# vendor.
#
# Hexagon and circle are the close pair, and measured they do separate: md-hexagon is pointy-top at 1233x1370, so it
# breaks the circle's 1233x1234 box top and bottom while its own sides run flat. If it still reads as a circle in your
# font, MODEL_MARK_FABLE=󰋙 (md-hexagon_outline) is the escape hatch.
#
# Every mark is U+F0000 and up, the plane Nerd Fonts have to themselves. macOS system fonts also claim the BMP
# private-use range (U+E000-F8FF), so a glyph there can lose the fallback race and render as nothing... Haiku's dot did
# exactly that as oct-dot_fill U+F444.
#
# Names and bounding boxes read out of HackNerdFontMono, not guessed. All four large marks are 1233 units wide so they
# carry equal weight. oct-dot_fill is 617, which is what made Haiku read as the runt.
model_mark_mythos="${MODEL_MARK_MYTHOS-󰝥}"
model_mark_fable="${MODEL_MARK_FABLE-󰋘}"
model_mark_opus="${MODEL_MARK_OPUS-󰝤}"
model_mark_sonnet="${MODEL_MARK_SONNET-󰔶}"
model_mark_haiku="${MODEL_MARK_HAIKU-󰧞}"
# Family colors, Starship Pastel Powerline again. Monochrome ignores them and falls back to letters.
model_color_mythos="${MODEL_COLOR_MYTHOS-#DA627D}"
model_color_opus="${MODEL_COLOR_OPUS-#9A348E}"
model_color_fable="${MODEL_COLOR_FABLE-#D4AF37}"
model_color_sonnet="${MODEL_COLOR_SONNET-#86BBD8}"
model_color_haiku="${MODEL_COLOR_HAIKU-#06969A}"
model_icon_mythos="${MODEL_ICON_MYTHOS-M}"
model_icon_opus="${MODEL_ICON_OPUS-O}"
model_icon_fable="${MODEL_ICON_FABLE-F}"
model_icon_sonnet="${MODEL_ICON_SONNET-S}"
model_icon_haiku="${MODEL_ICON_HAIKU-H}"
model_icon_default="${MODEL_ICON_DEFAULT-}"
show_effort="${SHOW_EFFORT-1}"
effort_label_low="${EFFORT_LABEL_LOW-L}"
effort_label_medium="${EFFORT_LABEL_MEDIUM-}"
effort_label_high="${EFFORT_LABEL_HIGH-H}"
effort_label_xhigh="${EFFORT_LABEL_XHIGH-X}"
effort_label_max="${EFFORT_LABEL_MAX-M}"
show_dir="${SHOW_DIRECTORY-1}"
# session = the folder claude started in, the one word that means anything when it sits a few levels deep. repo = path
# relative to the git root. basename = just the folder.
dir_style="${DIR_STYLE-session}"
dir_icon="${DIR_ICON-}"
show_branch="${SHOW_BRANCH-1}"
# md-source_branch, U+F062C. Nerd Font, supplementary plane like the model marks.
branch_icon="${BRANCH_ICON-󰘬}"
# Dirty/clean marker. Costs a `git status` per render: ~12ms normally, 59ms on a very large working tree.
show_git_status="${SHOW_GIT_STATUS-1}"
git_clean_icon="${GIT_CLEAN_ICON-✓}"
# N files edited. md-plus_minus_box, U+F0993. The box is what stops it reading as arithmetic, which a bare ± and the
# Octicons "diff" glyph both did.
git_dirty_icon="${GIT_DIRTY_ICON-󰦓}"
# When the last edited file lives in a different repo than the cwd, show that repo's branch. Ticket folders symlink the
# real checkout out of the tree, so the cwd's branch says nothing.
show_active_repo="${SHOW_ACTIVE_REPO-1}"
show_worktree="${SHOW_WORKTREE-1}"
worktree_icon="${WORKTREE_ICON-⋔}"
# Cmd-clickable links (OSC 8, in iTerm2/Kitty/WezTerm, ignored elsewhere): folder opens in Finder, branch or worktree
# opens its page on the repo's host, PR opens the PR. The host comes from the repo's own origin URL, so GitHub, GitLab
# (self-hosted too), Bitbucket Cloud and Server, Gitea/Forgejo/Codeberg and Azure DevOps all resolve. Anything else
# links to the repo root. BRANCH_LINK_TEMPLATE overrides with {host} {path} {branch}, e.g.
#   https://{host}/{path}/-/tree/{branch}
links="${LINKS-1}"
# none, or straight. Nothing subtler is on offer: Claude Code re-serialises the line through a model with one underline
# boolean, so a dotted style (SGR 4:4) arrives as a plain 4 and an underline color (SGR 58) is dropped, leaving the
# solid rule the style was meant to avoid. iTerm2 also underlines OSC 8 links on its own... turn that off with `defaults
# write com.googlecode.iterm2 underlineHyperlinks -bool false` (Settings > Advanced > Drawing). Cmd-hover underlines
# either way.
link_underline="${LINK_UNDERLINE-none}"
# A link's glyph as a percent of the element's color. The name is what gets read, so the icon sits behind it. 100 makes
# them one color again. A non-truecolor palette has nothing to tint and ignores it.
link_icon_tint="${LINK_ICON_TINT-60}"
branch_link_template="${BRANCH_LINK_TEMPLATE-}"
# The branch's ref against the remote's copy, read from the ref files, no fork. Differing or never pushed puts
# md-cloud_upload (U+F0167) after the name. No ahead/behind count, that costs a git call per render.
show_unpushed="${SHOW_UNPUSHED-1}"
unpushed_icon="${UNPUSHED_ICON-󰅧}"
git_remote="${GIT_REMOTE-origin}"
# The branch's open PR from pr.number / pr.url / pr.review_state: green approved, red changes requested, grey draft,
# amber otherwise, linked. md-source_pull, U+F04C2.
show_pr="${SHOW_PR-1}"
pr_icon="${PR_ICON-󰓂}"
# A second line while the task list has work left: a meter of done over total in the bars' width, then the task in
# progress. Claude Code keeps the list under ~/.claude/tasks/<session_id>/. Subagents aren't repeated here, the agent
# panel below the prompt lists those (see SUBAGENT_BAR_WIDTH). md-format_list_checks U+F0756, indigo 300.
show_tasks="${SHOW_TASKS-1}"
task_icon="${TASK_ICON-󰝖}"
task_color="${TASK_COLOR-#7986CB}"
# Agent-panel rows: family shape, a context meter this many cells wide, the effort run out of the cap, then the name and
# what fits of the description.
subagent_bar_width="${SUBAGENT_BAR_WIDTH-10}"
show_context="${SHOW_CONTEXT-1}"
show_context_bar="${SHOW_CONTEXT_BAR-1}"
# Ride the model/effort dial in the meter's first cell, since what it relates is one thing: which model, at what effort,
# eating how much context. Needs MODEL_STYLE=glyph, anything wider gets its own element.
model_in_context="${MODEL_IN_CONTEXT-1}"
# The prompt cache, beside the meter. It answers "what does the next turn cost", so it's quiet while the answer is
# "almost nothing". Nothing at all while the cache holds, amber through the last CACHE_WARN_AT percent of the TTL (where
# sending now still reads the prefix from cache), then red and bold once cold, where the next turn rewrites the whole
# prefix at the cache-write premium. Set CACHE_HELD_ICON to mark the holding state too... 󰆼 (md-database, U+F01BC) suits
# it, at CACHE_HELD_TINT percent of the meter's color. Claude Code re-renders at expiry and every refreshInterval
# between, so the ramp keeps time. md-fire, U+F0238.
show_cache="${SHOW_CACHE-1}"
cache_icon="${CACHE_ICON-󰈸}"
cache_held_icon="${CACHE_HELD_ICON-}"
cache_held_tint="${CACHE_HELD_TINT-45}"
cache_warn_at="${CACHE_WARN_AT-25}"

# Bars. Every one carries its own number inside, so the C:/S:/W:/B: labels are off.
#   solid   filled run painted as a background, label knocked out of it
#   blocks  the same layout in ▓/░, for monochrome or no truecolor backgrounds
# BAR_WIDTH=auto sizes them all to the terminal: Claude Code exports COLUMNS, everything that isn't a bar gets measured,
# and the bars split the rest equally between BAR_WIDTH_MIN and BAR_WIDTH_MAX cells. A number pins them. BAR_FIT_MARGIN
# is what the footer takes off COLUMNS first: 2 columns of padding each side and a 1-column gap before the right-hand
# indicators (IDE selection, PR badge, "focus"). Those take their own width on top when they show and the line's tail
# gives way, so raise this if one is a fixture on your screen.
bar_width="${BAR_WIDTH-auto}"
bar_width_min="${BAR_WIDTH_MIN-10}"
bar_width_max="${BAR_WIDTH_MAX-64}"
bar_fit_margin="${BAR_FIT_MARGIN-5}"
# Digits inside the bars, small enough to sit in one rather than compete with it: sub (₀₁₂₃₄₅₆₇₈₉), super (⁰¹²³⁴⁵⁶⁷⁸⁹),
# or plain. Hack has the superscripts but no subscripts, so sub relies on fallback to a face that has them (Menlo,
# Monaco and Apple Symbols all do on a Mac).
bar_digits="${BAR_DIGITS-sub}"
bar_style="${BAR_STYLE-solid}"
bar_track_color="${BAR_TRACK_COLOR-#343434}"
# tint: the empty track is a dark tint of the bar's own color, so each bar is one object end to end, and the effort
# pill is darker still. neutral: the flat grey above for every bar. BAR_TRACK_TINT is the percent used for the track,
# and the pill and its unlit steps likewise.
bar_track="${BAR_TRACK-tint}"
bar_track_tint="${BAR_TRACK_TINT-30}"
effort_pill_tint="${EFFORT_PILL_TINT-18}"
effort_dim_tint="${EFFORT_DIM_TINT-55}"
bar_text_color="${BAR_TEXT_COLOR-#1c1c1c}"
# End caps: powerline (rounded, needs a Nerd Font), half (▐▌, any font), none. The rest of the line needs a Nerd Font
# anyway. On a machine without one set BAR_CAPS=half, or the caps show as tofu boxes.
bar_caps="${BAR_CAPS-powerline}"
context_as_tokens="${CONTEXT_AS_TOKENS-0}"
show_usage="${SHOW_USAGE-1}"
# This session's cost, just ahead of the session bar it was spent in and in that bar's color. Claude Code computes it
# client-side at list price whoever is paying, so on a Max or Pro login it is what the session would have cost, not a
# bill.
#   billed   where somebody is accounting for it: an API-key account, a gateway metering a spend limit, or an
#            enterprise/team seat, where usage is attributed and charged back. Hidden on a personal Max or Pro,
#            where the plan flatly covers the session and the number is noise.  (default)
#   always   the list-price figure regardless
#   never
#
# That split is what makes this follow an account swap on its own. Lumping every subscription together meant seeing the
# figure on a work seat took SHOW_COST=always, which then put a meaningless $49 on a personal login. Whole dollars,
# nearest, hidden under 50c: cents were three digits of precision on a number nobody acts on that finely, and the ".50"
# shoved everything right of it a cell as it ticked. md-currency_usd, U+F01C1.
show_cost="${SHOW_COST-billed}"
cost_icon="${COST_ICON-󰇁}"
# Spend against a weekly budget of your own, as a fourth bar. Off till WEEKLY_BUDGET_USD holds a number, since there's
# no sane default for somebody else's budget.
#
# The payload only carries the CURRENT session's cost, so the week's total is kept in ~/.claude/statusline-spend.tsv,
# appended to when the figure moves and pruned to the current week. Counts what this Mac spent, in sessions whose status
# line rendered. A gauge, not an invoice.
#
# Rows are keyed by account, so a work seat's week does not follow you to a personal login and is still there when you
# switch back. The key is a hash, so the file holds no address.
#
# BUDGET_WEEK_START is mon or sun, local midnight. The plan's seven_day window resets on its own schedule and would drag
# the money week around with it, so the two aren't tied.
#
# The pace marker is the week's clock, same as the weekly bar: behind it is under budget for the day, ahead is over.
# md-wallet, U+F0584.
weekly_budget_usd="${WEEKLY_BUDGET_USD-}"
budget_week_start="${BUDGET_WEEK_START-mon}"
show_budget="${SHOW_BUDGET-1}"
show_budget_bar="${SHOW_BUDGET_BAR-1}"
show_budget_label="${SHOW_BUDGET_LABEL-0}"
budget_icon="${BUDGET_ICON-󰖄}"
element_color_budget="${ELEMENT_COLOR_BUDGET-}"
# Lead glyphs for the two window bars, riding in the first cell like the model shape does: clock for the 5-hour session
# (md-clock_outline, U+F0150), calendar for the week (md-calendar_week, U+F0A33). Blank one to give that bar its cell
# back.
usage_icon="${USAGE_ICON-󰅐}"
weekly_icon="${WEEKLY_ICON-󰨳}"
show_bar="${SHOW_PROGRESS_BAR-1}"
show_pace_marker="${SHOW_PACE_MARKER-1}"
# The marker sits back from the bar, a tint nearer the track than the fill: there when looked for, quiet otherwise. 100
# is full strength.
pace_marker_tint="${PACE_MARKER_TINT-55}"
pace_marker_step_colors="${PACE_MARKER_STEP_COLORS-0}"
show_reset="${SHOW_RESET_TIME-1}"
use_24h="${USE_24_HOUR_TIME-0}"
show_context_label="${SHOW_CONTEXT_LABEL-0}"
show_usage_label="${SHOW_USAGE_LABEL-0}"
show_reset_label="${SHOW_RESET_LABEL-0}"
# Two spaces, not a glyph. The bars already end at a hard edge, so a dot between them did no work.
section_separator="${SECTION_SEPARATOR-  }"
color_mode="${COLOR_MODE-colored}"
single_color="${SINGLE_COLOR-#00BFFF}"
show_profile="${SHOW_PROFILE-1}"
# PROFILE_NAME defaults to empty on purpose. It names whichever Claude account is active, so it can't be a shipped
# constant shared across people... the label is read from ~/.claude.json (oauthAccount) every render, so it follows a
# swap immediately. Pin one on a single machine in ~/.claude/statusline-config.local.txt.
profile_name="${PROFILE_NAME-}"
# PROFILE_STYLE picks what that label says:
#   name       displayName, or the email local-part if it is unset  (default)
#   email      the email local-part
#   plan       the subscription: MAX20, PRO, TEAM, ENT, FREE
#   name+plan  both, space separated
profile_style="${PROFILE_STYLE-name}"
# The tier as a glyph, ahead of the label. The default style is the name alone, so this is the only place the tier
# shows... icon says what kind of account, text says whose. Blank one to drop it for that tier. md-crown,
# md-account_circle, md-account_group, md-office_building, md-account, md-account_outline (the fallback, and what an
# API-key account with no oauthAccount gets).
profile_icon_max="${PROFILE_ICON_MAX-󰆥}"
profile_icon_pro="${PROFILE_ICON_PRO-󰀉}"
profile_icon_team="${PROFILE_ICON_TEAM-󰡉}"
profile_icon_enterprise="${PROFILE_ICON_ENTERPRISE-󰦑}"
profile_icon_free="${PROFILE_ICON_FREE-󰀄}"
profile_icon_default="${PROFILE_ICON_DEFAULT-󰀓}"
# Cmd-click the profile for the usage page of whoever is billed: claude.ai on a subscription, the Console on an API key,
# since that's where each one's numbers live. PROFILE_URL sends it elsewhere. Needs LINKS=1.
profile_url="${PROFILE_URL-}"
show_weekly="${SHOW_WEEKLY-1}"
show_weekly_bar="${SHOW_WEEKLY_BAR-1}"
show_weekly_pace_marker="${SHOW_WEEKLY_PACE_MARKER-1}"
show_weekly_reset="${SHOW_WEEKLY_RESET_TIME-1}"
show_weekly_label="${SHOW_WEEKLY_LABEL-0}"
show_extra_usage="${SHOW_EXTRA_USAGE-1}"
# Starship Pastel Powerline, so COLOR_MODE=perElement matches a prompt on that theme. Inert under the default
# COLOR_MODE=colored.
element_color_dir="${ELEMENT_COLOR_DIR-#DA627D}"
element_color_branch="${ELEMENT_COLOR_BRANCH-#FCA17D}"
element_color_worktree="${ELEMENT_COLOR_WORKTREE-#33658A}"
element_color_model="${ELEMENT_COLOR_MODEL-#86BBD8}"
element_color_profile="${ELEMENT_COLOR_PROFILE-#9A348E}"
element_color_context="${ELEMENT_COLOR_CONTEXT-#06969A}"
element_color_separator="${ELEMENT_COLOR_SEPARATOR-#585858}"
element_color_usage="${ELEMENT_COLOR_USAGE-}"
element_color_pace="${ELEMENT_COLOR_PACE-}"
element_color_weekly="${ELEMENT_COLOR_WEEKLY-}"
element_color_extra="${ELEMENT_COLOR_EXTRA-}"

# Anything unparseable in the width keys falls back rather than tripping the arithmetic below. BAR_WIDTH is either
# "auto" or a cell count.
case "$bar_width" in auto|[0-9]*) ;; *) bar_width=auto ;; esac
case "$bar_width" in *[!0-9a-z]*) bar_width=auto ;; esac
case "$bar_width_min" in ''|*[!0-9]*) bar_width_min=10 ;; esac
case "$bar_width_max" in ''|*[!0-9]*) bar_width_max=64 ;; esac
case "$bar_fit_margin" in ''|*[!0-9]*) bar_fit_margin=5 ;; esac
case "$effort_chevron_fade" in ''|*[!0-9]*) effort_chevron_fade=45 ;; esac
case "$effort_chevron_dim" in ''|*[!0-9]*) effort_chevron_dim=35 ;; esac
case "$cache_held_tint" in ''|*[!0-9]*) cache_held_tint=45 ;; esac
case "$cache_warn_at" in ''|*[!0-9]*) cache_warn_at=25 ;; esac
[ "$cache_warn_at" -gt 100 ] && cache_warn_at=100
case "$subagent_bar_width" in ''|*[!0-9]*) subagent_bar_width=10 ;; esac
case "$link_icon_tint" in ''|*[!0-9]*) link_icon_tint=60 ;; esac
# What underline a link wears, and why the list is only two long.
#
# Claude Code doesn't hand the line to the terminal as written. It parses it into a model of its own and re-serialises,
# inventing an id= on the OSC 8 on the way, and that model holds one underline boolean: no style, no color. SGR 4:4
# arrives as a plain 4, SGR 58 never arrives, so you get a solid rule in the text's own color... exactly what a dotted
# tint was meant to replace. iTerm2 draws 4:4 and 58 correctly through cat, so the terminal isn't the thing to fix.
case "$link_underline" in
  straight) link_underline_sgr="4" ;;
  *)        link_underline_sgr="" ;;   # none
esac
case "$pace_marker_tint" in ''|*[!0-9]*) pace_marker_tint=55 ;; esac

# Digits the bars print with. Hack has the superscripts, not the subscripts, so "sub" leans on fallback to a face that
# does... Menlo on a Mac, same Bitstream Vera lineage, so the metrics match. Without one they are tofu.
case "$bar_digits" in
  super) bar_digit_glyphs="⁰¹²³⁴⁵⁶⁷⁸⁹" ;;
  sub)   bar_digit_glyphs="₀₁₂₃₄₅₆₇₈₉" ;;
  *)     bar_digit_glyphs="" ;;
esac



# date(1) portability: BSD (macOS) first, GNU (Linux) as fallback.
epoch_fmt() {  # epoch seconds, strftime format -> local time string
  date -r "$1" "$2" 2>/dev/null || date -d "@$1" "$2" 2>/dev/null
}

# "5pm", not "05:00 PM". Minutes show only when they aren't :00, the day only when the window crosses one. By hand
# because strftime's %-I is a GNU extension BSD date lacks, and padding is only half of it anyway.
short_time=""
fmt_short_time() {  # <epoch> <with_day 0|1> -> sets short_time
  local raw h m ap day=""
  if [ "$use_24h" = "1" ]; then
    if [ "$2" = "1" ]; then
      short_time=$(epoch_fmt "$1" "+%a %H:%M")
    else
      short_time=$(epoch_fmt "$1" "+%H:%M")
    fi
    return
  fi
  if [ "$2" = "1" ]; then
    raw=$(epoch_fmt "$1" "+%a %I:%M %p")
    day=${raw%% *}
    raw=${raw#* }
  else
    raw=$(epoch_fmt "$1" "+%I:%M %p")
  fi
  short_time=""
  [ -n "$raw" ] || return
  h=${raw%%:*}
  ap=${raw##* }
  m=${raw#*:}
  m=${m%% *}
  h=${h#0}
  [ -n "$h" ] || h=12
  case "$ap" in
    AM|am) ap=am ;;
    *)     ap=pm ;;
  esac
  if [ "$m" = "00" ]; then
    short_time="${h}${ap}"
  else
    short_time="${h}:${m}${ap}"
  fi
  [ -n "$day" ] && short_time="${day} ${short_time}"
}
# Eighth-blocks, so the fill boundary lands inside a cell instead of jumping a whole one. Indexed 1/8 through 7/8.
BAR_PARTIALS=(▏ ▎ ▍ ▌ ▋ ▊ ▉)

# Cells a rendered string takes, color and OSC 8 escapes stripped. The width fit, the agent rows and the task line all
# measure with this.
pw=0
plain_width() {  # <string> -> pw, cells once the SGR and OSC 8 sequences are removed
  local s=$1 out=""
  while :; do   # hyperlinks first: ESC ] ... BEL
    case "$s" in *$'\033]'*) ;; *) break ;; esac
    out="${out}${s%%$'\033]'*}"
    s=${s#*$'\033]'}
    s=${s#*$'\a'}
  done
  s="${out}${s}"; out=""
  while :; do   # then colors: ESC [ ... m
    case "$s" in *$'\033['*) ;; *) break ;; esac
    out="${out}${s%%$'\033['*}"
    s=${s#*$'\033['}
    s=${s#*m}
  done
  pw=$(( ${#out} + ${#s} ))
}

# OSC 8 hyperlink, BEL-terminated the way the Claude Code docs write it. Terminals without it show the text and drop the
# rest. iTerm2, Kitty and WezTerm make it Cmd-clickable, and it costs no width either way.
#
# No underline by default: color already marks the element, and the only rule Claude Code can carry is the harsh solid
# one. Closed inside the link so it can't bleed onto whatever the caller appends.
linked=""
link() {  # <url> <text> -> linked
  if [ "$links" != "1" ] || [ -z "$1" ]; then
    linked=$2
    return
  fi
  local deco="" close=""
  if [ -n "$link_underline_sgr" ]; then
    deco=$'\033['"$link_underline_sgr"'m'
    close=$'\033[24m'
  fi
  linked=$'\033]8;;'"$1"$'\a'"${deco}${2}${close}"$'\033]8;;\a'
}

# Glyph plus name, the glyph at LINK_ICON_TINT of the element's color. The word is what gets read, so the icon sits
# behind it... the hierarchy the tinted underline wanted, in a channel Claude Code actually forwards. A non-truecolor
# palette has nothing to tint and both stay one color.
glyphed=""
glyph_label() {  # <icon> <label> <element color> -> glyphed
  glyphed="${1:+$1 }$2"
  [ -n "$1" ] || return
  tint "$3" "$link_icon_tint"
  [ -n "$tinted" ] || return
  glyphed=$'\033[38;2;'"${tinted}"'m'"$1 $3$2"
}


# One bar per window, all one width, number inside it rather than beside it.
#
# "solid" paints the fill as a background and lays the label over it, so each digit flips from track-colored to
# knocked-out as the fill passes. The boundary cell carries an eighth-block, which is what stops visible stepping.
# "blocks" is the same layout in ▓/░, the monochrome fallback where a background carries nothing.
#
# Pure bash throughout. This runs four times a render and $( ) forks.

# A darker truecolor escape as "R;G;B", ready to wrap in 38;2; or 48;2;. Only the 38;2; form is tintable... a
# 256-color or plain code leaves tinted empty and the caller keeps its fallback.
tinted=""
tint() {  # <truecolor fg escape> <percent> -> sets tinted
  tinted=""
  local body=${1#*\[38;2;}
  [ "$body" != "$1" ] || return
  body=${body%m}
  local r g b
  IFS=';' read -r r g b <<< "$body"
  case "$r$g$b" in ''|*[!0-9]*) return ;; esac
  tinted="$((r * $2 / 100));$((g * $2 / 100));$((b * $2 / 100))"
}

# The same color as a background. Three forms turn up: the 256-color ramp (38;5;N), truecolor from a hex config
# (38;2;r;g;b), and the plain codes the default palette uses (0;36). The last is the trap... its leading "0;" resets
# attributes, so a color written after a background wipes the background. That is why this exists, and why the segment order below is what it is.
bg_of=""
to_bg() {  # <fg escape> -> sets bg_of
  case "$1" in
    *'[38;5;'*) bg_of=${1/38;5;/48;5;} ;;
    *'[38;2;'*) bg_of=${1/38;2;/48;2;} ;;
    *'[0;3'*)   bg_of=$'\033['"4${1#*\[0;3}" ;;
    *'[3'*)     bg_of=$'\033['"4${1#*\[3}" ;;
    *)          bg_of="" ;;
  esac
}

bar=""
make_bar() {  # <pct> <label> <color> [pace_col] [pace_color] [points_on] [lead] [next_bg]
  local pct=$1 label=$2 color=$3 pace_col=${4:-} pace_color=${5:-} points_on=${6:-}
  local lead=${7:-} next_bg=${8:-}
  local w=$bar_width content pad i ch seg out full rem eighths fill_bg

  to_bg "$color"
  fill_bg=$bg_of

  # The empty track is a dark tint of the bar's own color, not neutral grey, so a bar reads as one colored object end
  # to end rather than a grey rail with color at one end. The caps follow it, so the outline is the same hue.
  local track_bg=$bar_track_bg track_fg=$bar_track_fg
  if [ "$bar_track" = "tint" ] && [ -n "$bar_track_bg" ]; then
    tint "$color" "$bar_track_tint"
    if [ -n "$tinted" ]; then
      track_bg=$'\033[48;2;'"$tinted"'m'
      track_fg=$'\033[38;2;'"$tinted"'m'
    fi
  fi

  # The pace marker sits back from the bar, a tint nearer the track than the fill, so it's there when looked for and
  # quiet otherwise. PACE_MARKER_TINT=100 is the old full-strength line.
  local pace_fg=$pace_color
  if [ -n "$pace_color" ] && [ "$pace_marker_tint" -lt 100 ]; then
    tint "$pace_color" "$pace_marker_tint"
    [ -n "$tinted" ] && pace_fg=$'\033[38;2;'"$tinted"'m'
  fi

  [ "$pct" -lt 0 ] && pct=0
  [ "$pct" -gt 100 ] && pct=100

  # The lead glyph takes the meter's first cell, not a socket beside it, and wears the bar's own coloring: knocked out
  # on the fill, meter-colored on the track, same as the digits.
  #
  # That's the whole trick for legibility. A mark with its own color has to survive both a bright fill and a dark
  # track, and no color does. Borrowing the digits' treatment inherits contrast already measured.
  #
  # Label right-aligned with a cell of air at the edge. Kept ASCII while indexed... lead and superscripts are
  # substituted per cell on the way out.
  pad=$(( w - ${#label} - 1 ))
  [ "$pad" -lt 0 ] && pad=0
  printf -v content '%*s%s ' "$pad" '' "$label"
  content=${content:0:$w}
  while [ ${#content} -lt "$w" ]; do content="$content "; done

  eighths=$(( pct * w * 8 / 100 ))
  full=$(( eighths / 8 ))
  rem=$(( eighths % 8 ))
  [ "$full" -gt "$w" ] && full=$w

  out=""
  i=0
  while [ "$i" -lt "$w" ]; do
    ch=${content:$i:1}
    [ "$i" -eq 0 ] && [ -n "$lead" ] && ch="$lead"
    if [ "$bar_style" = "solid" ] && [ -n "$color" ]; then
      # Color first, background second, always... a plain "0;3x" color resets whatever background preceded it.
      if [ "$i" -lt "$full" ]; then
        seg="${bar_knockout}${fill_bg}"
      elif [ "$i" -eq "$full" ] && [ "$rem" -gt 0 ] && [ "$ch" = " " ]; then
        seg="${color}${track_bg}"
        ch=${BAR_PARTIALS[$((rem - 1))]}
      elif [ "$i" -eq "$full" ] && [ "$rem" -ge 4 ]; then
        # A lead glyph or digit already holds the boundary cell, so there's nowhere to draw the eighth-block. Round to
        # nearest: past halfway the cell reads filled. Without it a lead glyph swallows any fill under one cell, and a
        # bar at 6% looked identical to 0%.
        seg="${bar_knockout}${fill_bg}"
      else
        seg="${color}${track_bg}"
      fi
    else
      seg="$color"
      if [ "$ch" = " " ]; then
        if [ "$i" -lt "$full" ]; then ch="▓"; else ch="░"; fi
      fi
    fi
    # The pace marker only ever replaces blank track, never a digit.
    if [ -n "$pace_col" ] && [ "$i" -eq "$pace_col" ] && [ "$ch" = " " ]; then
      ch="┃"
      seg="${seg}${pace_fg}"
    fi
    # Superscript digits, so the number sits small inside the bar instead of competing with it. No percent sign
    # either... a number in a meter already is one.
    case "$ch" in [0-9]) [ -n "$bar_digit_glyphs" ] && ch=${bar_digit_glyphs:$ch:1} ;; esac
    out="${out}${seg}${ch}"
    i=$((i + 1))
  done
  if [ -n "$bar_cap_l" ]; then
    # Each cap takes the color of the background it butts against, so the end reads as part of the bar. A bar with
    # something after it closes on an arrow, and that arrow is the pointing... which is why the element
    # carries no literal " -> " before its time.
    local cap_l_fg=$track_fg cap_r_fg=$track_fg cap_r=$bar_cap_r
    # The left cap abuts cell 0's left edge, and an eighth-block fills from that edge, so any fill at all colors it.
    # Testing full alone left the cap dark against a colored first cell on every bar under 1/14th.
    { [ "$full" -gt 0 ] || [ "$rem" -gt 0 ]; } && cap_l_fg=$color
    # The right cap abuts the last cell's right edge, which a partial block never reaches. Only a full bar colors it.
    [ "$full" -ge "$w" ] && cap_r_fg=$color
    [ -n "$points_on" ] && cap_r=$bar_cap_arrow
    if [ -n "$next_bg" ]; then
      # Powerline ribbon handoff: the arrow is drawn in the color of the edge it leaves, over the background of the
      # segment it enters. That's what makes two segments share an edge. No RESET after it... the caller keeps writing
      # on that background, and a reset punches a hole in the join.
      bar="${RESET}${cap_l_fg}${bar_cap_l}${out}${RESET}${cap_r_fg}${next_bg}${bar_cap_arrow}"
    else
      bar="${RESET}${cap_l_fg}${bar_cap_l}${out}${RESET}${cap_r_fg}${cap_r}${RESET}"
    fi
  else
    bar="${out}${RESET}"
  fi
}
reset_epoch_of() {  # resets_at -> epoch seconds, or empty if it isn't one
  case "$1" in
    ''|*[!0-9]*) return ;;
    *)           printf '%s' "$1" ;;
  esac
}

# Which account is signed in, the thing worth watching when you swap. Claude Code keeps it in ~/.claude.json under
# oauthAccount, rewritten on every profile fetch. One sed pass costs ~6ms and can never lag a swap... a cache showing
# the account you just left is the exact failure this prevents.
#
# PROFILE_NAME overrides. PROFILE_STYLE picks what the label says:
#
#   name       displayName, or the email local-part if it is unset  (default)
#   email      the email local-part
#   plan       the subscription: MAX20, PRO, TEAM, ENT, FREE
#   name+plan  both, space separated
claude_json="$HOME/.claude.json"

acct_name=""
acct_email=""
acct_type=""
acct_tier=""
if [ -f "$claude_json" ]; then
  # One pass, four keys, one match per line whatever the file's layout. Claude Code pretty-prints it, one key per line,
  # but a compact one-line file has to parse the same: a single sed with four substitutions did not, since the first one
  # rewrote the whole line and the other three never matched.
  while IFS= read -r acct_line; do
    acct_val=${acct_line#*:}      # what follows the colon
    acct_val=${acct_val#*\"}      # through the opening quote
    acct_val=${acct_val%\"}       # and the closing one
    case "$acct_line" in
      '"displayName"'*)               [ -n "$acct_name" ]  || acct_name=$acct_val ;;
      '"emailAddress"'*)              [ -n "$acct_email" ] || acct_email=$acct_val ;;
      '"organizationType"'*)          [ -n "$acct_type" ]  || acct_type=$acct_val ;;
      '"organizationRateLimitTier"'*) [ -n "$acct_tier" ]  || acct_tier=$acct_val ;;
    esac
  done <<EOF
$(grep -oE '"(displayName|emailAddress|organizationType|organizationRateLimitTier)": *"[^"]*"' "$claude_json" 2>/dev/null)
EOF
fi

# organizationType is claude_max / claude_pro / claude_team / claude_enterprise. Matched loosely so a renamed or unseen
# tier lands somewhere sensible instead of blanking the label.
plan_label() {
  [ -n "$acct_type" ] || return 0
  local base mult
  case "$acct_type" in
    *enterprise*) base="ENT" ;;
    *team*)       base="TEAM" ;;
    *max*)        base="MAX" ;;
    *pro*)        base="PRO" ;;
    *free*)       base="FREE" ;;
    *)            base=$(printf '%s' "${acct_type#claude_}" | tr '[:lower:]' '[:upper:]') ;;
  esac
  # default_claude_max_20x -> MAX20. A tier with no multiplier just drops it.
  mult=$(printf '%s' "$acct_tier" | sed -n 's/.*_\([0-9][0-9]*\)x$/\1/p')
  printf '%s%s' "$base" "$mult"
}

# The same tiers as a glyph. Worth its own mark, not a repeat of the label: the default style prints only the name, so
# the tier is otherwise not on screen. Text says who, icon says what kind.
plan_icon() {
  case "$acct_type" in
    *enterprise*) printf '%s' "$profile_icon_enterprise" ;;
    *team*)       printf '%s' "$profile_icon_team" ;;
    *max*)        printf '%s' "$profile_icon_max" ;;
    *pro*)        printf '%s' "$profile_icon_pro" ;;
    *free*)       printf '%s' "$profile_icon_free" ;;
    # An API-key account has no oauthAccount, so acct_type is empty and this lands on the neutral outline.
    *)            printf '%s' "$profile_icon_default" ;;
  esac
}

if [ -z "${profile_name:-}" ]; then
  case "${profile_style:-name}" in
    plan)
      profile_name=$(plan_label) ;;
    email)
      profile_name="${acct_email%%@*}" ;;
    name+plan)
      profile_name="${acct_name:-${acct_email%%@*}}"
      profile_plan=$(plan_label)
      [ -n "$profile_plan" ] && profile_name="${profile_name:+$profile_name }$profile_plan" ;;
    *)
      profile_name="${acct_name:-${acct_email%%@*}}" ;;
  esac
fi

# An API-key account never gets rate_limits on stdin, so the usage sections would sit on a permanent "~". No
# oauthAccount means exactly that.
account_is_subscription=0
[ -n "$acct_type" ] && account_is_subscription=1

input=$(cat)

# Everything needed out of the payload, in one grep.
#
# Each $( ) is a fork, ~2ms on macOS, so the nine echo|grep|sed pipelines this replaces cost ~8ms EACH, more than the
# whole rest of the render. One pass, then bash-only expansion to pick fields apart... a $(helper) would fork again.
#
# Windows come through whole ("five_hour":{...}) and get split below. No nested braces, so [^}]* bounds them.
payload_transcript=""
payload_project_dir=""
payload_current_dir=""
payload_model=""
payload_model_id=""
payload_worktree=""
payload_effort=""
payload_input_tokens=""
payload_cache_create=""
payload_cache_read=""
payload_ctx_size=""
payload_five_hour=""
payload_seven_day=""
payload_spend_limit=""
payload_cost=""
payload_cache_warm=""
payload_cache_observed=""
payload_cache_ttl=""
payload_cache_expires=""
payload_pr=""
payload_session=""
payload_columns=""
payload_is_subagent=0

while IFS= read -r pf; do
  case "$pf" in
    '"transcript_path":"'*) [ -n "$payload_transcript" ] || { pf=${pf#*:\"}; payload_transcript=${pf%\"}; } ;;
    '"project_dir":"'*)   [ -n "$payload_project_dir" ] || { pf=${pf#*:\"}; payload_project_dir=${pf%\"}; } ;;
    '"current_dir":"'*)   [ -n "$payload_current_dir" ] || { pf=${pf#*:\"}; payload_current_dir=${pf%\"}; } ;;
    '"display_name":"'*)  [ -n "$payload_model" ]       || { pf=${pf#*:\"}; payload_model=${pf%\"}; } ;;
    '"id":"'*)            [ -n "$payload_model_id" ]    || { pf=${pf#*:\"}; payload_model_id=${pf%\"}; } ;;
    '"worktree":'*)       [ -n "$payload_worktree" ]    || { pf=${pf##*:\"}; payload_worktree=${pf%\"}; } ;;
    '"effort":'*)         [ -n "$payload_effort" ]      || { pf=${pf##*:\"}; payload_effort=${pf%\"}; } ;;
    '"input_tokens":'*)               [ -n "$payload_input_tokens" ] || payload_input_tokens=${pf##*:} ;;
    '"cache_creation_input_tokens":'*) payload_cache_create=${pf##*:} ;;
    '"cache_read_input_tokens":'*)     payload_cache_read=${pf##*:} ;;
    '"context_window_size":'*)         payload_ctx_size=${pf##*:} ;;
    '"five_hour":'*)      payload_five_hour=$pf ;;
    '"seven_day":'*)      payload_seven_day=$pf ;;
    '"spend_limit":'*)    payload_spend_limit=$pf ;;
    '"total_cost_usd":'*) payload_cost=${pf##*:} ;;
    '"warm":'*)             payload_cache_warm=${pf##*:} ;;
    '"caching_observed":'*) payload_cache_observed=${pf##*:} ;;
    '"ttl":"'*)             pf=${pf#*:\"}; payload_cache_ttl=${pf%\"} ;;
    '"expires_at":'*)       payload_cache_expires=${pf##*:} ;;
    '"pr":'*)               payload_pr=$pf ;;
    '"session_id":"'*)      [ -n "$payload_session" ] || { pf=${pf#*:\"}; payload_session=${pf%\"}; } ;;
    '"columns":'*)          payload_columns=${pf##*:} ;;
    '"tasks":['*)           payload_is_subagent=1 ;;
  esac
done <<EOF
$(printf '%s' "$input" | grep -oE '"(current_dir|display_name|id|transcript_path|project_dir)":"[^"]*"|"worktree":\{"name":"[^"]*"|"effort":\{"level":"[^"]*"|"(input_tokens|cache_creation_input_tokens|cache_read_input_tokens|context_window_size)":[0-9]+|"total_cost_usd":[0-9.]+|"(warm|caching_observed)":(true|false)|"ttl":"[^"]*"|"expires_at":(null|[0-9]+)|"(five_hour|seven_day|spend_limit|pr)":\{[^}]*\}|"session_id":"[^"]*"|"columns":[0-9]+|"tasks":\[')
EOF

current_dir_path="$payload_current_dir"
current_dir=${current_dir_path##*/}
model="$payload_model"

# Claude Code puts the limits it already knows about in the payload:
#
#   "rate_limits":{"five_hour":{"used_percentage":14.0,"resets_at":1788642000},
#                  "seven_day":{"used_percentage":6,"resets_at":1789088400}}
#
# The same figures a third-party fetcher spends a round trip on, free and never stale. Neither key shows up on an
# API-key account or before a session's first response, so an empty read is normal... the bars just stay absent.
#
# used_percentage is a float (14.000000000000002) and every comparison downstream is an integer test, so round on the
# way in. resets_at is already epoch seconds.
# Both assign to a global rather than printing: $(fn) forks a subshell even when the body is pure bash.
rl_num=""
rl_field() {  # <window blob> <field> -> sets rl_num
  rl_num=""
  case "$1" in
    *"\"$2\":"*) ;;
    *) return ;;
  esac
  local v=${1#*\"$2\":}
  v=${v%%,*}
  rl_num=${v%\}}
}

rl_int=""
rl_pct() {  # <window blob> -> sets rl_int to used_percentage, rounded
  rl_int=""
  rl_field "$1" used_percentage
  [ -n "$rl_num" ] || return
  # Round half up on the first decimal. printf '%.0f' does it, but only inside $( ), and that fork is the thing being
  # dodged.
  local int=${rl_num%%.*} frac=${rl_num#*.}
  [ "$frac" = "$rl_num" ] && frac=""
  [ -n "$int" ] || int=0
  case "$int" in
    ''|*[!0-9]*) return ;;
  esac
  case "$frac" in
    [5-9]*) int=$((int + 1)) ;;
  esac
  rl_int=$int
}
rl_pct   "$payload_five_hour";   rl_session_pct=$rl_int
rl_field "$payload_five_hour" resets_at; rl_session_reset=$rl_num
rl_pct   "$payload_seven_day";   rl_weekly_pct=$rl_int
rl_field "$payload_seven_day" resets_at; rl_weekly_reset=$rl_num

# Hide the usage sections rather than park them on a permanent "~", but only for an account that can never report
# limits. A subscription still waiting on its first response shows "~", which is honest and clears itself.
if [ "$account_is_subscription" = "0" ] && [ -z "$rl_session_pct" ] && [ -z "$rl_weekly_pct" ]; then
  show_usage=0
  show_weekly=0
  show_extra_usage=0
fi

# Hex to ANSI. Sets $ansi rather than printing... the body is pure bash but $(hex_to_ansi) forks anyway, and this
# runs 13 times a render.
ansi=""
hex_to_ansi() {
  local hex=${1#\#}
  printf -v ansi '\033[38;2;%d;%d;%dm' \
    "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
}

# Set colors based on mode
RESET=$'\033[0m'

if [ "$color_mode" = "monochrome" ]; then
  # Monochrome mode - no colors
  BLUE=""
  GREEN=""
  GRAY=""
  YELLOW=""
  CYAN=""
  MAGENTA=""
  TEAL=""
  LEVEL_1=""
  LEVEL_2=""
  LEVEL_3=""
  LEVEL_4=""
  LEVEL_5=""
  LEVEL_6=""
  LEVEL_7=""
  LEVEL_8=""
  LEVEL_9=""
  LEVEL_10=""
  PACE_COMFORTABLE=""
  PACE_ON_TRACK=""
  PACE_WARMING=""
  PACE_PRESSING=""
  PACE_CRITICAL=""
  PACE_RUNAWAY=""
elif [ "$color_mode" = "singleColor" ]; then
  # Single color mode - use user's chosen color for everything
  hex_to_ansi "$single_color"; single_ansi=$ansi
  BLUE=$single_ansi
  GREEN=$single_ansi
  GRAY=$single_ansi
  YELLOW=$single_ansi
  CYAN=$single_ansi
  MAGENTA=$single_ansi
  TEAL=$single_ansi
  LEVEL_1=$single_ansi
  LEVEL_2=$single_ansi
  LEVEL_3=$single_ansi
  LEVEL_4=$single_ansi
  LEVEL_5=$single_ansi
  LEVEL_6=$single_ansi
  LEVEL_7=$single_ansi
  LEVEL_8=$single_ansi
  LEVEL_9=$single_ansi
  LEVEL_10=$single_ansi
  PACE_COMFORTABLE=$single_ansi
  PACE_ON_TRACK=$single_ansi
  PACE_WARMING=$single_ansi
  PACE_PRESSING=$single_ansi
  PACE_CRITICAL=$single_ansi
  PACE_RUNAWAY=$single_ansi
elif [ "$color_mode" = "perElement" ]; then
  # Per-element mode - each element uses its own user-defined color
  hex_to_ansi "$element_color_dir"; BLUE=$ansi
  hex_to_ansi "$element_color_branch"; GREEN=$ansi
  hex_to_ansi "$element_color_model"; YELLOW=$ansi
  hex_to_ansi "$element_color_profile"; MAGENTA=$ansi
  hex_to_ansi "$element_color_context"; CYAN=$ansi
  hex_to_ansi "$element_color_separator"; GRAY=$ansi
  if [ -n "$element_color_worktree" ]; then
    hex_to_ansi "$element_color_worktree"; TEAL=$ansi
  else
    TEAL=$'\033[38;2;38;166;154m'           # teal 400, worktree
  fi

  # Usage gradient: override all levels if a base color is set, else use standard gradient
  if [ -n "$element_color_usage" ]; then
    hex_to_ansi "$element_color_usage"; usage_override=$ansi
    LEVEL_1=$usage_override
    LEVEL_2=$usage_override
    LEVEL_3=$usage_override
    LEVEL_4=$usage_override
    LEVEL_5=$usage_override
    LEVEL_6=$usage_override
    LEVEL_7=$usage_override
    LEVEL_8=$usage_override
    LEVEL_9=$usage_override
    LEVEL_10=$usage_override
  else
    LEVEL_1=$'\033[38;2;102;187;106m'
    LEVEL_2=$'\033[38;2;129;199;132m'
    LEVEL_3=$'\033[38;2;156;204;101m'
    LEVEL_4=$'\033[38;2;212;225;87m'
    LEVEL_5=$'\033[38;2;253;216;53m'
    LEVEL_6=$'\033[38;2;255;202;40m'
    LEVEL_7=$'\033[38;2;255;183;77m'
    LEVEL_8=$'\033[38;2;255;167;38m'
    LEVEL_9=$'\033[38;2;255;138;101m'
    LEVEL_10=$'\033[38;2;239;83;80m'
  fi

  # Pace colors: override all tiers if a base color is set, else use standard 6-tier
  if [ -n "$element_color_pace" ]; then
    hex_to_ansi "$element_color_pace"; pace_override=$ansi
    PACE_COMFORTABLE=$pace_override
    PACE_ON_TRACK=$pace_override
    PACE_WARMING=$pace_override
    PACE_PRESSING=$pace_override
    PACE_CRITICAL=$pace_override
    PACE_RUNAWAY=$pace_override
  else
    PACE_COMFORTABLE=$'\033[38;5;34m'
    PACE_ON_TRACK=$'\033[38;5;37m'
    PACE_WARMING=$'\033[38;5;178m'
    PACE_PRESSING=$'\033[38;5;208m'
    PACE_CRITICAL=$'\033[38;5;160m'
    PACE_RUNAWAY=$'\033[38;5;135m'
  fi
else
  # Colored mode (default) - use full color palette
  BLUE=$'\033[38;2;66;165;245m'           # blue 400, folder
  GREEN=$'\033[38;2;102;187;106m'          # green 400, branch
  GRAY=$'\033[38;5;240m'  # faded, the separator is the only user
  YELLOW=$'\033[38;2;255;202;40m'           # amber 400, status + context mid
  CYAN=$'\033[38;2;38;198;218m'           # cyan 400, context low
  MAGENTA=$'\033[38;2;171;71;188m'           # purple 400, account
  TEAL=$'\033[38;2;38;166;154m'           # teal 400, worktree   # worktree, distinct from branch green

  # 10-level gradient, Material 300-600. These are bar BACKGROUNDS now, label knocked out in BAR_TEXT_COLOR, so they
  # have to carry dark text. The old 256-color ramp was picked when they were foregrounds: dark green scored 2.1x
  # contrast and deep red 2.3x against a 4.5x threshold, which is why both ends were unreadable. Every level here clears
  # 4.5x on the fill.
  LEVEL_1=$'\033[38;2;102;187;106m'          # green 400
  LEVEL_2=$'\033[38;2;129;199;132m'          # green 300
  LEVEL_3=$'\033[38;2;156;204;101m'          # light green 400
  LEVEL_4=$'\033[38;2;212;225;87m'           # lime 500
  LEVEL_5=$'\033[38;2;253;216;53m'           # yellow 600
  LEVEL_6=$'\033[38;2;255;202;40m'           # amber 400
  LEVEL_7=$'\033[38;2;255;183;77m'           # orange 300
  LEVEL_8=$'\033[38;2;255;167;38m'           # orange 400
  LEVEL_9=$'\033[38;2;255;138;101m'          # deep orange 300
  LEVEL_10=$'\033[38;2;239;83;80m'            # red 400

  # 6-tier pace marker colors
  PACE_COMFORTABLE=$'\033[38;2;102;187;106m'          # green
  PACE_ON_TRACK=$'\033[38;2;77;208;225m'           # cyan
  PACE_WARMING=$'\033[38;2;255;202;40m'           # amber
  PACE_PRESSING=$'\033[38;2;255;167;38m'           # orange
  PACE_CRITICAL=$'\033[38;2;239;83;80m'            # red
  PACE_RUNAWAY=$'\033[38;2;186;104;200m'          # purple
fi

# With pace step colors on, the 6 tiers beat even a per-element override (not in monochrome). Truecolor so
# PACE_MARKER_TINT can shade them... the 256-color codes these used to be can't be tinted.
if [ "$pace_marker_step_colors" != "0" ] && [ "$color_mode" != "monochrome" ]; then
  PACE_COMFORTABLE=$'\033[38;2;102;187;106m'   # green
  PACE_ON_TRACK=$'\033[38;2;77;208;225m'      # cyan
  PACE_WARMING=$'\033[38;2;255;202;40m'       # amber
  PACE_PRESSING=$'\033[38;2;255;167;38m'      # orange
  PACE_CRITICAL=$'\033[38;2;239;83;80m'       # red
  PACE_RUNAWAY=$'\033[38;2;186;104;200m'      # purple
fi

# The ten-step ramp every gauge shares. The three older ones still spell it out inline... this exists so the budget bar
# didn't become a fourth copy.
level=""
level_color() {  # <pct> -> level
  if   [ "$1" -le 10 ]; then level="$LEVEL_1"
  elif [ "$1" -le 20 ]; then level="$LEVEL_2"
  elif [ "$1" -le 30 ]; then level="$LEVEL_3"
  elif [ "$1" -le 40 ]; then level="$LEVEL_4"
  elif [ "$1" -le 50 ]; then level="$LEVEL_5"
  elif [ "$1" -le 60 ]; then level="$LEVEL_6"
  elif [ "$1" -le 70 ]; then level="$LEVEL_7"
  elif [ "$1" -le 80 ]; then level="$LEVEL_8"
  elif [ "$1" -le 90 ]; then level="$LEVEL_9"
  else                       level="$LEVEL_10"
  fi
}

# The track a bar sits in, and the color the label is knocked out in over the fill. Derived once. Monochrome leaves
# them empty and make_bar falls back to blocks.
bar_track_bg=""
bar_track_fg=""
bar_knockout=""
if [ "$bar_style" = "solid" ] && [ "$color_mode" != "monochrome" ]; then
  hex_to_ansi "$bar_track_color"; bar_track_fg=$ansi; to_bg "$ansi"; bar_track_bg=$bg_of
  hex_to_ansi "$bar_text_color";  bar_knockout=$ansi
fi

# End caps, the powerline ribbon trick: a half-glyph in the color of the cell it abuts, on the terminal background, so
# the bar reads as a pill instead of a rectangle.
#
#   powerline  U+E0B6 / U+E0B4, rounded. Needs a Nerd Font, which the rest of the line assumes anyway.
#   half       ▐ / ▌, plain Unicode half blocks. Squarer, any font.
#   none       hard edges.
#
# Caps sit outside BAR_WIDTH, solid style only... with no background behind them there is nothing to cap.

# Effort's own color, not the family's and not the meter's. The family color is an identity, not a quantity, and Opus
# purple is too dark to read as lit. The meter's is worse: two quantities in one capsule reads as more bar.
#
# So a dark blue-grey pill, bright blue fill. The dark base is what lets the lit half look lit. The unlit half is
# lighter than the track, not darker... at #242424 it sat a hair off the terminal background and vanished.
effort_pill_bg=""
effort_pill_fg=""
effort_dim_fg=""
if [ -n "$bar_track_bg" ]; then
  hex_to_ansi "$effort_pill_color"; effort_pill_fg="$ansi"; to_bg "$ansi"; effort_pill_bg="$bg_of"
  hex_to_ansi "$effort_dim_color";  effort_dim_fg="$ansi"
fi

bar_cap_l=""
bar_cap_r=""
bar_cap_arrow=""
bar_cap_thin=""   # the arrow's outline, for an effort chevron that is not lit
if [ -n "$bar_track_bg" ]; then
  case "$bar_caps" in
    # Literal glyphs, not $'\ue0b6'. bash 3.2 has no \u escape (4.2 added it) and passes the six characters through,
    # which is what shipped once.
    powerline) bar_cap_l=""; bar_cap_r=""; bar_cap_arrow=""; bar_cap_thin="" ;;
    half)      bar_cap_l="▐";        bar_cap_r="▌";        bar_cap_arrow="▸"; bar_cap_thin="›" ;;
  esac
fi

# The effort run, for the main line and every agent row. Sets effort_ramp (cells after the meter's cap), effort_join_bg
# (what the cap hands off to), effort_cap_fg and effort_close_glyph (empty when the run closes itself). Color follows
# EFFORT_LIT_COLOR, where "context" means whatever context_color is at call time.
build_effort() {  # <level>
  # A lit run, not one shape. Effort is a multiplier over the model and the context, not a category, so it wants a
  # scale: lit to the level, dark past it, in the meter's color.
  effort_ramp=""
  effort_join_bg=""
  effort_cap_fg=""
  effort_close_glyph=""
  if [ "$show_effort" = "1" ] && [ "$model_style" = "glyph" ]; then
    case "$1" in
      low)    effort_lit=1 ;;
      medium) effort_lit=2 ;;
      high)   effort_lit=3 ;;
      xhigh)  effort_lit=4 ;;
      max)    effort_lit=5 ;;
      *)      effort_lit=0 ;;
    esac
    if [ "$effort_lit" -gt 0 ]; then
      # What lit means. Default is the meter's color, so the run reads as the meter's multiplier... one hue, shifting
      # cyan to red together as context climbs.
      case "$effort_lit_color" in
        context|"") effort_lit_fg="${context_color:-$CYAN}" ;;
        family)     effort_lit_fg="$model_color" ;;
        *)          hex_to_ansi "$effort_lit_color"; effort_lit_fg="$ansi" ;;
      esac
    fi

    if [ "$effort_lit" -gt 0 ] && [ "$effort_style" = "chevrons" ] && [ -n "$bar_cap_arrow" ] \
       && [ -n "$bar_cap_thin" ] && [ "$bar_style" = "solid" ] && [ "$color_mode" != "monochrome" ]; then
      # The meter's arrow cap five times over, one per level. Lit ones are solid bands fading outward, so the run reads
      # as momentum. Unlit ones are the arrow's outline in a dim tint, so five stay countable. Dark solid bands were
      # tried... two adjacent share a color, the arrow between them vanishes, the run goes to one block.
      #
      # Powerline handoff again: each arrow drawn in the band it leaves over the band it enters. The meter's cap is the
      # first arrow, so the bands grow out of the bar.
      effort_i=1
      effort_prev_fg=""
      while [ "$effort_i" -le "$effort_lit" ]; do
        effort_pct=$(( 100 - (100 - effort_chevron_fade) * (effort_i - 1) / 4 ))
        tint "$effort_lit_fg" "$effort_pct"
        if [ -n "$tinted" ]; then
          effort_band_fg=$'\033[38;2;'"$tinted"'m'
          effort_band_bg=$'\033[48;2;'"$tinted"'m'
        else
          # Not a truecolor base, so no shades: every lit band is the color.
          effort_band_fg="$effort_lit_fg"; to_bg "$effort_lit_fg"; effort_band_bg="$bg_of"
        fi
        if [ "$effort_i" -eq 1 ]; then
          effort_join_bg="$effort_band_bg"
        else
          effort_ramp="${effort_ramp}${effort_prev_fg}${effort_band_bg}${bar_cap_arrow}"
        fi
        effort_prev_fg="$effort_band_fg"
        effort_i=$((effort_i + 1))
      done
      effort_ramp="${effort_ramp}${RESET}${effort_prev_fg}${bar_cap_arrow}"
      tint "$effort_lit_fg" "$effort_chevron_dim"
      if [ -n "$tinted" ]; then
        effort_dim_now=$'\033[38;2;'"$tinted"'m'
      else
        effort_dim_now="$bar_track_fg"
      fi
      while [ "$effort_i" -le 5 ]; do
        effort_ramp="${effort_ramp}${RESET}${effort_dim_now}${bar_cap_thin}"
        effort_i=$((effort_i + 1))
      done
      # The run closes itself, so the context block draws no cap and appends a bare RESET.
      effort_cap_fg=""
      effort_close_glyph=""
    elif [ "$effort_lit" -gt 0 ]; then
      # The pill: EFFORT_STYLE=pill, and the fallback with no arrow or background to hand off. Four steps in a capsule,
      # the closing hemisphere the fifth.
      #
      # Pill and unlit steps are darker tints of the same color, so meter and pill are one hue at three intensities:
      # fill, track, pill. Black underneath read as a hole beside a bright bar.
      effort_pill_bg_now="$effort_pill_bg"
      effort_dim_fg_now="$effort_dim_fg"
      if [ "$bar_track" = "tint" ] && [ -n "$effort_pill_bg" ]; then
        tint "$effort_lit_fg" "$effort_pill_tint"
        [ -n "$tinted" ] && effort_pill_bg_now=$'\033[48;2;'"$tinted"'m'
        tint "$effort_lit_fg" "$effort_dim_tint"
        [ -n "$tinted" ] && effort_dim_fg_now=$'\033[38;2;'"$tinted"'m'
      fi

      # Space separated so splitting never has to index into a multibyte glyph.
      read -ra effort_steps <<< "$effort_ramp_glyphs"
      effort_total=${#effort_steps[@]}
      effort_i=0
      # The closing hemisphere is the fifth step. It lights only past the four, so max fills the pill's end.
      effort_cap_lit=0
      [ "$effort_lit" -gt "$effort_total" ] && effort_cap_lit=1
      while [ "$effort_i" -lt "$effort_total" ]; do
        if [ "$effort_i" -lt "$effort_lit" ]; then
          effort_ramp="${effort_ramp}${effort_lit_fg}${effort_pill_bg_now}${effort_steps[$effort_i]}"
        elif [ "$color_mode" = "monochrome" ]; then
          effort_ramp="${effort_ramp} "
        else
          effort_ramp="${effort_ramp}${effort_dim_fg_now}${effort_pill_bg_now}${effort_steps[$effort_i]}"
        fi
        effort_i=$((effort_i + 1))
      done
      effort_join_bg="$effort_pill_bg_now"
      if [ "$effort_cap_lit" = "1" ]; then
        effort_cap_fg="$effort_lit_fg"
      else
        effort_cap_fg="$effort_dim_fg_now"
      fi
      effort_close_glyph="$bar_cap_r"
    fi
  fi

}

# ---- The agent panel: one row per running subagent ----
#
# Under subagentStatusLine Claude Code sends one JSON object: "columns" for the usable width and a "tasks" array of id,
# name, status, description, model, effort, tokenCount, contextWindowSize. It takes back one JSON line per row, drawn in
# place of the default "name · description · tokens".
#
# Same script, same glyphs: family shape leads a short meter, the effort run grows out of the cap, then the name and
# whatever description fits.
jsoned=""
json_escape() {  # <string> -> jsoned
  local j=$1
  j=${j//\\/\\\\}; j=${j//\"/\\\"}; j=${j//$'\033'/\\u001b}; j=${j//$'\a'/\\u0007}; j=${j//$'\n'/\\n}; j=${j//$'\t'/\\t}
  jsoned=$j
}
if [ "$payload_is_subagent" = 1 ]; then
  sa_cols=${payload_columns:-80}
  case "$sa_cols" in ''|*[!0-9]*) sa_cols=80 ;; esac
  sa_id=""; sa_name=""; sa_status=""; sa_desc=""; sa_model=""; sa_effort=""; sa_ctx=""; sa_tokens=""
  # Bar, both caps, the five chevrons and the closing arrow. Rows are emitted as they are parsed, so this cannot be
  # the measured maximum... it is the width a full row takes.
  sa_lead_width=$(( subagent_bar_width + 8 ))
  sa_pad="                    "
  sa_emit() {
    local pct=0 color lead="" avail text row
    if [ -n "$sa_ctx" ] && [ "$sa_ctx" -gt 0 ] && [ -n "$sa_tokens" ]; then
      pct=$(( sa_tokens * 100 / sa_ctx )); [ "$pct" -gt 100 ] && pct=100
    fi
    if [ "$pct" -le 25 ]; then color="$CYAN"; elif [ "$pct" -le 34 ]; then color="$YELLOW"
    elif [ "$pct" -le 44 ]; then color="$LEVEL_8"; else color="$LEVEL_10"; fi
    case "$sa_model" in
      *mythos*) lead="$model_mark_mythos" ;;
      *opus*)   lead="$model_mark_opus" ;;
      *fable*)  lead="$model_mark_fable" ;;
      *sonnet*) lead="$model_mark_sonnet" ;;
      *haiku*)  lead="$model_mark_haiku" ;;
    esac
    context_color="$color"; model_color="$color"
    build_effort "$sa_effort"
    bar_width=$subagent_bar_width
    if [ -n "$effort_ramp" ] && [ -n "$effort_join_bg" ] && [ -n "$bar_cap_arrow" ]; then
      make_bar "$pct" "$pct" "$color" "" "" "$effort_ramp" "$lead" "$effort_join_bg"
      row="${bar}${effort_ramp}${RESET}${effort_cap_fg}${effort_close_glyph}${RESET}"
    else
      make_bar "$pct" "$pct" "$color" "" "" "" "$lead" ""
      row="${bar}${effort_ramp}${RESET}"
    fi
    plain_width "$row"
    # Names only line up if what precedes them is a constant width. The effort run is six cells on a model that has an
    # effort dial and nothing at all on one that does not, so a Haiku row otherwise pulls its name six columns left of
    # the rest and the panel reads as ragged. Pad, never truncate.
    if [ "$pw" -lt "$sa_lead_width" ]; then
      row="${row}${sa_pad:0:$(( sa_lead_width - pw ))}"
      pw=$sa_lead_width
    fi
    avail=$(( sa_cols - pw - ${#sa_name} - 4 ))
    text=$sa_desc
    if [ "$avail" -gt 1 ] && [ ${#text} -gt "$avail" ]; then text="${text:0:$((avail - 1))}…"; fi
    [ "$avail" -gt 1 ] || text=""
    row="${row}  ${sa_name}${text:+  ${GRAY}${text}${RESET}}"
    json_escape "$row"
    printf '{"id":"%s","content":"%s"}\n' "$sa_id" "$jsoned"
  }
  # Per-task fields arrive in document order, and a task starts at its "id".
  while IFS= read -r sf; do
    case "$sf" in
      '"id":"'*)          [ -n "$sa_id" ] && sa_emit
                          sf=${sf#*:\"}; sa_id=${sf%\"}
                          sa_name=""; sa_status=""; sa_desc=""; sa_model=""; sa_effort=""; sa_ctx=""; sa_tokens="" ;;
      '"name":"'*)        sf=${sf#*:\"}; sa_name=${sf%\"} ;;
      '"status":"'*)      sf=${sf#*:\"}; sa_status=${sf%\"} ;;
      '"description":"'*) sf=${sf#*:\"}; sa_desc=${sf%\"} ;;
      '"model":"'*)       sf=${sf#*:\"}; sa_model=${sf%\"} ;;
      '"effort":"'*)      sf=${sf#*:\"}; sa_effort=${sf%\"} ;;
      '"contextWindowSize":'*) sa_ctx=${sf##*:} ;;
      '"tokenCount":'*)   sa_tokens=${sf##*:} ;;
    esac
  done <<EOF
$(printf '%s' "$input" | grep -oE '"(id|name|status|description|model|effort)":"[^"]*"|"(contextWindowSize|tokenCount)":[0-9]+')
EOF
  [ -n "$sa_id" ] && sa_emit
  exit 0
fi

# Build components (without separators)

# Which repo the git elements describe.
#
# The cwd is not always a checkout. A per-task directory that symlinks out to the repos it works on, with the edits
# landing in a sibling worktree, leaves the outer repo's branch and status describing nothing you are doing.
#
# Three sources, best first:
#
#   1. the last file an editing tool touched, per the transcript. The only one that survives that layout.
#   2. a lone entry under ./repos/, which names the repo before anything has been edited.
#   3. the cwd, right everywhere else.
session_dir="${payload_project_dir:-$current_dir_path}"
git_ctx=""
if [ "$show_active_repo" = "1" ] && [ -n "$payload_transcript" ]; then
  # The whole file, not its tail. The edits that matter are often thousands of turns back... in a real ticket session
  # the last 256KB of a 2.7MB transcript held no edit at all and the answer sat near the start.
  #
  # grep, not awk. Same scan, and awk isn't close: 57ms vs 5ms on that file, 835ms vs 13ms on the largest transcript
  # here (60MB). Even that worst case is affordable once a render, so there's no cache to keep coherent.
  active_file=$(grep -o \
    '"name":"\(Edit\|Write\|MultiEdit\|NotebookEdit\)","input":{[^}]*"file_path":"[^"]*"' \
    "$payload_transcript" 2>/dev/null | tail -1)
  active_file=${active_file##*\"file_path\":\"}
  active_file=${active_file%\"}
  [ -n "$active_file" ] && [ -e "$active_file" ] && git_ctx=${active_file%/*}
fi
if [ -z "$git_ctx" ] && [ -d "$session_dir/repos" ]; then
  repo_count=0
  for repo_link in "$session_dir"/repos/*; do
    [ -d "$repo_link" ] || continue
    repo_count=$((repo_count + 1))
    git_ctx="$repo_link"
  done
  # More than one and there is nothing to choose between them.
  [ "$repo_count" -eq 1 ] || git_ctx=""
fi

# Root, worktree-ness and branch, without running git.
#
# git rev-parse and git branch cost ~10ms each, and every answer sits in the filesystem in plain text:
#
#   .git is a directory  -> ordinary checkout
#   .git is a FILE       -> linked worktree, holding "gitdir: <path>"
#   <gitdir>/HEAD        -> "ref: refs/heads/<branch>", or a bare sha when detached
#
# Walk up for .git, read two files. No forks, and it works where git isn't on PATH.
git_toplevel=""
git_gitdir=""
git_is_worktree=0
git_branch=""
walk_dir="${git_ctx:-$current_dir_path}"
while [ -n "$walk_dir" ] && [ "$walk_dir" != "/" ]; do
  if [ -d "$walk_dir/.git" ]; then
    git_toplevel="$walk_dir"
    git_gitdir="$walk_dir/.git"
    break
  elif [ -f "$walk_dir/.git" ]; then
    IFS= read -r git_link < "$walk_dir/.git" 2>/dev/null
    case "$git_link" in
      "gitdir: "*)
        git_toplevel="$walk_dir"
        git_gitdir=${git_link#gitdir: }
        git_is_worktree=1
        ;;
    esac
    break
  fi
  walk_dir=${walk_dir%/*}
done
if [ -n "$git_gitdir" ] && [ -r "$git_gitdir/HEAD" ]; then
  IFS= read -r git_head < "$git_gitdir/HEAD" 2>/dev/null
  case "$git_head" in
    "ref: refs/heads/"*) git_branch=${git_head#ref: refs/heads/} ;;
  esac
fi

# Refs and config live in the common dir: the git-dir itself for a plain checkout, and for a linked worktree wherever
# its "commondir" file points. Worktrees share everything but HEAD.
git_common="$git_gitdir"
if [ -n "$git_gitdir" ] && [ -f "$git_gitdir/commondir" ]; then
  IFS= read -r git_cdir < "$git_gitdir/commondir" 2>/dev/null
  case "$git_cdir" in
    "")  ;;
    /*)  git_common="$git_cdir" ;;
    *)   git_common="$git_gitdir/$git_cdir" ;;
  esac
fi

# Where the repo lives on the web, from its own origin URL rather than payload workspace.repo, which describes the cwd's
# repo and not the child repo a ticket folder is editing. One file read, no fork:
#
#   git@github.com:owner/name.git        ssh://git@host:7999/KEY/name.git
#   https://user@host/owner/name.git     git@ssh.dev.azure.com:v3/org/proj/name
git_origin=""
if [ -n "$git_common" ] && [ -r "$git_common/config" ]; then
  git_in_origin=0
  while IFS= read -r git_cl; do
    git_cl=${git_cl#"${git_cl%%[![:space:]]*}"}
    case "$git_cl" in
      "[remote \"$git_remote\"]") git_in_origin=1 ;;
      "["*) git_in_origin=0 ;;
      url*=*) [ "$git_in_origin" = 1 ] && { git_origin=${git_cl#*=}; git_origin=${git_origin#"${git_origin%%[![:space:]]*}"}; break; } ;;
    esac
  done < "$git_common/config"
fi
git_host=""; git_path=""
if [ -n "$git_origin" ]; then
  git_u=${git_origin%/}; git_u=${git_u%.git}
  case "$git_u" in
    *://*) git_u=${git_u#*://}; git_u=${git_u#*@}; git_host=${git_u%%/*}; git_path=${git_u#*/} ;;
    *@*:*) git_u=${git_u#*@};   git_host=${git_u%%:*}; git_path=${git_u#*:} ;;
    *:*)                        git_host=${git_u%%:*}; git_path=${git_u#*:} ;;
  esac
  git_host=${git_host%%:*}   # a port, if any
  git_path=${git_path#/}
fi

# The branch's page on that host. GitHub, GitLab (any host with gitlab in the name, so self-hosted too), Bitbucket Cloud
# and Server, Gitea/Forgejo/Codeberg and Azure DevOps each spell it differently. Anything else gets the repo root, and
# BRANCH_LINK_TEMPLATE overrides the lot with {host} {path} {branch}.
git_branch_url=""
if [ "$links" = "1" ] && [ -n "$git_host" ] && [ -n "$git_path" ] && [ -n "$git_branch" ]; then
  git_b=${git_branch//\#/%23}
  if [ -n "$branch_link_template" ]; then
    git_branch_url=$branch_link_template
    git_branch_url=${git_branch_url//\{host\}/$git_host}
    git_branch_url=${git_branch_url//\{path\}/$git_path}
    git_branch_url=${git_branch_url//\{branch\}/$git_b}
  else
    case "$git_host" in
      github.com|*github*)             git_branch_url="https://$git_host/$git_path/tree/$git_b" ;;
      *gitlab*)                        git_branch_url="https://$git_host/$git_path/-/tree/$git_b" ;;
      bitbucket.org)                   git_branch_url="https://bitbucket.org/$git_path/branch/$git_b" ;;
      *bitbucket*)                     git_branch_url="https://$git_host/projects/${git_path%%/*}/repos/${git_path#*/}/browse?at=refs/heads/$git_b" ;;
      codeberg.org|*gitea*|*forgejo*)  git_branch_url="https://$git_host/$git_path/src/branch/$git_b" ;;
      ssh.dev.azure.com)               git_az=${git_path#v3/}; git_branch_url="https://dev.azure.com/${git_az%%/*}/${git_az#*/}"
                                       git_branch_url="${git_branch_url%/*}/_git/${git_branch_url##*/}?version=GB$git_b" ;;
      dev.azure.com|*visualstudio.com) git_branch_url="https://$git_host/$git_path?version=GB$git_b" ;;
      *)                               git_branch_url="https://$git_host/$git_path" ;;
    esac
  fi
fi

# Unpushed: the branch's ref against the remote's copy, straight from the ref files, no fork. Loose refs first, since a
# loose ref is newer than the packed one it shadows. packed-refs only when one is missing, and then one grep rather than
# a bash loop over thousands of lines. Differing or never pushed earns the mark. No count... that needs the history
# walked, which is a git call per render.
git_unpushed=0
if [ "$show_unpushed" = "1" ] && [ -n "$git_branch" ] && [ -n "$git_common" ]; then
  git_local_sha=""; git_remote_sha=""
  [ -r "$git_common/refs/heads/$git_branch" ] && IFS= read -r git_local_sha < "$git_common/refs/heads/$git_branch"
  [ -r "$git_common/refs/remotes/$git_remote/$git_branch" ] && IFS= read -r git_remote_sha < "$git_common/refs/remotes/$git_remote/$git_branch"
  if { [ -z "$git_local_sha" ] || [ -z "$git_remote_sha" ]; } && [ -r "$git_common/packed-refs" ]; then
    while IFS= read -r git_pl; do
      case "$git_pl" in
        *" refs/heads/$git_branch")                [ -n "$git_local_sha" ]  || git_local_sha=${git_pl%% *} ;;
        *" refs/remotes/$git_remote/$git_branch")  [ -n "$git_remote_sha" ] || git_remote_sha=${git_pl%% *} ;;
      esac
    done <<EOF
$(grep -E " refs/(heads|remotes/$git_remote)/$git_branch\$" "$git_common/packed-refs" 2>/dev/null)
EOF
  fi
  [ -n "$git_local_sha" ] && [ "$git_local_sha" != "$git_remote_sha" ] && git_unpushed=1
fi
git_unpushed_mark=""
[ "$git_unpushed" = 1 ] && git_unpushed_mark=" ${YELLOW}${unpushed_icon}"

# Is that repo somewhere other than where you're standing? A string test, not a second rev-parse. Session folder under
# the repo root means the folder element already names it. Otherwise "main" of what... so name the repo too.
git_foreign=0
if [ -n "$git_toplevel" ]; then
  case "$session_dir/" in
    "$git_toplevel"/*) ;;
    *) git_foreign=1 ;;
  esac
fi

# 1. The folder claude started in. Not the repo-relative path... nested a few deep that reads
# "tasks/acme/PROJ-123", three levels of noise around the one word that means anything.
#
#   DIR_STYLE=session   PROJ-123              (default)
#            =repo      myproject/services    relative to the git root
#            =basename  services
dir_text=""
dir_label=${session_dir##*/}
[ -n "$dir_label" ] || dir_label="$current_dir"
if [ "$dir_style" = "basename" ]; then
  dir_label="$current_dir"
elif [ "$dir_style" = "repo" ] && [ -n "$git_toplevel" ] && [ -z "$git_ctx" ]; then
  repo_name=${git_toplevel##*/}
  phys_cwd=$(cd "$current_dir_path" 2>/dev/null && pwd -P)
  [ -n "$phys_cwd" ] || phys_cwd="$current_dir_path"
  if [ "$phys_cwd" = "$git_toplevel" ]; then
    dir_label="$repo_name"
  elif [ "${phys_cwd#"$git_toplevel"/}" != "$phys_cwd" ]; then
    rel="${phys_cwd#"$git_toplevel"/}"
    case "$rel" in
      */*/*) dir_label="$repo_name/…/${rel##*/}" ;;
      *)     dir_label="$repo_name/$rel" ;;
    esac
  fi
fi
if [ "$show_dir" = "1" ]; then
  # Cmd-click opens the folder in Finder. Spaces are the one thing a path has that a URL can't.
  glyph_label "$dir_icon" "$dir_label" "$BLUE"
  link "file://${session_dir// /%20}" "$glyphed"
  dir_text="${BLUE}${linked}${RESET}"
fi

# 2. The repo being worked on: worktree name, or branch on a plain checkout. The glyph says which, so the name
# doesn't have to.
#
# A linked worktree keeps its git-dir under <common>/worktrees/, so the two differ. Both have to be absolute first:
# below the repo root git hands back an absolute --git-dir and a RELATIVE --git-common-dir ("../.git"), and comparing
# those raw marks every subdirectory of every plain repo a worktree.
repo_text=""
if [ "$show_branch" = "1" ] && [ -n "$git_toplevel" ]; then
  # Either form links to the branch page, and carries the unpushed mark when the remote is behind or has never seen it.
  if [ "$git_is_worktree" = "1" ] || [ -n "$payload_worktree" ]; then
    # The worktree directory name already carries the ticket, so it needs no branch beside it.
    glyph_label "$worktree_icon" "${payload_worktree:-${git_toplevel##*/}}" "$TEAL"
    link "$git_branch_url" "$glyphed"
    repo_text="${TEAL}${linked}${git_unpushed_mark}${RESET}"
  elif [ -n "$git_branch" ]; then
    if [ "$git_foreign" = "1" ]; then
      # "main" of what? Name the repo when it isn't the one you're standing in.
      glyph_label "$branch_icon" "${git_toplevel##*/}:${git_branch}" "$GREEN"
    else
      glyph_label "$branch_icon" "$git_branch" "$GREEN"
    fi
    link "$git_branch_url" "$glyphed"
    repo_text="${GREEN}${linked}${git_unpushed_mark}${RESET}"
  fi
fi

# 3. Whether that repo is dirty, and by how many files. Costs a `git status`: ~12ms normally, 59ms on a very large
# working tree, so it gets its own switch.
status_text=""
if [ "$show_git_status" = "1" ] && [ -n "$git_toplevel" ]; then
  # The one thing that needs git. Nothing on disk says whether the working tree matches the index without comparing.
  #
  # The exit status is the whole point of the `if`. Empty output means clean only when git succeeded... it also comes
  # back empty with no git on PATH, on a repo git refuses for dubious ownership (2.35.2+, common on a shared or
  # mounted checkout), and on a corrupt index. Reading empty as clean painted a green tick over every one of those,
  # which is worse than saying nothing, because a tick is a claim.
  if git_st=$(git -C "$git_toplevel" status --porcelain 2>/dev/null); then
    if [ -z "$git_st" ]; then
      status_text="${GREEN}${git_clean_icon}${RESET}"
    else
      st_count=0
      while IFS= read -r _; do st_count=$((st_count + 1)); done <<EOF
$git_st
EOF
      # Spaced like the branch and worktree glyphs. This mark is wide enough that a glued-on digit reads as part of it.
      status_text="${YELLOW}${git_dirty_icon} ${st_count}${RESET}"
    fi
  fi
fi

# 4. The branch's open PR, when Claude Code reports one (pr.number, pr.url, pr.review_state), colored by review
# state and linked. The footer has its own badge on the right... this one sits with the git cluster, where the eye is.
pr_text=""
if [ "$show_pr" = "1" ] && [ -n "$payload_pr" ]; then
  js_val=""
  js_field() {  # <blob> <key> -> js_val, the value with its quotes off
    js_val=""
    case "$1" in *"\"$2\":"*) ;; *) return ;; esac
    local v=${1#*\"$2\":}
    case "$v" in
      \"*) v=${v#\"}; js_val=${v%%\"*} ;;
      *)   v=${v%%,*}; js_val=${v%\}} ;;
    esac
  }
  js_field "$payload_pr" number; pr_number=$js_val
  js_field "$payload_pr" url;    pr_url=$js_val
  js_field "$payload_pr" review_state; pr_state=$js_val
  if [ -n "$pr_number" ] && [ "$pr_number" != "null" ]; then
    case "$pr_state" in
      approved)          pr_color="$GREEN" ;;
      changes_requested) pr_color="$LEVEL_10" ;;
      draft)             pr_color="$GRAY" ;;
      *)                 pr_color="$YELLOW" ;;
    esac
    glyph_label "$pr_icon" "$pr_number" "$pr_color"
    link "$pr_url" "$glyphed"
    pr_text="${pr_color}${linked}${RESET}"
  fi
fi

# Model and effort, in two marks that say neither out loud.
#
#   MODEL_STYLE=glyph  󰝤 ▁▃▅▆   family as a shape, effort as a lit ramp   (default)
#              =icon   OM        first letter + effort tier
#              =name   Opus
#              =both   O Opus
#              =full   Opus 5    (display_name verbatim, the old behavior)
#
# Glyph style exists to be unreadable over a shoulder. "OM" says Opus at max to anyone looking. A shape and a ramp give
# up nothing, including whether a model is involved.
#
# Sides drop with capability: Mythos circle, Fable hexagon, Opus square, Sonnet triangle, Haiku a dot. Hexagon sat out
# the four-family version, on the argument that filled it reads as the circle... Mythos spent that rung. Every mark is
# U+F0000 or above, the plane only Nerd Fonts claim: macOS fonts shadow the BMP private-use range and a glyph there
# renders as nothing (Haiku's dot did, oct-dot_fill U+F444).
#
# Effort is five chevrons out of the meter's arrow cap, one lit per level, fading outward. Unlit ones are the arrow's
# outline in a dim tint, so all five stay countable. EFFORT_STYLE=pill is the older capsule:
#
#    low    medium    high    xhigh    max
#
# No effort dial means no effort.level in the payload and no run. Ultracode folds to xhigh before the payload is
# written, so it can't show. Monochrome takes the letters instead... with no color to share, shape and ramp lose the
# relationship they exist to show.

# Context percentage and color, resolved before the model block because the effort ramp lights in this color.
context_pct=""
context_color=""
current_tokens=0
if [ "$show_context" = "1" ]; then
  input_tokens="${payload_input_tokens:-0}"
  cache_create="${payload_cache_create:-0}"
  cache_read="${payload_cache_read:-0}"
  context_size="$payload_ctx_size"
  if [ -n "$context_size" ] && [ "$context_size" -gt 0 ]; then
    current_tokens=$((input_tokens + cache_create + cache_read))
    context_pct=$((current_tokens * 100 / context_size))
    # Red at 45%, well before the wall, because that's where the wrap-up-or-compact call gets made.
    if [ "$context_pct" -le 25 ]; then
      context_color="$CYAN"
    elif [ "$context_pct" -le 34 ]; then
      context_color="$YELLOW"
    elif [ "$context_pct" -le 44 ]; then
      context_color="$LEVEL_8"
    else
      context_color="$LEVEL_10"
    fi
  fi
fi

model_text=""
if [ "$show_model" = "1" ] && [ -n "$model" ]; then
  model_id="$payload_model_id"

  case "$(printf '%s %s' "$model" "$model_id" | tr '[:upper:]' '[:lower:]')" in
    *mythos*) model_icon="$model_icon_mythos"; model_mark="$model_mark_mythos"
              model_short="Mythos"; model_hex="$model_color_mythos" ;;
    *opus*)   model_icon="$model_icon_opus";   model_mark="$model_mark_opus"
              model_short="Opus";   model_hex="$model_color_opus" ;;
    *fable*)  model_icon="$model_icon_fable";  model_mark="$model_mark_fable"
              model_short="Fable";  model_hex="$model_color_fable" ;;
    *sonnet*) model_icon="$model_icon_sonnet"; model_mark="$model_mark_sonnet"
              model_short="Sonnet"; model_hex="$model_color_sonnet" ;;
    *haiku*)  model_icon="$model_icon_haiku";  model_mark="$model_mark_haiku"
              model_short="Haiku";  model_hex="$model_color_haiku" ;;
    # Unknown family: first letter of whatever Claude Code calls it.
    *)        model_icon="${model_icon_default:-${model:0:1}}"; model_mark="$model_icon"
              model_short="$model"; model_hex="" ;;
  esac

  # Resolved before the style case, since the glyph style IS the effort.
  effort="$payload_effort"
  [ "$show_effort" = "1" ] || effort=""

  # Monochrome takes the letters (see the block above).
  if [ "$model_style" = "glyph" ] && [ "$color_mode" = "monochrome" ]; then
    model_style="icon"
  fi

  model_color="$YELLOW"
  case "$model_style" in
    glyph)
      # The family shape. Under MODEL_IN_CONTEXT=1 the context block lifts it into the meter's first cell and it takes
      # the bar's coloring. Otherwise it stands here in the family color with the ramp beside it.
      model_display="$model_mark"
      if [ -n "$model_hex" ]; then
        hex_to_ansi "$model_hex"
        model_color="$ansi"
      fi
      ;;
    icon) model_display="$model_icon" ;;
    name) model_display="$model_short" ;;
    both) model_display="$model_icon $model_short" ;;
    *)    model_display="$model" ;;
  esac

  # The effort tier rides with the model since it qualifies it: OM is Opus at max, OX at xhigh. Only in the payload for
  # models with an effort dial. Medium is blank by default, which frees M for max. Blank whichever tier you sit at.
  if [ "$show_effort" = "1" ] && [ "$model_style" != "glyph" ]; then
    case "$effort" in
      low)    effort_label="$effort_label_low" ;;
      medium) effort_label="$effort_label_medium" ;;
      high)   effort_label="$effort_label_high" ;;
      xhigh)  effort_label="$effort_label_xhigh" ;;
      max)    effort_label="$effort_label_max" ;;
      *)      effort_label="" ;;
    esac
    if [ -n "$effort_label" ]; then
      # Glued to a single-letter model (OM), spaced off anything longer.
      if [ ${#model_display} -le 1 ]; then
        model_display="${model_display}${effort_label}"
      else
        model_display="${model_display} ${effort_label}"
      fi
    fi
  fi

  build_effort "$effort"

  # Appended here and lifted back out by the context block, so effort survives when the meter isn't rendering.
  model_text="${model_color}${model_display}${RESET}${effort_ramp}${effort_ramp:+${RESET}${effort_cap_fg}${effort_close_glyph}}${RESET}"
fi

# Cmd-click opens that account's usage page, where the two window bars come from. Which page depends on who bills: a
# subscription's windows live on claude.ai, an API key's spend in the Console. PROFILE_URL overrides both.
profile_text=""
if [ "$show_profile" = "1" ] && [ -n "$profile_name" ]; then
  profile_mark=$(plan_icon)
  profile_href="$profile_url"
  if [ -z "$profile_href" ]; then
    if [ "$account_is_subscription" = "1" ]; then
      profile_href="https://claude.ai/settings/usage"
    else
      profile_href="https://console.anthropic.com/settings/usage"
    fi
  fi
  glyph_label "$profile_mark" "$profile_name" "$MAGENTA"
  link "$profile_href" "$glyphed"
  profile_text="${MAGENTA}${linked}${RESET}"
fi

# Context percentage calculation from current_usage tokens
context_text=""
ctx_bar=0
if [ "$show_context" = "1" ]; then
  if [ -n "$context_pct" ]; then
    # Integer percentage for display
    context_int=$context_pct

    # Display as tokens or percentage
    ctx_label=""
    [ "$show_context_label" = "1" ] && ctx_label="C: "

    if [ "$context_as_tokens" = "1" ]; then
      if [ "$current_tokens" -ge 1000 ]; then
        ctx_value="$((current_tokens / 1000))K"
      else
        ctx_value="$current_tokens"
      fi
    else
      ctx_value="${context_int}"
    fi

    # The model mark rides in the meter's first cell rather than standing alone, because the three things it relates are
    # one thing: which model, at what effort, eating how much context. Only the one-cell glyph style fits... "Opus 5" in
    # there would eat the meter.
    ctx_lead=""
    ctx_trail=""
    if [ "$model_in_context" = "1" ] && [ "$show_context_bar" = "1" ] \
       && [ "$show_model" = "1" ] && [ "$model_style" = "glyph" ] && [ -n "$model_display" ]; then
      # Shape says which model, fill says how much context is gone, the run says how hard it's being pushed.
      ctx_lead="$model_display"
      ctx_trail="$effort_ramp"
      model_text=""
    fi

    # No pace marker here. Context has no clock to pace against, it just climbs till a compact resets it.
    if [ "$show_context_bar" = "1" ]; then
      # The effort run joins the meter rather than floating after it: the meter hands its background off through the
      # arrow cap and the run picks it up, either the first chevron's band or the pill's floor. Needs backgrounds to
      # hand off... without them (blocks, monochrome, caps off) the ramp is just appended.
      ctx_pill_bg=""
      ctx_pill_cap=""
      if [ -n "$ctx_trail" ] && [ -n "$effort_join_bg" ] && [ -n "$bar_cap_arrow" ]; then
        ctx_pill_bg="$effort_join_bg"
        # Chevrons close themselves and leave this a bare RESET. The pill's hemisphere gets drawn here.
        ctx_pill_cap="${RESET}${effort_cap_fg}${effort_close_glyph}${RESET}"
      fi
      # Drawn in the layout pass below, once the bar has a width.
      ctx_bar=1
    else
      [ "$context_as_tokens" = "1" ] || ctx_value="${ctx_value}%"
      context_text="${context_color}${ctx_label}${ctx_value}${RESET}"
    fi
  fi
fi

# One clock per render, one fork for it. CLAUDE_STATUSLINE_NOW pins it, which is how the selftest and preview.sh get
# reset times and pace markers that don't depend on when they ran.
case "${CLAUDE_STATUSLINE_NOW:-}" in
  ''|*[!0-9]*) now_epoch=$(date +%s) ;;
  *)           now_epoch=$CLAUDE_STATUSLINE_NOW ;;
esac

# The prompt cache, beside the context meter because the cached prefix is the conversation.
#
# It answers "what does the next turn cost", not "is the cache warm", and those are opposite polarities. Warm is the
# cheap ordinary state and shows nothing, because a fire lit all session says nothing. Fire means money burning.
#
# Held (warm, plenty of TTL): CACHE_HELD_ICON, off by default. A CACHE_HELD_TINT wash of the meter's color. Last
# CACHE_WARN_AT percent of the TTL: amber, brightening as it closes. The only actionable tier... a turn sent now
#   still reads the prefix at about a tenth of input price.
# Cold: red and bold. The next turn rewrites the whole prefix at the cache-write premium.
#
# Only an idle session reaches the warning tier, since an active one keeps refreshing, so the flame shows up when
# there's time to act. Claude Code re-renders at expiry and every refreshInterval between. All absent till the first
# response reports cache tokens.
cache_text=""
if [ "$show_cache" = "1" ] && [ "$payload_cache_observed" = "true" ]; then
  cache_glyph=""; cache_fg=""; cache_weight=""
  if [ "$payload_cache_warm" = "true" ]; then
    cache_left_pct=100
    case "$payload_cache_expires" in
      ''|null|*[!0-9]*) ;;
      *)
        case "$payload_cache_ttl" in *5m*) cache_ttl=300 ;; *) cache_ttl=3600 ;; esac
        cache_left=$((payload_cache_expires - now_epoch))
        [ "$cache_left" -lt 0 ] && cache_left=0
        [ "$cache_left" -gt "$cache_ttl" ] && cache_left=$cache_ttl
        cache_left_pct=$(( 100 * cache_left / cache_ttl ))
        ;;
    esac
    if [ "$cache_warn_at" -gt 0 ] && [ "$cache_left_pct" -le "$cache_warn_at" ]; then
      # 55% of amber at the top of the window, full amber as it runs out.
      cache_glyph="$cache_icon"
      tint "$YELLOW" "$(( 100 - 45 * cache_left_pct / cache_warn_at ))"
      if [ -n "$tinted" ]; then cache_fg=$'\033[38;2;'"$tinted"'m'; else cache_fg="$YELLOW"; fi
    elif [ -n "$cache_held_icon" ]; then
      cache_glyph="$cache_held_icon"
      cache_base="${context_color:-$CYAN}"
      tint "$cache_base" "$cache_held_tint"
      if [ -n "$tinted" ]; then cache_fg=$'\033[38;2;'"$tinted"'m'; else cache_fg="$cache_base"; fi
    fi
  else
    # Bold carries the cold tier where color can't: monochrome, and amber next to red under the common kinds of color
    # blindness.
    cache_glyph="$cache_icon"
    cache_fg="$LEVEL_10"
    cache_weight=$'\033[1m'
  fi
  [ -n "$cache_glyph" ] && cache_text="${cache_weight}${cache_fg}${cache_glyph}${RESET}"
fi

usage_text=""
usage_bar=0
if [ "$show_usage" = "1" ]; then
  utilization="$rl_session_pct"
  reset_epoch=$(reset_epoch_of "$rl_session_reset")

  if [ -n "$utilization" ]; then
    if [ "$utilization" -le 10 ]; then
      usage_color="$LEVEL_1"
    elif [ "$utilization" -le 20 ]; then
      usage_color="$LEVEL_2"
    elif [ "$utilization" -le 30 ]; then
      usage_color="$LEVEL_3"
    elif [ "$utilization" -le 40 ]; then
      usage_color="$LEVEL_4"
    elif [ "$utilization" -le 50 ]; then
      usage_color="$LEVEL_5"
    elif [ "$utilization" -le 60 ]; then
      usage_color="$LEVEL_6"
    elif [ "$utilization" -le 70 ]; then
      usage_color="$LEVEL_7"
    elif [ "$utilization" -le 80 ]; then
      usage_color="$LEVEL_8"
    elif [ "$utilization" -le 90 ]; then
      usage_color="$LEVEL_9"
    else
      usage_color="$LEVEL_10"
    fi

    usage_label=""
    [ "$show_usage_label" = "1" ] && usage_label="S: "

    # How far into the window we are, and the color that pace earns. The marker's cell comes at draw time.
    elapsed_secs=""
    pace_color=""
    if [ "$show_pace_marker" = "1" ] && [ "$show_bar" = "1" ] && [ -n "$reset_epoch" ]; then
      remaining=$((reset_epoch - now_epoch))
      if [ $remaining -gt 0 ] && [ $remaining -lt 18000 ]; then
        elapsed_secs=$((18000 - remaining))

        # Compute pace color, falling back to usage_color (empty in monochrome = no color)
        pace_color="$usage_color"
        if [ "$pace_marker_step_colors" != "0" ] && [ $elapsed_secs -ge 540 ]; then
          projected_pct=$((utilization * 18000 / elapsed_secs))
          if [ $projected_pct -lt 50 ]; then
            pace_color="$PACE_COMFORTABLE"
          elif [ $projected_pct -lt 75 ]; then
            pace_color="$PACE_ON_TRACK"
          elif [ $projected_pct -lt 90 ]; then
            pace_color="$PACE_WARMING"
          elif [ $projected_pct -lt 100 ]; then
            pace_color="$PACE_PRESSING"
          elif [ $projected_pct -lt 120 ]; then
            pace_color="$PACE_CRITICAL"
          else
            pace_color="$PACE_RUNAWAY"
          fi
        fi

      fi
    fi

    reset_time_display=""
    if [ "$show_reset" = "1" ] && [ -n "$reset_epoch" ]; then
      epoch=$reset_epoch

      if [ -n "$epoch" ]; then
        # Round to nearest minute to prevent pinballing (e.g., 6:59:45 -> 7:00)
        seconds_part=$((epoch % 60))
        if [ "$seconds_part" -ge 30 ]; then
          epoch=$((epoch + (60 - seconds_part)))
        else
          epoch=$((epoch - seconds_part))
        fi

        fmt_short_time "$epoch" 0
        if [ -n "$short_time" ]; then
          # An arrow cap already points at this, so a text arrow says it twice. With no cap it earns its place again.
          reset_point=" → "
          [ -n "$bar_cap_arrow" ] && [ "$show_bar" = "1" ] && reset_point=" "
          if [ "$show_reset_label" = "1" ]; then
            reset_time_display="${reset_point}Reset: $short_time"
          else
            reset_time_display="${reset_point}${short_time}"
          fi
        fi
      fi
    fi

    if [ "$show_bar" = "1" ]; then
      # Drawn in the layout pass below, once the bar has a width.
      usage_bar=1
    else
      usage_text="${usage_color}${usage_label}${utilization}%${reset_time_display}${RESET}"
    fi
  fi
  # No placeholder while the figure isn't in. A "~" was a shrug where a number lands a second later.
fi

# This session's cost, ahead of the window it was spent in and in that bar's color, so the run reads "cost, usage,
# reset" for the same five hours.
#
# Claude Code computes it client-side at list price whoever pays, so the figure is never literally an invoice. "billed"
# shows it where somebody is nonetheless accounting for it:
#
#   API key      no oauthAccount at all, and the spend is real
#   spend limit  a gateway metering it in rate_limits
#   enterprise   an org seat, where usage gets attributed and charged back
#   team         same
#
# and hides it on a personal Max or Pro, where the plan flatly covers the session and the number is noise. That split is
# what makes this follow an account swap on its own. Lumping every subscription together instead would mean a work seat
# needed SHOW_COST=always, and that flag then puts a meaningless figure on screen the moment the login changes.
# `always` and `never` force it either way.
case "$show_cost" in
  0|never)  cost_applies=0 ;;
  1|always) cost_applies=1 ;;
  *)        cost_applies=0
            [ "$account_is_subscription" = 0 ] && cost_applies=1
            [ -n "$payload_spend_limit" ] && cost_applies=1
            case "$acct_type" in *enterprise*|*team*) cost_applies=1 ;; esac ;;
esac
money=""
# Whole dollars, nearest, nothing below 50c. Cents were three digits of precision on a figure nobody acts on that
# finely, and the trailing ".50" shoved every element right of it a cell as it ticked. Under 50c rounds to zero, which
# is already the hidden case.
fmt_money() {  # <usd float> -> money: whole dollars, empty under 0.50
  money=""
  local int=${1%%.*} frac=${1#*.}
  [ "$frac" = "$1" ] && frac=""
  [ -n "$int" ] || int=0
  frac="${frac}0"
  case "$int$frac" in *[!0-9]*) return ;; esac
  [ "${frac:0:1}" -ge 5 ] && int=$((int + 1))
  [ "$int" -gt 0 ] && money=$int
}
cents_of() {  # <usd float> -> cents, integer, truncated; empty if it isn't a number
  cents=""
  local int=${1%%.*} frac=${1#*.}
  [ "$frac" = "$1" ] && frac=""
  [ -n "$int" ] || int=0
  frac="${frac}00"
  case "$int$frac" in *[!0-9]*) return ;; esac
  cents=$((int * 100 + 10#${frac:0:2}))
}
fmt_cents() {  # <cents> -> money, the same whole dollars fmt_money gives
  money=""
  local d=$(( ($1 + 50) / 100 ))
  [ "$d" -gt 0 ] && money=$d
}
cost_text=""
if [ "$cost_applies" = 1 ] && [ -n "$payload_cost" ]; then
  fmt_money "$payload_cost"
  if [ -n "$money" ]; then
    cost_color="${usage_color:-$LEVEL_1}"
    cost_text="${cost_color}${cost_icon}${cost_icon:+ }${money}${RESET}"
  fi
fi

weekly_text=""
weekly_bar=0
if [ "$show_weekly" = "1" ] && [ "$show_usage" = "1" ]; then
  weekly_util="$rl_weekly_pct"
  weekly_reset="$rl_weekly_reset"

  if [ -n "$weekly_util" ]; then
    weekly_label=""
    [ "$show_weekly_label" = "1" ] && weekly_label="W: "
    w_elapsed=""
    w_pace_color=""

    if [ "$weekly_util" -le 10 ]; then
      weekly_color="$LEVEL_1"
    elif [ "$weekly_util" -le 20 ]; then
      weekly_color="$LEVEL_2"
    elif [ "$weekly_util" -le 30 ]; then
      weekly_color="$LEVEL_3"
    elif [ "$weekly_util" -le 40 ]; then
      weekly_color="$LEVEL_4"
    elif [ "$weekly_util" -le 50 ]; then
      weekly_color="$LEVEL_5"
    elif [ "$weekly_util" -le 60 ]; then
      weekly_color="$LEVEL_6"
    elif [ "$weekly_util" -le 70 ]; then
      weekly_color="$LEVEL_7"
    elif [ "$weekly_util" -le 80 ]; then
      weekly_color="$LEVEL_8"
    elif [ "$weekly_util" -le 90 ]; then
      weekly_color="$LEVEL_9"
    else
      weekly_color="$LEVEL_10"
    fi

    # Per-element override: weekly gets its own fixed color when set
    if [ "$color_mode" = "perElement" ] && [ -n "$element_color_weekly" ]; then
      hex_to_ansi "$element_color_weekly"; weekly_color=$ansi
    fi


    if [ "$show_weekly_pace_marker" = "1" ] && [ "$show_weekly_bar" = "1" ] && [ -n "$weekly_reset" ] && [ "$weekly_reset" != "null" ]; then
      w_reset_epoch=$(reset_epoch_of "$weekly_reset")
      if [ -n "$w_reset_epoch" ]; then
        w_remaining=$((w_reset_epoch - now_epoch))
        if [ $w_remaining -gt 0 ] && [ $w_remaining -lt 604800 ]; then
          w_elapsed=$((604800 - w_remaining))

          w_pace_color="$weekly_color"
          if [ "$pace_marker_step_colors" != "0" ] && [ $w_elapsed -ge 3024 ]; then
            w_projected=$((weekly_util * 604800 / w_elapsed))
            if [ $w_projected -lt 50 ]; then
              w_pace_color="$PACE_COMFORTABLE"
            elif [ $w_projected -lt 75 ]; then
              w_pace_color="$PACE_ON_TRACK"
            elif [ $w_projected -lt 90 ]; then
              w_pace_color="$PACE_WARMING"
            elif [ $w_projected -lt 100 ]; then
              w_pace_color="$PACE_PRESSING"
            elif [ $w_projected -lt 120 ]; then
              w_pace_color="$PACE_CRITICAL"
            else
              w_pace_color="$PACE_RUNAWAY"
            fi
          fi
        fi
      fi
    fi

    weekly_reset_display=""
    if [ "$show_weekly_reset" = "1" ] && [ -n "$weekly_reset" ] && [ "$weekly_reset" != "null" ]; then
      w_reset_epoch=$(reset_epoch_of "$weekly_reset")
      if [ -n "$w_reset_epoch" ]; then
        seconds_part=$((w_reset_epoch % 60))
        if [ "$seconds_part" -ge 30 ]; then
          w_reset_epoch=$((w_reset_epoch + (60 - seconds_part)))
        else
          w_reset_epoch=$((w_reset_epoch - seconds_part))
        fi
        fmt_short_time "$w_reset_epoch" 1
        if [ -n "$short_time" ]; then
          w_reset_point=" → "
          [ -n "$bar_cap_arrow" ] && [ "$show_weekly_bar" = "1" ] && w_reset_point=" "
          weekly_reset_display="${w_reset_point}${short_time}"
        fi
      fi
    fi

    if [ "$show_weekly_bar" = "1" ]; then
      weekly_bar=1
    else
      weekly_text="${weekly_color}${weekly_label}${weekly_util}%${weekly_reset_display}${RESET}"
    fi
  fi
fi

# ---- The week's spend against a budget of your own ----
#
# The payload carries this session's cost and nothing else, so the week's total is kept in
# ~/.claude/statusline-spend.tsv, rows of "<account> <session> <seen> <cents>". Later rows beat earlier ones for the
# same session, so one session's many renders collapse to its final cost instead of summing.
#
# ACCOUNT-SCOPED, because the money is. Sum only the rows for whoever is signed in now, or a swap from a work seat to a
# personal login carries the work week's spend across and bills it against the wrong budget. Other accounts' rows are
# kept, not dropped, so switching back and forth leaves each week intact. The key is a hash of the account rather than
# its email, so the file holds no address.
#
# No API call, no key, no daemon, and it works on a plan that reports no spend at all, which is the point on an
# enterprise seat. This Mac only, and only sessions that rendered... a gauge, not an invoice.
#
# APPEND-ONLY, because several sessions render at once. Read-merge-write races and loses rows, and an ended session
# never re-adds itself, so the week drifts down silently. One O_APPEND write of one short line doesn't interleave.
#
# Rewrites only compact, past LEDGER_MAX rows or once last week's rows are in the file, through a temp file and rename
# so a concurrent reader sees old or new, never half. A row appended in that window comes back next render. None of it
# exists till WEEKLY_BUDGET_USD is set.
LEDGER_MAX=64
budget_text=""
budget_bar=0
if [ "$show_budget" = "1" ] && [ -n "$weekly_budget_usd" ]; then
  cents_of "$weekly_budget_usd"; budget_cents=$cents
  if [ -n "$budget_cents" ] && [ "$budget_cents" -gt 0 ]; then
    # Local midnight at the top of the week. One date fork, only for people who turned this on. A DST shift inside the
    # week moves the boundary by its hour, which no budget cares about.
    IFS=' ' read -r budget_dow budget_h budget_m budget_s <<EOF
$(epoch_fmt "$now_epoch" "+%u %H %M %S")
EOF
    case "$budget_dow" in ''|*[!0-9]*) budget_dow=1 ;; esac
    [ "$budget_week_start" = "sun" ] && budget_dow=$((budget_dow % 7 + 1))
    week_start=$(( now_epoch - ((budget_dow - 1) * 86400 \
      + 10#${budget_h:-0} * 3600 + 10#${budget_m:-0} * 60 + 10#${budget_s:-0}) ))

    cents_of "${payload_cost:-0}"; session_cents=${cents:-0}

    # Who the row belongs to. FNV-1a over the account identity, in pure bash: eight lines beats a fork, and a hash keeps
    # the address out of a file that is easy to cat. An API-key login has no oauthAccount and gets "apikey".
    acct_ident="${acct_type}|${acct_email}"
    if [ "$acct_ident" = "|" ]; then
      acct_key=apikey
    else
      acct_hash=2166136261
      acct_rest=$acct_ident
      while [ -n "$acct_rest" ]; do
        printf -v acct_ch '%d' "'${acct_rest:0:1}"
        acct_rest=${acct_rest:1}
        acct_hash=$(( (acct_hash ^ acct_ch) & 4294967295 ))
        acct_hash=$(( (acct_hash * 16777619) & 4294967295 ))
      done
      printf -v acct_key '%08x' "$acct_hash"
    fi

    ledger="$HOME/.claude/statusline-spend.tsv"
    ledger_accts=(); ledger_ids=(); ledger_amts=(); ledger_seen=()
    ledger_rows=0; ledger_stale=0; stored_self=-1
    if [ -r "$ledger" ]; then
      while IFS="	" read -r l_acct l_id l_seen l_cents; do
        [ -n "$l_acct" ] && [ -n "$l_id" ] || continue
        # A row this cannot parse is a row worth rewriting away, which is also how the pre-account 3-column format
        # retires itself: every old row lands here once and the next compaction drops it.
        case "$l_seen$l_cents" in ''|*[!0-9]*) ledger_stale=1; continue ;; esac
        if [ "$l_seen" -lt "$week_start" ]; then ledger_stale=1; continue; fi
        ledger_rows=$((ledger_rows + 1))
        # Another account's row is carried through compaction untouched and left out of the sum.
        if [ "$l_acct" = "$acct_key" ] && [ "$l_id" = "$payload_session" ]; then stored_self=$l_cents; continue; fi
        l_i=0; l_n=${#ledger_ids[@]}
        while [ "$l_i" -lt "$l_n" ]; do
          [ "${ledger_accts[$l_i]}" = "$l_acct" ] && [ "${ledger_ids[$l_i]}" = "$l_id" ] && break
          l_i=$((l_i + 1))
        done
        ledger_accts[$l_i]=$l_acct
        ledger_ids[$l_i]=$l_id
        ledger_amts[$l_i]=$l_cents
        ledger_seen[$l_i]=$l_seen
      done < "$ledger"
    fi
    spent_cents=0
    l_i=0; l_n=${#ledger_ids[@]}
    while [ "$l_i" -lt "$l_n" ]; do
      [ "${ledger_accts[$l_i]}" = "$acct_key" ] && spent_cents=$((spent_cents + ledger_amts[l_i]))
      l_i=$((l_i + 1))
    done
    # A resumed session re-reports from zero, so take the larger of stored and payload. A fresh payload must not walk
    # the week's number backwards.
    [ "$stored_self" -gt "$session_cents" ] && session_cents=$stored_self
    if [ -n "$payload_session" ]; then
      spent_cents=$((spent_cents + session_cents))
      # One appended line, only when the figure moved. A session still at zero has nothing to record.
      if [ "$session_cents" -gt 0 ] && [ "$stored_self" != "$session_cents" ] \
         && [ -d "$HOME/.claude" ]; then
        printf '%s\t%s\t%s\t%s\n' "$acct_key" "$payload_session" "$now_epoch" "$session_cents" \
          >> "$ledger" 2>/dev/null
        ledger_rows=$((ledger_rows + 1))
      fi
    fi
    if [ "$ledger_stale" = 1 ] || [ "$ledger_rows" -gt "$LEDGER_MAX" ]; then
      if [ -d "$HOME/.claude" ]; then
        ledger_tmp="${ledger}.$$"
        {
          l_i=0; l_n=${#ledger_ids[@]}
          while [ "$l_i" -lt "$l_n" ]; do
            # Its own seen time, not now. That stamp prunes the row at the top of next week, and refreshing it here
            # would outlive the week it belongs to.
            printf '%s\t%s\t%s\t%s\n' "${ledger_accts[$l_i]}" "${ledger_ids[$l_i]}" \
              "${ledger_seen[$l_i]}" "${ledger_amts[$l_i]}"
            l_i=$((l_i + 1))
          done
          [ -n "$payload_session" ] && [ "$session_cents" -gt 0 ] && \
            printf '%s\t%s\t%s\t%s\n' "$acct_key" "$payload_session" "$now_epoch" "$session_cents"
        } > "$ledger_tmp" 2>/dev/null \
          && mv -f "$ledger_tmp" "$ledger" 2>/dev/null
        rm -f "$ledger_tmp" 2>/dev/null
      fi
    fi

    budget_pct=$(( spent_cents * 100 / budget_cents ))
    level_color "$budget_pct"; budget_color=$level
    if [ "$color_mode" = "perElement" ] && [ -n "$element_color_budget" ]; then
      hex_to_ansi "$element_color_budget"; budget_color=$ansi
    fi

    # The label is money, not a percentage. The bar already says how much of the budget is gone. Whole dollars, and a
    # bare 0 under 50c... a bar can't go empty-handed the way the cost element can.
    fmt_cents "$spent_cents"
    budget_value="${money:-0}"
    budget_label=""
    [ "$show_budget_label" = "1" ] && budget_label="B: "

    # Pace is the week's clock against the week's money, read like the weekly bar's: behind the marker is under budget
    # for the day.
    b_marker_frac=$(( (now_epoch - week_start) ))
    b_pace_color="$budget_color"
    if [ "$pace_marker_step_colors" != "0" ] && [ "$b_marker_frac" -ge 3024 ]; then
      b_projected=$(( budget_pct * 604800 / b_marker_frac ))
      if [ $b_projected -lt 50 ]; then
        b_pace_color="$PACE_COMFORTABLE"
      elif [ $b_projected -lt 75 ]; then
        b_pace_color="$PACE_ON_TRACK"
      elif [ $b_projected -lt 90 ]; then
        b_pace_color="$PACE_WARMING"
      elif [ $b_projected -lt 100 ]; then
        b_pace_color="$PACE_PRESSING"
      elif [ $b_projected -lt 120 ]; then
        b_pace_color="$PACE_CRITICAL"
      else
        b_pace_color="$PACE_RUNAWAY"
      fi
    fi

    if [ "$show_budget_bar" = "1" ]; then
      budget_bar=1
    else
      budget_text="${budget_color}${budget_icon}${budget_icon:+ }${budget_label}${budget_value}${RESET}"
    fi
  fi
fi

extra_usage_text=""
if [ "$show_extra_usage" = "1" ] && [ "$show_usage" = "1" ]; then
  # Overage spend against the configured limit, sent as a third rate_limits window and only on accounts with extra usage
  # turned on, so it's empty for everyone else. A percentage, not dollars, which is what the ramp and the other two
  # windows speak.
  rl_pct "$payload_spend_limit"; cost_pct=$rl_int

  if [ -n "$cost_pct" ]; then
    if [ "$cost_pct" -le 10 ]; then
      cost_color="$LEVEL_1"
    elif [ "$cost_pct" -le 20 ]; then
      cost_color="$LEVEL_2"
    elif [ "$cost_pct" -le 30 ]; then
      cost_color="$LEVEL_3"
    elif [ "$cost_pct" -le 40 ]; then
      cost_color="$LEVEL_4"
    elif [ "$cost_pct" -le 50 ]; then
      cost_color="$LEVEL_5"
    elif [ "$cost_pct" -le 60 ]; then
      cost_color="$LEVEL_6"
    elif [ "$cost_pct" -le 70 ]; then
      cost_color="$LEVEL_7"
    elif [ "$cost_pct" -le 80 ]; then
      cost_color="$LEVEL_8"
    elif [ "$cost_pct" -le 90 ]; then
      cost_color="$LEVEL_9"
    else
      cost_color="$LEVEL_10"
    fi
    # Per-element override: extra usage gets its own fixed color when set
    if [ "$color_mode" = "perElement" ] && [ -n "$element_color_extra" ]; then
      hex_to_ansi "$element_color_extra"; cost_color=$ansi
    fi
    if [ "$show_usage_label" = "1" ]; then
      extra_usage_text="${cost_color}E: ${cost_pct}%${RESET}"
    else
      extra_usage_text="${cost_color}${cost_pct}%${RESET}"
    fi
  fi
fi

# ---- Fit the bars to the terminal, then draw them ----
#
# Claude Code exports COLUMNS to the command, so the width is known with no fork and no tty (/dev/tty is "Device not
# configured" under it). Everything that isn't a bar is fixed text, measured below, and the bars split what's left
# equally so they always match. BAR_WIDTH=auto turns it on, a number pins the old fixed width.
#
# The line doesn't get all of COLUMNS. The footer row pads 2 columns each side plus a 1-column gap before a right-hand
# indicator block (IDE selection, PR badge, "focus") that never shrinks... the line does. So 5 come off before anything
# is measured, plus the block's own width when it shows. Ink truncates an overrun rather than wrapping it, so it clips
# the week's reset time, not the layout.

fit_bars() {  # -> bar_width, from COLUMNS less everything that is not a bar
  local cols=${COLUMNS:-} used=0 n=0 elements=0 caps=0 t
  case "$cols" in ''|*[!0-9]*) return ;; esac
  [ -n "$bar_cap_l" ] && caps=2
  for t in "$dir_text" "$repo_text" "$status_text" "$pr_text" "$model_text" "$profile_text" \
           "$context_text" "$cache_text" "$cost_text" "$usage_text" "$weekly_text" \
           "$budget_text" "$extra_usage_text"; do
    [ -n "$t" ] || continue
    plain_width "$t"; used=$((used + pw)); elements=$((elements + 1))
  done
  # Cost is zero till the first response, then a few cells wide, and the flame arrives with that response too. Hold both
  # cells from the start, same reason the window bars' room is held.
  if [ -z "$cost_text" ] && [ "$cost_applies" = 1 ] && [ -n "$payload_cost" ]; then
    used=$((used + 6)); elements=$((elements + 1))
  fi
  if [ -z "$cache_text" ] && [ "$show_cache" = 1 ] && [ -z "$payload_cache_observed" ]; then
    used=$((used + 1)); elements=$((elements + 1))
  fi
  # A bar is its caps plus whatever hangs off the right one: the effort pill, or a window's reset time.
  if [ "$ctx_bar" = 1 ]; then
    plain_width "$ctx_trail"; used=$((used + caps + pw))
    plain_width "$ctx_pill_cap"; used=$((used + pw))
    n=$((n + 1)); elements=$((elements + 1))
  fi
  if [ "$usage_bar" = 1 ]; then
    used=$((used + caps + ${#reset_time_display})); n=$((n + 1)); elements=$((elements + 1))
  elif [ "$show_usage" = 1 ] && [ "$show_bar" = 1 ] && [ "$account_is_subscription" = 1 ] && [ -z "$usage_text" ]; then
    # Not in yet, the first rate_limits arrive with the first response. Hold the room anyway or the context meter opens
    # at most of the row and shrinks to a third a second later. Eight cells covers " 12:02pm".
    used=$((used + caps)); [ "$show_reset" = 1 ] && used=$((used + 8))
    n=$((n + 1)); elements=$((elements + 1))
  fi
  if [ "$weekly_bar" = 1 ]; then
    used=$((used + caps + ${#weekly_reset_display})); n=$((n + 1)); elements=$((elements + 1))
  elif [ "$show_weekly" = 1 ] && [ "$show_usage" = 1 ] && [ "$show_weekly_bar" = 1 ] && [ "$account_is_subscription" = 1 ] && [ -z "$weekly_text" ]; then
    # Twelve covers " Thu 12:02pm".
    used=$((used + caps)); [ "$show_weekly_reset" = 1 ] && used=$((used + 12))
    n=$((n + 1)); elements=$((elements + 1))
  fi
  # No reset time on the budget bar. The week it counts is the calendar's and needs no announcing.
  if [ "$budget_bar" = 1 ]; then
    used=$((used + caps)); n=$((n + 1)); elements=$((elements + 1))
  fi
  [ "$n" -gt 0 ] || return
  [ "$elements" -gt 1 ] && used=$(( used + (elements - 1) * ${#section_separator} ))
  bar_width=$(( (cols - bar_fit_margin - used) / n ))
  [ "$bar_width" -lt "$bar_width_min" ] && bar_width=$bar_width_min
  [ "$bar_width" -gt "$bar_width_max" ] && bar_width=$bar_width_max
}

if [ "$bar_width" = "auto" ]; then
  bar_width=14   # what a shell with no COLUMNS gets, the old fixed default
  fit_bars
fi

if [ "$ctx_bar" = 1 ]; then
  make_bar "$context_pct" "${ctx_label}${ctx_value}" "$context_color" "" "" "$ctx_trail" "$ctx_lead" "$ctx_pill_bg"
  context_text="${bar}${ctx_trail}${ctx_pill_cap}"
  [ -n "$ctx_pill_bg" ] || context_text="${bar}${ctx_trail}${RESET}"
fi
if [ "$usage_bar" = 1 ]; then
  # The pace marker's cell, now the bar has a width. Clock in the first cell, same trick as the model mark: rides inside
  # the bar, takes its coloring, costs no width, can't clash with the fill.
  marker_pos=""
  if [ -n "$elapsed_secs" ]; then
    marker_pos=$(( (elapsed_secs * bar_width + 9000) / 18000 ))
    [ "$marker_pos" -gt $((bar_width - 1)) ] && marker_pos=$((bar_width - 1))
  fi
  make_bar "$utilization" "${usage_label}${utilization}" "$usage_color" "$marker_pos" "$pace_color" "$reset_time_display" "$usage_icon"
  usage_text="${bar}${usage_color}${reset_time_display}${RESET}"
fi
if [ "$weekly_bar" = 1 ]; then
  w_marker_pos=""
  if [ -n "$w_elapsed" ]; then
    w_marker_pos=$(( (w_elapsed * bar_width + 302400) / 604800 ))
    [ "$w_marker_pos" -gt $((bar_width - 1)) ] && w_marker_pos=$((bar_width - 1))
  fi
  make_bar "$weekly_util" "${weekly_label}${weekly_util}" "$weekly_color" "$w_marker_pos" "$w_pace_color" "$weekly_reset_display" "$weekly_icon"
  weekly_text="${bar}${weekly_color}${weekly_reset_display}${RESET}"
fi
if [ "$budget_bar" = 1 ]; then
  b_marker_pos=$(( (b_marker_frac * bar_width + 302400) / 604800 ))
  [ "$b_marker_pos" -gt $((bar_width - 1)) ] && b_marker_pos=$((bar_width - 1))
  [ "$b_marker_pos" -lt 0 ] && b_marker_pos=0
  make_bar "$budget_pct" "${budget_label}${budget_value}" "$budget_color" "$b_marker_pos" "$b_pace_color" "" "$budget_icon"
  budget_text="${bar}${RESET}"
fi

output=""
# What goes between sections. Each element carries its own color, so this only has to breathe, not fence.
case "$section_separator" in
  *[!\ ]*) separator="${GRAY}${section_separator}${RESET}" ;;
  *)        separator="$section_separator" ;;   # all whitespace, nothing to color
esac

# Order: where you are (folder, repo, status), whose account this is, then what it's running (model, context) and what's
# left of it (S, W, budget). The account leads that run because everything after it belongs to it.
[ -n "$dir_text" ] && output="${dir_text}"

# Then the repo being worked on, not always the one the cwd is in
if [ -n "$repo_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${repo_text}"
fi

# Then whether that repo is dirty
if [ -n "$status_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${status_text}"
fi

# Then its open pull request
if [ -n "$pr_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${pr_text}"
fi

# Then the account
if [ -n "$profile_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${profile_text}"
fi

# Then model
if [ -n "$model_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${model_text}"
fi

# Then context
if [ -n "$context_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${context_text}"
fi

# Then the prompt cache that context is riding on
if [ -n "$cache_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${cache_text}"
fi

# Then what this session has cost, ahead of the window it was spent in
if [ -n "$cost_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${cost_text}"
fi

# Finally usage
if [ -n "$usage_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${usage_text}"
fi

# Then weekly usage
if [ -n "$weekly_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${weekly_text}"
fi

# Then the week's money, last of the bars because it's the only one that isn't the plan's own accounting
if [ -n "$budget_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${budget_text}"
fi

# Then extra usage
if [ -n "$extra_usage_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${extra_usage_text}"
fi

# ---- Second line: the session's task list, while it has work left ----
#
# Claude Code keeps the list on disk, one file per task under ~/.claude/tasks/<session_id>/, each with a status and an
# activeForm. A meter of done over total in the main bars' width, then the task in progress. Only while something is
# pending or running, so an idle session stays one row. Subagents aren't repeated here... the agent panel below the
# prompt already lists exactly those, in this script's styling.
task_line=""
if [ "$show_tasks" = "1" ] && [ -n "$payload_session" ] && [ -d "$HOME/.claude/tasks/$payload_session" ]; then
  task_total=0; task_done=0; task_active=""; task_cur=""
  while IFS= read -r tl; do
    case "$tl" in
      "") ;;
      *'"completed"')   task_total=$((task_total + 1)); task_done=$((task_done + 1)) ;;
      *'"in_progress"') task_total=$((task_total + 1)); [ -n "$task_active" ] || task_active=${tl%%:*} ;;
      *)                task_total=$((task_total + 1)) ;;
    esac
  done <<EOF
$(grep -oH '"status": *"[^"]*"' "$HOME/.claude/tasks/$payload_session"/*.json 2>/dev/null)
EOF
  if [ "$task_total" -gt 0 ] && [ "$task_done" -lt "$task_total" ]; then
    if [ -n "$task_active" ] && [ -r "$task_active" ]; then
      while IFS= read -r tl; do
        case "$tl" in
          *'"activeForm":'*) tl=${tl#*\"activeForm\":}; tl=${tl#*\"}; task_cur=${tl%\"*}; break ;;
        esac
      done < "$task_active"
    fi
    hex_to_ansi "$task_color"; task_ansi=$ansi
    make_bar $(( task_done * 100 / task_total )) "${task_done}/${task_total}" "$task_ansi" "" "" "" "$task_icon" ""
    task_line="$bar"
    if [ -n "$task_cur" ]; then
      plain_width "$task_line"
      task_avail=$(( ${COLUMNS:-140} - bar_fit_margin - pw - 2 ))
      if [ "$task_avail" -gt 1 ] && [ ${#task_cur} -gt "$task_avail" ]; then task_cur="${task_cur:0:$((task_avail - 1))}…"; fi
      [ "$task_avail" -gt 1 ] && task_line="${task_line}  ${GRAY}${task_cur}${RESET}"
    fi
  fi
fi

printf "%s\n" "$output"
if [ -n "$task_line" ]; then
  printf "%s\n" "$task_line"
fi

# Exit 0 explicitly. Claude Code throws away the output of a status line that fails, and the last statement's status is
# the script's. Written as `[ -n "$task_line" ] && printf ...` this exited 1 on every render with no task line, which is
# most of them, and the whole line vanished.
exit 0
