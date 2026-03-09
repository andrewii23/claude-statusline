# claude-statusline

Minimal Claude Code statusline with usage bars and rate limit tracking.

<!-- TODO: Add screenshot here -->

## What It Shows
<img width="830" height="132" alt="CleanShot 2569-03-09 at 09 26 17@2x" src="https://github.com/user-attachments/assets/30325f24-05b9-48a3-a4cb-3d61f1118e12" />

- **Line 1** - Model name and context window usage
- **Line 2** - Current (5-hour) rate limit with reset time
- **Line 3** - Weekly (7-day) rate limit with reset time

## Install

```bash
npx @anthropic-ii23/claude-statusline
```

This will:
1. Back up your existing statusline (if any)
2. Copy the statusline script to `~/.claude/statusline.sh`
3. Update `~/.claude/settings.json` with the statusline config

Restart Claude Code to see the statusline.

## Uninstall

```bash
npx @anthropic-ii23/claude-statusline --uninstall
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
