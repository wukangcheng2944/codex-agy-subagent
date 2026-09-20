# Codex-AGY Subagent & Sidebar Zero-Polling Suite

Seamlessly integrate **Google Antigravity (AGY)** into **OpenAI Codex** as a native subagent and sidebar assistant with **100% zero status polling (event-driven reactive wakeup)**.

---

## ⚡ 1-Line Quick Install

Run this command in **PowerShell** on any target machine (including `chengpc`):

```powershell
irm https://raw.githubusercontent.com/wukangcheng2944/codex-agy-subagent/main/install.ps1 | iex
```

Or clone and run locally:

```powershell
git clone https://github.com/wukangcheng2944/codex-agy-subagent.git
cd codex-agy-subagent
pwsh -ExecutionPolicy Bypass -File .\install.ps1
```

---

## 🚀 What This Does

1. **MCP Native Subagent (`agy_subagent`)**:
   - Registered in `~/.codex/config.toml`.
   - Allows Codex to invoke AGY inline, waiting for structured JSON report in a single turn without polling loops.

2. **Sidebar Terminal Dispatch (`agy-sidebar` / `agy_sidebar_dispatch`)**:
   - Supports Herdr split pane (`herdr pane split`), Windows Terminal (`wt.exe`), and background detached tasks.
   - Instantly returns a loud constraint banner to Codex: **DO NOT POLL STATUS. FINISH TURN IMMEDIATELY.**

3. **Event-Driven Reactive Wakeup**:
   - AGY's runtime `Stop` hook captures the completion report.
   - Resolves target Codex thread via session tracking hook (`SessionStart`).
   - Automatically injects the completion message directly into Codex via `codex queue --thread <ID>`, waking Codex up reactively.

---

## 📁 Repository Structure

```
codex-agy-subagent/
├── install.ps1                 # Universal one-click installer (remote & local)
├── mcp/
│   └── subagent-server.mjs     # MCP Server (implements agy_subagent & agy_sidebar_dispatch)
├── scripts/
│   ├── agy-sidebar.ps1         # Sidebar & detached process dispatcher
│   ├── agy-sidebar.cmd         # Windows CMD wrapper for agy-sidebar
│   ├── notify-codex.ps1        # AGY Stop hook -> codex queue event bridge
│   ├── notify-codex.cmd        # Windows CMD wrapper for notify-codex
│   ├── codex-session-record.ps1# Codex SessionStart hook -> active-codex-thread.txt
│   └── codex-session-record.cmd# Windows CMD wrapper for session recording
└── rules/
    └── agy-subagent.md         # Behavioral rules for Codex (strict anti-polling mandate)
```

---

## 🛠 Manual Verification

After installation, verify with:

```powershell
# 1. Check MCP Registration
codex mcp list

# 2. Test Sidebar Dispatch
agy-sidebar -Task "Hello from AGY" -Mode "plan" -Effort "low"
```
