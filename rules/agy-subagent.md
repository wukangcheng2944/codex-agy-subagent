# AGY Subagent & Sidebar Terminal Usage Guidelines

This workspace is integrated with Google Antigravity (AGY) as an autonomous subagent system.

## 1. Execution Modes

### Mode A: Sidebar Terminal Dispatch (Event-Driven & Zero-Polling)
When the user asks to run AGY in the sidebar terminal (or for long-running / detached tasks):
- **Command**: Run in terminal:
  ```powershell
  agy-sidebar -Task "<detailed task description>" [-Mode accept-edits|plan] [-Effort high|medium|low]
  ```
  Or call MCP tool:
  ```json
  agy_sidebar_dispatch({ "task": "<detailed task description>" })
  ```
- **STRICT ANTI-POLLING RULE**:
  - **DO NOT POLL FOR STATUS**: Do NOT execute `while` sleep loops, `Get-Process` checks, or repeated status commands.
  - **AUTOMATIC REACTIVE WAKEUP**: AGY's runtime Stop hook automatically captures execution output and pushes it back into this Codex thread via `codex queue`.
  - **END TURN IMMEDIATELY**: After launching `agy-sidebar`, briefly acknowledge the task has started in the sidebar terminal, and immediately stop calling tools to conclude your turn.

### Mode B: Synchronous Inline Subagent Call
When the user wants Codex to wait for the AGY result inline:
- **MCP Tool**: Call `agy_subagent(task="...", mode="accept-edits", effort="high")`.
- The tool will execute and return the final JSON result in a single turn without prompt-level polling.
