# claude-statusline

Minimal Claude Code statusline with usage bars and rate limit tracking.

<!-- TODO: Add screenshot here -->

## What It Shows
<img width="730" height="128" alt="CleanShot 2569-03-09 at 09 52 49@2x" src="https://github.com/user-attachments/assets/bc9aae8e-209c-4a10-a656-aeb190aff8fa" />

- **Line 1** - Model name, your plan (e.g. Ultra, Max) and context window usage
- **Current** - 5-hour session limit with reset time, only on plans that still have one (the $200 Ultra plan doesn't)
- **Weekly** - 7-day limit with reset time, plus a per-model weekly line (e.g. Fable) once you use it

Usage comes from the same endpoint Claude Code's `/usage` reads. One session refreshes it at a time, at most every 2 minutes, and backs off 5 minutes after a failure; if it can't refresh for 10 minutes the statusline says how old the numbers are.

## Check

```bash
bash ~/.claude/statusline.sh --check
```

Shows your plan, a live call to the usage endpoint (HTTP status), which limits your plan has, and a sample render.

## Install

```bash
npx @andrewii23/claude-statusline
```

This will:
1. Back up your existing statusline (if any)
2. Copy the statusline script to `~/.claude/statusline.sh`
3. Update `~/.claude/settings.json` with the statusline config

Restart Claude Code to see the statusline.

## Uninstall

```bash
npx @andrewii23/claude-statusline --uninstall
```

Restores your previous statusline from backup if available.

## Manual Install

```bash
git clone https://github.com/andrewii23/claude-statusline.git
cp claude-statusline/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  }
}
```

## Requirements

- [jq](https://jqlang.github.io/jq/) - JSON parser
- [curl](https://curl.se/) - For fetching usage data
- Claude Code with OAuth login (for rate limit data)

macOS: `brew install jq`

## License

MIT
