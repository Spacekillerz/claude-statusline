#!/usr/bin/env bash
# Compact status line for Claude Code.
# Reads the session JSON that Claude Code writes on stdin and prints one line:
#   Opus 5.5 · high · git main · ctx ████░░░░░░ 42% 84k/200k · ~$1.23 · cache 4m · +120 -34 · up 25m
#   · 5h ████████░░ 78% resets 1h40 full in ~45m · 7d ████░░░░░░ 40% resets 3d11h
#
# Settings (environment variables):
#   CLAUDE_STATUSLINE_SEGMENTS       segments to show, in order (default
#                                    "model,effort,branch,context,cost,cache,lines,duration,5h,7d")
#   CLAUDE_STATUSLINE_WARN           percentage where a gauge turns yellow (default 50)
#   CLAUDE_STATUSLINE_CRIT           percentage where a gauge turns red    (default 80)
#   CLAUDE_STATUSLINE_FORECAST_FROM  usage percentage from which 5h/7d warn when the
#                                    current pace hits the limit before it resets;
#                                    101 turns the forecast off             (default 70)
#   CLAUDE_STATUSLINE_SEP            separator between segments            (default " · ")
#   CLAUDE_STATUSLINE_BAR_WIDTH      cells in each bar, 0 hides the bars  (default 10)
#   NO_COLOR                         any value disables colors
#
# `--segments LIST` on the command line overrides CLAUDE_STATUSLINE_SEGMENTS.

set -u

SEGMENTS=${CLAUDE_STATUSLINE_SEGMENTS:-model,effort,branch,context,cost,cache,lines,duration,5h,7d}
while (( $# )); do
  case $1 in
    --segments) SEGMENTS=${2:-}; shift 2 || shift ;;
    --segments=*) SEGMENTS=${1#*=}; shift ;;
    *) shift ;;
  esac
done

WARN=${CLAUDE_STATUSLINE_WARN:-50}
CRIT=${CLAUDE_STATUSLINE_CRIT:-80}
SEP=${CLAUDE_STATUSLINE_SEP:- · }
BAR_WIDTH=${CLAUDE_STATUSLINE_BAR_WIDTH:-10}
FORECAST_FROM=${CLAUDE_STATUSLINE_FORECAST_FROM:-70}
NOW=${CLAUDE_STATUSLINE_NOW:-$(date +%s)}

if [[ -n ${NO_COLOR:-} ]]; then
  RESET='' DIM='' BOLD='' GREEN='' YELLOW='' RED='' CYAN='' MAGENTA=''
else
  RESET=$'\e[0m' DIM=$'\e[2m' BOLD=$'\e[1m'
  GREEN=$'\e[32m' YELLOW=$'\e[33m' RED=$'\e[31m' CYAN=$'\e[36m' MAGENTA=$'\e[35m'
fi

input=$(cat)

