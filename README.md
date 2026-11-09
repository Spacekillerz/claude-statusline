# claude-statusline

A compact, colored status line for [Claude Code](https://code.claude.com/docs/en/overview)
that shows what `/usage` tells you without typing it:

```
Opus 5.5 · high · ⎇ main · ctx ████░░░░░░ 42% 84k/200k · ~$1.23 · 5h ████████░░ 83% ↻2h10 · 7d ██████░░░░ 55% ↻3d11h
```

| Name      | Looks like                    | Meaning                                                         |
|-----------|-------------------------------|-----------------------------------------------------------------|
| `model`   | `Opus 5.5`                    | current model                                                   |
| `effort`  | `high`                        | reasoning effort (only for models that support it)              |
| `branch`  | `⎇ main`                      | git branch of the session's directory, or commit if detached    |
| `context` | `ctx ████░░░░░░ 42% 84k/200k` | context window used: bar, percentage, tokens used / window size |
| `cost`    | `~$1.23`                      | session cost at API prices (see below)                          |
| `5h`      | `5h ████████░░ 83% ↻2h10`     | 5-hour usage limit consumed: bar, percentage, time until reset  |
| `7d`      | `7d ██████░░░░ 55% ↻3d11h`    | weekly usage limit consumed: bar, percentage, time until reset  |

Percentages are green below 50 %, yellow from 50 %, red from 80 %.
A segment is hidden when Claude Code does not provide its value, for example
the usage limits when you log in with an API key rather than a Pro/Max plan.
You choose which segments to show, and in which order: see
[Choosing segments](#choosing-segments).

## Requirements

- bash 4+
- [jq](https://jqlang.org/download/)
- Claude Code with status line support (tested on 2.1.319)

## Install

```bash
git clone https://github.com/Spacekillerz/claude-statusline.git
cd claude-statusline
./install.sh
```

The installer asks, segment by segment, what you want to see (Enter keeps it,
`n` hides it). It then sets `statusLine` in `~/.claude/settings.json` (or
`$CLAUDE_CONFIG_DIR/settings.json`) to the `statusline.sh` of this checkout,
after saving a timestamped backup next to it. A `git pull` updates the status
line in place; run the installer again to change your choice.

| Command                                | Effect                                        |
|----------------------------------------|-----------------------------------------------|
| `./install.sh`                         | asks which segments to show                   |
| `./install.sh --segments context,cost` | shows only these, in this order, no questions |
| `./install.sh --all`                   | shows every segment, no questions             |
| `./install.sh --uninstall`             | removes the status line                       |

Prefer to do it by hand? Add this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/claude-statusline/statusline.sh --segments model,context,cost",
    "padding": 0
  }
}
```

## Choosing segments

Pass a comma-separated list of segment names (see the table at the top),
in the order you want them:

```bash
statusline.sh --segments context            # ctx ████░░░░░░ 42% 84k/200k
statusline.sh --segments model,context,cost # Opus 5.5 · ctx ████░░░░░░ 42% 84k/200k · ~$1.23
```

Without `--segments`, the list comes from `CLAUDE_STATUSLINE_SEGMENTS`, and
without that, every segment is shown. Unknown names are ignored.

## Configuration

Set these in your shell profile, or in the `env` block of `settings.json`:

| Variable                      | Default | Effect                                 |
|-------------------------------|---------|----------------------------------------|
| `CLAUDE_STATUSLINE_SEGMENTS`  | all     | segments to show, in order             |
| `CLAUDE_STATUSLINE_WARN`      | `50`    | percentage where a gauge turns yellow  |
| `CLAUDE_STATUSLINE_CRIT`      | `80`    | percentage where a gauge turns red     |
| `CLAUDE_STATUSLINE_SEP`       | ` · `   | separator between segments             |
| `CLAUDE_STATUSLINE_BAR_WIDTH` | `10`    | cells in each bar, `0` hides every bar |
| `NO_COLOR`                    | unset   | any value disables colors              |

## About the cost

Claude Code reports `cost.total_cost_usd` for the current session, computed at
API prices. On a Pro or Max subscription, you are not billed that amount: it is
an estimate of what the session would cost through the API, hence the `~`. The
`5h` and `7d` gauges are what counts against your plan.

## How it works

Claude Code runs the status line command after each message and writes the
session state as JSON on its stdin (model, effort, context window, cost,
rate limits…). `statusline.sh` extracts the fields with a single `jq` call and
prints one line. Nothing is sent anywhere and no API is called.

To see the raw JSON your version sends, point `statusLine.command` at
`tee /tmp/statusline.json` for one message.

## Tests

```bash
tests/run.sh
```

## License

[MIT](LICENSE)
