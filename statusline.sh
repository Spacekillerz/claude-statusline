#!/usr/bin/env bash
# Compact status line for Claude Code.
# Reads the session JSON that Claude Code writes on stdin and prints one line:
#   Opus 5.5 · high · ⎇ main · ctx ████░░░░░░ 42% 84k/200k · ~$1.23 · 5h 18% ↻2h10 · 7d 40%
#
# Settings (environment variables):
#   CLAUDE_STATUSLINE_SEGMENTS   segments to show, in order
#                                (default "model,effort,branch,context,cost,5h,7d")
#   CLAUDE_STATUSLINE_WARN       percentage where a gauge turns yellow (default 50)
#   CLAUDE_STATUSLINE_CRIT       percentage where a gauge turns red    (default 80)
#   CLAUDE_STATUSLINE_SEP        separator between segments            (default " · ")
#   CLAUDE_STATUSLINE_BAR_WIDTH  cells in the context bar, 0 hides it  (default 10)
#   NO_COLOR                     any value disables colors
#
# `--segments LIST` on the command line overrides CLAUDE_STATUSLINE_SEGMENTS.

set -u

SEGMENTS=${CLAUDE_STATUSLINE_SEGMENTS:-model,effort,branch,context,cost,5h,7d}
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
      (.workspace.current_dir // .cwd // "")
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

# Time left until an epoch timestamp: 2h10, 45m, 3d4h.
until_reset() {
  local left=$(( $1 - $(date +%s) ))
  (( left <= 0 )) && return
  local d=$(( left / 86400 )) h=$(( left % 86400 / 3600 )) m=$(( left % 3600 / 60 ))
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
  printf '%s' "${DIM}⎇${RESET} ${MAGENTA}${branch}${RESET}"
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

limit_segment() {
  local label=$1 pct=$2 reset=$3 seg left
  [[ -n $pct ]] || return
  seg="${DIM}${label}${RESET} $(gauge_color "$pct")${pct}%${RESET}"
  if [[ -n $reset ]]; then
    left=$(until_reset "$reset")
    [[ -n $left ]] && seg+=" ${DIM}↻${left}${RESET}"
  fi
  printf '%s' "$seg"
}

segment_5h() { limit_segment 5h "$five_pct" "$five_reset"; }
segment_7d() { limit_segment 7d "$week_pct" "$week_reset"; }

out=''
IFS=', ' read -r -a wanted <<<"$SEGMENTS"
for name in "${wanted[@]}"; do
  [[ $name =~ ^(model|effort|branch|context|cost|5h|7d)$ ]] || continue
  s=$("segment_$name")
  [[ -n $s ]] || continue
  [[ -n $out ]] && out+="${DIM}${SEP}${RESET}"
  out+=$s
done
printf '%s\n' "$out"