# One jq pass, one field per line; an empty line means "not provided".
{
  IFS= read -r model
  IFS= read -r effort
  IFS= read -r ctx_pct
  IFS= read -r ctx_used
  IFS= read -r ctx_size
  IFS= read -r cost
  IFS= read -r five_pct
  IFS= read -r five_reset
  IFS= read -r week_pct
  IFS= read -r week_reset
  IFS= read -r cwd
  IFS= read -r added
  IFS= read -r removed
  IFS= read -r duration_ms
  IFS= read -r cache_warm
  IFS= read -r cache_expires
} < <(jq -r '
  def num: if type == "number" then . else null end;
  def rnd: if type == "number" then round else null end;
  def flr: if type == "number" then floor else null end;
  (.context_window // {}) as $c
  | $c.current_usage as $u
  | (if $u == null then null
     else (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0)
           + ($u.cache_read_input_tokens // 0)) end) as $used
  | [
      (.model.display_name // .model.id // ""),
      (.effort.level // ""),
      ($c.used_percentage
        // (if ($used != null and ($c.context_window_size // 0) > 0)
            then $used * 100 / $c.context_window_size else null end)
        | rnd),
      ($used | num),
      ($c.context_window_size | num),
      (.cost.total_cost_usd | num),
      (.rate_limits.five_hour.used_percentage | rnd),
      (.rate_limits.five_hour.resets_at | flr),
      (.rate_limits.seven_day.used_percentage | rnd),
      (.rate_limits.seven_day.resets_at | flr),
      (.workspace.current_dir // .cwd // ""),
      (.cost.total_lines_added | flr),
      (.cost.total_lines_removed | flr),
      (.cost.total_duration_ms | flr),
      (.prompt_cache.warm | if type == "boolean" then . else null end),
      (.prompt_cache.expires_at | flr)
    ]
  | map(if . == null then "" else tostring end)
  | .[]
' <<<"$input" 2>/dev/null)

gauge_color() {
  local pct=$1
  if (( pct >= CRIT )); then printf '%s' "$RED"
  elif (( pct >= WARN )); then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"
  fi
}

human_tokens() {
  local n=$1
  if (( n >= 1000000 )); then
    awk -v n="$n" 'BEGIN { s = sprintf("%.1f", n / 1000000); sub(/\.0$/, "", s); print s "M" }'
  elif (( n >= 1000 )); then
    printf '%dk' $(( (n + 500) / 1000 ))
  else
    printf '%d' "$n"
  fi
}

progress_bar() {
  local pct=$1 color=$2 filled bar=''
  (( pct > 100 )) && pct=100
  filled=$(( (pct * BAR_WIDTH + 50) / 100 ))
  local i
  for (( i = 0; i < BAR_WIDTH; i++ )); do
    (( i == filled )) && bar+="${RESET}${DIM}"
    if (( i < filled )); then bar+='█'; else bar+='░'; fi
  done
  printf '%s%s%s' "$color" "$bar" "$RESET"
}

# A number of seconds as 3d4h, 2h10 or 45m.
format_duration() {
  local s=$1
  local d=$(( s / 86400 )) h=$(( s % 86400 / 3600 )) m=$(( s % 3600 / 60 ))
  if (( d > 0 )); then printf '%dd%dh' "$d" "$h"
  elif (( h > 0 )); then printf '%dh%02d' "$h" "$m"
  else printf '%dm' "$m"
  fi
}

segment_model() {
  [[ -n $model ]] && printf '%s' "${BOLD}${CYAN}${model}${RESET}"
}

segment_effort() {
  [[ -n $effort ]] || return
  local color
  case $effort in
    max|xhigh) color=$MAGENTA ;;
    high) color=$CYAN ;;
    *) color=$DIM ;;
  esac
  printf '%s' "${color}${effort}${RESET}"
}

# --no-optional-locks: the status line runs after every message and must never
# hold the index lock while the user or Claude runs git in the same repo.
segment_branch() {
  [[ -n $cwd && -d $cwd ]] || return
  local branch
  branch=$(git --no-optional-locks -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null) \
    || branch=$(git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null) \
    || return
  printf '%s' "${DIM}git${RESET} ${MAGENTA}${branch}${RESET}"
}

segment_context() {
  [[ -n $ctx_pct ]] || return
  local color seg
  color=$(gauge_color "$ctx_pct")
  seg="${DIM}ctx${RESET}"
  (( BAR_WIDTH > 0 )) && seg+=" $(progress_bar "$ctx_pct" "$color")"
  seg+=" ${color}${ctx_pct}%${RESET}"
  if [[ -n $ctx_used && -n $ctx_size ]]; then
    seg+=" ${DIM}$(human_tokens "$ctx_used")/$(human_tokens "$ctx_size")${RESET}"
  fi
  printf '%s' "$seg"
}

# On a subscription this is what the session would cost at API prices, hence "~".
segment_cost() {
  [[ -n $cost ]] && printf '%s' "${DIM}~\$$(LC_NUMERIC=C printf '%.2f' "$cost")${RESET}"
}

segment_lines() {
  [[ -n $added || -n $removed ]] || return
  (( ${added:-0} + ${removed:-0} > 0 )) || return
  printf '%s' "${GREEN}+${added:-0}${RESET} ${RED}-${removed:-0}${RESET}"
}

segment_duration() {
  [[ -n $duration_ms ]] || return
  printf '%s' "${DIM}up${RESET} $(format_duration $(( duration_ms / 1000 )))"
}

# While warm, the next message reads the conversation from the prompt cache;
# once cold, it reprocesses the whole context.
segment_cache() {
  [[ -n $cache_warm ]] || return
  local left=0
  [[ -n $cache_expires ]] && left=$(( cache_expires - NOW ))
  if [[ $cache_warm != true ]] || (( left <= 0 )); then
    printf '%s' "${DIM}cache${RESET} ${YELLOW}cold${RESET}"
  elif (( left < 60 )); then
    printf '%s' "${DIM}cache${RESET} ${YELLOW}<1m${RESET}"
  else
    printf '%s' "${DIM}cache${RESET} ${GREEN}$(format_duration "$left")${RESET}"
  fi
}

# The forecast assumes usage keeps the pace it had since the window opened:
# elapsed = window - time left, so pct grew at pct/elapsed per second.
limit_segment() {
  local label=$1 pct=$2 reset=$3 window=$4 seg color left elapsed to_full
  [[ -n $pct ]] || return
  color=$(gauge_color "$pct")
  seg="${DIM}${label}${RESET}"
  (( BAR_WIDTH > 0 )) && seg+=" $(progress_bar "$pct" "$color")"
  seg+=" ${color}${pct}%${RESET}"
  [[ -n $reset ]] || { printf '%s' "$seg"; return; }
  left=$(( reset - NOW ))
  if (( left > 0 )); then
    seg+=" ${DIM}resets $(format_duration "$left")${RESET}"
    elapsed=$(( window - left ))
    if (( pct >= FORECAST_FROM && pct > 0 && pct < 100 && elapsed > 0 )); then
      to_full=$(( (100 - pct) * elapsed / pct ))
      (( to_full < left )) && seg+=" ${RED}full in ~$(format_duration "$to_full")${RESET}"
    fi
  fi
  printf '%s' "$seg"
}

segment_5h() { limit_segment 5h "$five_pct" "$five_reset" 18000; }
segment_7d() { limit_segment 7d "$week_pct" "$week_reset" 604800; }

out=''
IFS=', ' read -r -a wanted <<<"$SEGMENTS"
for name in "${wanted[@]}"; do
  [[ $name =~ ^(model|effort|branch|context|cost|cache|lines|duration|5h|7d)$ ]] || continue
  s=$("segment_$name")
  [[ -n $s ]] || continue
  [[ -n $out ]] && out+="${DIM}${SEP}${RESET}"
  out+=$s
done
printf '%s\n' "$out"
