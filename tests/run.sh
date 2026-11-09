#!/usr/bin/env bash
# Feeds sample session JSON to statusline.sh and checks the printed line.
set -u

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
export NO_COLOR=1
now=$(date +%s)
failures=0

# check NAME JSON EXPECTED [statusline.sh arguments...]
check() {
  local name=$1 json=$2 expected=$3 actual
  shift 3
  actual=$(./statusline.sh "$@" <<<"$json")
  if [[ $actual == "$expected" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    echo "     expected: $expected"
    echo "     actual:   $actual"
    failures=$((failures + 1))
  fi
}

check "full session" "$(cat <<EOF
{"model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},
 "effort":{"level":"high"},
 "cost":{"total_cost_usd":1.2345},
 "context_window":{"context_window_size":200000,"used_percentage":42,
   "current_usage":{"input_tokens":4000,"cache_creation_input_tokens":20000,"cache_read_input_tokens":60000,"output_tokens":500}},
 "rate_limits":{"five_hour":{"used_percentage":83.4,"resets_at":$((now + 7830))},
                "seven_day":{"used_percentage":55,"resets_at":$((now + 300030))}}}
EOF
)" "Opus 5.5 · high · ctx ████░░░░░░ 42% 84k/200k · ~\$1.23 · 5h ████████░░ 83% ↻2h10 · 7d ██████░░░░ 55% ↻3d11h"

check "percentage derived from tokens" \
  '{"model":{"display_name":"Sonnet 5.5"},"context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":250000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}' \
  "Sonnet 5.5 · ctx ███░░░░░░░ 25% 250k/1M"

check "no rate limits, no effort" \
  '{"model":{"display_name":"Haiku 5.5"},"cost":{"total_cost_usd":0}}' \
  "Haiku 5.5 · ~\$0.00"

check "expired reset hides countdown" \
  "{\"model\":{\"display_name\":\"Opus 5.5\"},\"rate_limits\":{\"five_hour\":{\"used_percentage\":10,\"resets_at\":$((now - 60))}}}" \
  "Opus 5.5 · 5h █░░░░░░░░░ 10%"

check "invalid input prints an empty line" 'not json' ""

session='{"model":{"display_name":"Opus 5.5"},"effort":{"level":"high"},"cost":{"total_cost_usd":2},"context_window":{"used_percentage":90},"rate_limits":{"seven_day":{"used_percentage":12}}}'

check "--segments picks and orders segments" "$session" \
  "~\$2.00 · ctx █████████░ 90%" --segments cost,context

check "--segments= form" "$session" "ctx █████████░ 90%" --segments=context

check "unknown segment names are ignored" "$session" "Opus 5.5 · 7d █░░░░░░░░░ 12%" --segments model,weekly,7d

check "a chosen segment without data is skipped" \
  '{"model":{"display_name":"Opus 5.5"}}' "Opus 5.5" --segments 5h,model

CLAUDE_STATUSLINE_SEGMENTS="effort, cost" \
  check "CLAUDE_STATUSLINE_SEGMENTS, spaces allowed" "$session" "high · ~\$2.00"

repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q -b feature/demo
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir "$repo/sub"

check "branch of the session directory" \
  "{\"model\":{\"display_name\":\"Opus 5.5\"},\"workspace\":{\"current_dir\":\"$repo/sub\"}}" \
  "Opus 5.5 · ⎇ feature/demo"

git -C "$repo" checkout -q --detach
check "detached HEAD shows the short commit" \
  "{\"workspace\":{\"current_dir\":\"$repo\"}}" \
  "⎇ $(git -C "$repo" rev-parse --short HEAD)" --segments branch

check "no branch outside a git repository" \
  '{"model":{"display_name":"Opus 5.5"},"workspace":{"current_dir":"/"}}' "Opus 5.5"

CLAUDE_STATUSLINE_BAR_WIDTH=0 \
  check "bar width 0 hides every bar" "$session" "ctx 90% · 7d 12%" --segments context,7d

if (( failures > 0 )); then
  echo "$failures failing"
  exit 1
fi
echo "all tests passed"
