#!/usr/bin/env bash
# Points Claude Code's status line at statusline.sh from this checkout.
#   ./install.sh                    asks which segments to show (all if not a terminal)
#   ./install.sh --segments LIST    shows LIST, e.g. model,context,cost
#   ./install.sh --all              shows every segment without asking
#   ./install.sh --refresh SECONDS  redraws every SECONDS so countdowns stay live
#                                   (default 60, 0 redraws only after each message)
#   ./install.sh --uninstall        removes the statusLine entry
# Each run keeps a backup of settings.json. CLAUDE_CONFIG_DIR overrides
# ~/.claude, as it does for Claude Code.

set -euo pipefail

ALL_SEGMENTS=(model effort branch context cost cache lines duration 5h 7d)
declare -A DESCRIPTIONS=(
  [model]="model name               Opus 5.5"
  [effort]="reasoning effort         high"
  [branch]="git branch               git main"
  [context]="context window           ctx ████░░░░░░ 42% 84k/200k"
  [cost]="session cost (API price) ~\$1.23"
  [cache]="prompt cache time left   cache 4m"
  [lines]="lines added / removed    +120 -34"
  [duration]="session duration         up 25m"
  [5h]="5-hour plan limit        5h ████████░░ 83% resets 2h10 full in ~34m"
  [7d]="weekly plan limit        7d ██████░░░░ 55% resets 3d11h"
)

usage() { sed -n '2,10s/^# \{0,1\}//p' "$0"; }

mode=install segments='' refresh=60
while (( $# )); do
  case $1 in
    --uninstall) mode=uninstall ;;
    --all) segments=$(IFS=,; echo "${ALL_SEGMENTS[*]}") ;;
    --segments) segments=${2:?--segments needs a list, e.g. model,context}; shift ;;
    --segments=*) segments=${1#*=} ;;
    --refresh) refresh=${2:?--refresh needs a number of seconds}; shift ;;
    --refresh=*) refresh=${1#*=} ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

command -v jq >/dev/null || { echo "jq is required: https://jqlang.org/download/" >&2; exit 1; }
[[ $refresh =~ ^[0-9]+$ ]] || { echo "--refresh needs a whole number of seconds" >&2; exit 1; }

config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
settings=$config_dir/settings.json
script=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/statusline.sh

if [[ $mode == install ]]; then
  if [[ -n $segments ]]; then
    for name in ${segments//,/ }; do
      [[ " ${ALL_SEGMENTS[*]} " == *" $name "* ]] \
        || { echo "Unknown segment: $name (known: ${ALL_SEGMENTS[*]})" >&2; exit 1; }
    done
  elif [[ -t 0 ]]; then
    echo "Which segments should the status line show? [Y/n]"
    chosen=()
    for name in "${ALL_SEGMENTS[@]}"; do
      read -r -p "  ${DESCRIPTIONS[$name]}  " answer
      [[ $answer =~ ^[Nn] ]] || chosen+=("$name")
    done
    (( ${#chosen[@]} )) || { echo "No segment chosen, nothing installed." >&2; exit 1; }
    segments=$(IFS=,; echo "${chosen[*]}")
  else
    segments=$(IFS=,; echo "${ALL_SEGMENTS[*]}")
  fi
fi

mkdir -p "$config_dir"
[[ -s $settings ]] || echo '{}' > "$settings"

backup=$settings.bak.$(date +%Y%m%d%H%M%S)
cp "$settings" "$backup"

tmp=$(mktemp "$settings.XXXXXX")
trap 'rm -f "$tmp"' EXIT

if [[ $mode == uninstall ]]; then
  jq 'del(.statusLine)' "$settings" > "$tmp"
  mv "$tmp" "$settings"
  echo "Status line removed from $settings (backup: $backup)"
  exit 0
fi

chmod +x "$script"
command=$(printf '%q --segments %s' "$script" "$segments")
jq --arg cmd "$command" --argjson refresh "$refresh" '
  .statusLine = {type: "command", command: $cmd, padding: 0}
  | if $refresh > 0 then .statusLine.refreshInterval = $refresh else . end
' "$settings" > "$tmp"
mv "$tmp" "$settings"
echo "Status line installed in $settings (backup: $backup)"
echo "Segments: $segments"
if (( refresh > 0 )); then
  echo "Redrawn every ${refresh}s"
else
  echo "Redrawn after each message"
fi
echo "It shows up on the next prompt of any running Claude Code session."
