#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const homeDir = require("os").homedir();
const claudeDir = path.join(homeDir, ".claude");
const settingsFile = path.join(claudeDir, "settings.json");
const statuslineTarget = path.join(claudeDir, "statusline.sh");
const backupFile = path.join(claudeDir, "statusline.sh.backup");
const statuslineSrc = path.join(__dirname, "..", "statusline.sh");

const isUninstall = process.argv.includes("--uninstall");

if (isUninstall) {
  console.log("\nUninstalling claude-statusline...\n");

  if (fs.existsSync(backupFile)) {
    fs.copyFileSync(backupFile, statuslineTarget);
    fs.unlinkSync(backupFile);
    console.log("  Restored previous statusline from backup");
  } else if (fs.existsSync(statuslineTarget)) {
    fs.unlinkSync(statuslineTarget);
    console.log("  Removed statusline script");
  }

  if (fs.existsSync(settingsFile)) {
    try {
      const settings = JSON.parse(fs.readFileSync(settingsFile, "utf8"));
      if (settings.statusLine) {
        delete settings.statusLine;
        fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + "\n");
        console.log("  Removed statusline config from settings.json");
      }
    } catch (e) {}
  }

  console.log("\n  Done!\n");
  process.exit(0);
}

console.log("\nInstalling claude-statusline...\n");

if (!fs.existsSync(claudeDir)) {
  fs.mkdirSync(claudeDir, { recursive: true });
}

if (fs.existsSync(statuslineTarget)) {
  fs.copyFileSync(statuslineTarget, backupFile);
  console.log("  Backed up existing statusline to ~/.claude/statusline.sh.backup");
}

fs.copyFileSync(statuslineSrc, statuslineTarget);
fs.chmodSync(statuslineTarget, 0o755);
console.log("  Installed statusline script to ~/.claude/statusline.sh");

let settings = {};
if (fs.existsSync(settingsFile)) {
  try {
    settings = JSON.parse(fs.readFileSync(settingsFile, "utf8"));
  } catch (e) {
    settings = {};
  }
}

settings.statusLine = {
  type: "command",
  command: "bash ~/.claude/statusline.sh",
};

fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + "\n");
console.log("  Updated ~/.claude/settings.json with statusline config");

console.log("\n  Done! Restart Claude Code to see the statusline.\n");
