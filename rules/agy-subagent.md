# AGY Subagent & Sidebar Terminal Usage Guidelines

This workspace is integrated with Google Antigravity (AGY) as an autonomous subagent system.

## 0. CRITICAL: Mode Selection by Context (STRICT RULE)

### 🔴 Scenario 1: Inside `/goal` Mode, Autonomous Loops, or Multi-Step Tasks
- **MANDATORY**: **ALWAYS use Mode B (`agy_subagent`)!**
- **STRICTLY PROHIBITED**: **NEVER use Mode A (`agy-sidebar` or `agy_sidebar_dispatch`) in Goal mode!**
- **WHY**:
  The `/goal` harness executes autonomously turn-by-turn. If you dispatch a task asynchronously in the background, the Goal loop **does NOT pause**; instead, it immediately launches the next turn, repeatedly burning reasoning tokens and quota while printing "waiting for hook", eventually timing out or falsely declaring the goal "blocked".
- **CORRECT USAGE**:
  Call `agy_subagent(task="...", mode="accept-edits", effort="high")`.
  The tool executes synchronously while your model reasoning is paused (consuming 0 thinking tokens). When it completes, the result is returned in the exact same turn, allowing you to complete or advance the goal in 1 single step.

---

### 🟢 Scenario 2: Interactive Human Chat (Default)
When you are in normal chat with a human user (NOT `/goal` mode):
- **When the user explicitly asks for "sidebar", "终端分屏", "后台执行", or wants to watch AGY run visually**:
  Use **Mode A (`agy-sidebar` / `agy_sidebar_dispatch`)**.
  - **STRICT ANTI-POLLING RULE**:
    - **DO NOT POLL FOR STATUS**: Do NOT execute `while` sleep loops, `Get-Process` checks, or repeated status commands.
    - **AUTOMATIC REACTIVE WAKEUP**: AGY's runtime Stop hook automatically pushes results into this thread via `codex queue`.
    - **END TURN IMMEDIATELY**: After dispatching, acknowledge and immediately stop calling tools.
- **For all other general delegation**:
  Use **Mode B (`agy_subagent`)**.

---

## 1. Execution Modes Specification

### Mode A: Sidebar Terminal Dispatch (Only for Interactive Human Sessions)
- **Terminal Command**:
  ```powershell
  agy-sidebar -Task "<detailed task description>" [-Mode accept-edits|plan] [-Effort high|medium|low]
  ```
- **MCP Tool**:
  ```json
  agy_sidebar_dispatch({ "task": "<detailed task description>" })
  ```

### Mode B: Synchronous Inline Subagent Call (Required for `/goal` Mode)
- **MCP Tool**:
  ```json
  agy_subagent({ "task": "<detailed task description>", "mode": "accept-edits", "effort": "high" })
  ```
- Blocks synchronously until AGY finishes. Consumes 0 thinking tokens while waiting. Returns complete diff and execution summary in the same turn.
