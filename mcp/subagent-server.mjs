#!/usr/bin/env node
/**
 * Codex AGY Native Subagent MCP Server
 * Standard Model Context Protocol (MCP) server over stdio.
 * Exposes AGY as a first-class native subagent to Codex.
 */

import { spawn } from 'child_process';
import readline from 'readline';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const parentDir = path.dirname(__dirname);

const LAUNCHER_PATH = path.join(parentDir, 'Invoke-CodexAGY.ps1');
const CLIENT_CONFIG_PATH = path.join(parentDir, 'client.json');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false
});

function sendResponse(id, result) {
  const msg = {
    jsonrpc: '2.0',
    id,
    result
  };
  process.stdout.write(JSON.stringify(msg) + '\n');
}

function sendError(id, code, message) {
  const msg = {
    jsonrpc: '2.0',
    id,
    error: { code, message }
  };
  process.stdout.write(JSON.stringify(msg) + '\n');
}

function handleInitialize(id, params) {
  sendResponse(id, {
    protocolVersion: '2024-11-05',
    capabilities: {
      tools: {
        listChanged: false
      }
    },
    serverInfo: {
      name: 'agy-subagent',
      version: '1.0.0'
    }
  });
}

function handleToolsList(id) {
  sendResponse(id, {
    tools: [
      {
        name: 'agy_subagent',
        description:
          'Delegate an autonomous software engineering, planning, research, or execution task to the Google Antigravity (AGY) subagent. AGY runs with full codebase capabilities and returns a structured summary and diff without requiring manual polling.',
        inputSchema: {
          type: 'object',
          properties: {
            task: {
              type: 'string',
              description: 'The detailed task prompt or instruction for the AGY subagent.'
            },
            mode: {
              type: 'string',
              enum: ['accept-edits', 'plan'],
              default: 'accept-edits',
              description: "Execution mode: 'accept-edits' to apply code edits, or 'plan' for read-only planning."
            },
            effort: {
              type: 'string',
              enum: ['low', 'medium', 'high'],
              default: 'high',
              description: "Reasoning effort level for the AGY model ('low', 'medium', 'high')."
            },
            conversation_id: {
              type: 'string',
              description: 'Optional existing AGY conversation ID to resume a conversation.'
            },
            workspace: {
              type: 'string',
              description: 'Target working directory for AGY. Defaults to the current workspace root.'
            }
          },
          required: ['task']
        }
      },
      {
        name: 'agy_status',
        description: 'Check connectivity and health of the AGY subagent runtime and local account pool.',
        inputSchema: {
          type: 'object',
          properties: {}
        }
      },
      {
        name: 'agy_sidebar_dispatch',
        description: 'Dispatch an AGY subagent task to the sidebar terminal or detached background process. DOES NOT BLOCK and DOES NOT REQUIRE POLLING. AGY will execute in the sidebar and automatically inject completed results back into this Codex session via an event-driven Stop hook. After calling this tool, Codex should immediately finish its turn without polling.',
        inputSchema: {
          type: 'object',
          properties: {
            task: {
              type: 'string',
              description: 'The task description to delegate to AGY in the sidebar terminal.'
            },
            mode: {
              type: 'string',
              enum: ['accept-edits', 'plan'],
              default: 'accept-edits',
              description: 'Execution mode: accept-edits (read-write) or plan (read-only).'
            },
            effort: {
              type: 'string',
              enum: ['low', 'medium', 'high'],
              default: 'high',
              description: 'Reasoning effort level.'
            },
            direction: {
              type: 'string',
              enum: ['right', 'down'],
              default: 'right',
              description: 'Sidebar split direction if running within Herdr.'
            },
            workspace: {
              type: 'string',
              description: 'Target working directory.'
            }
          },
          required: ['task']
        }
      }
    ]
  });
}

async function handleAgySubagent(args) {
  const task = args.task;
  const mode = args.mode || 'accept-edits';
  const effort = args.effort || 'high';
  const cwd = args.workspace || process.cwd();
  const conversationId = args.conversation_id;

  if (!fs.existsSync(LAUNCHER_PATH)) {
    return {
      content: [
        {
          type: 'text',
          text: `Error: AGY launcher script not found at ${LAUNCHER_PATH}`
        }
      ],
      isError: true
    };
  }

  const agyArgs = [
    '--prompt',
    task,
    '--mode',
    mode,
    '--effort',
    effort,
    '--dangerously-skip-permissions',
    '--output-format',
    'json'
  ];

  if (conversationId) {
    agyArgs.push('--conversation', conversationId);
  }

  return new Promise((resolve) => {
    const psExecutable = fs.existsSync('C:\\Program Files\\PowerShell\\7\\pwsh.exe')
      ? 'C:\\Program Files\\PowerShell\\7\\pwsh.exe'
      : 'pwsh.exe';

    const child = spawn(psExecutable, [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      LAUNCHER_PATH,
      '-DataDirectory',
      parentDir,
      ...agyArgs
    ], {
      cwd,
      env: {
        ...process.env,
        CODEX_THREAD_ID: process.env.CODEX_THREAD_ID || ''
      },
      windowsHide: true
    });

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (data) => {
      stdout += data.toString('utf8');
    });

    child.stderr.on('data', (data) => {
      stderr += data.toString('utf8');
    });

    child.on('error', (err) => {
      resolve({
        content: [
          {
            type: 'text',
            text: `Failed to spawn AGY subagent: ${err.message}`
          }
        ],
        isError: true
      });
    });

    child.on('close', (code) => {
      const output = stdout.trim() || stderr.trim() || `AGY exited with code ${code}`;
      resolve({
        content: [
          {
            type: 'text',
            text: output
          }
        ],
        isError: code !== 0
      });
    });
  });
}

async function handleAgyStatus() {
  let clientInfo = 'Unknown';
  if (fs.existsSync(CLIENT_CONFIG_PATH)) {
    try {
      clientInfo = fs.readFileSync(CLIENT_CONFIG_PATH, 'utf8');
    } catch {}
  }

  return {
    content: [
      {
        type: 'text',
        text: `AGY Subagent Bridge Status:
- Launcher: ${LAUNCHER_PATH} (exists: ${fs.existsSync(LAUNCHER_PATH)})
- Client Config:
${clientInfo}
- Mode: Event-driven + Native Subagent MCP Ready`
      }
    ],
    isError: false
  };
}

async function handleAgySidebarDispatch(args) {
  const task = args.task;
  const mode = args.mode || 'accept-edits';
  const effort = args.effort || 'high';
  const direction = args.direction || 'right';
  const cwd = args.workspace || process.cwd();

  const scriptPath = path.join(parentDir, 'scripts', 'agy-sidebar.ps1');
  const psExecutable = fs.existsSync('C:\\Program Files\\PowerShell\\7\\pwsh.exe')
    ? 'C:\\Program Files\\PowerShell\\7\\pwsh.exe'
    : 'pwsh.exe';

  return new Promise((resolve) => {
    const child = spawn(psExecutable, [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      scriptPath,
      '-Task',
      task,
      '-Mode',
      mode,
      '-Effort',
      effort,
      '-Direction',
      direction,
      '-Workspace',
      cwd
    ], {
      cwd,
      env: {
        ...process.env,
        CODEX_THREAD_ID: process.env.CODEX_THREAD_ID || ''
      },
      windowsHide: true
    });

    let output = '';
    child.stdout.on('data', (d) => { output += d.toString('utf8'); });
    child.stderr.on('data', (d) => { output += d.toString('utf8'); });

    child.on('close', (code) => {
      resolve({
        content: [
          {
            type: 'text',
            text: output.trim() || `AGY subagent dispatched to sidebar (exit code: ${code}).`
          }
        ],
        isError: code !== 0
      });
    });
  });
}

async function handleToolsCall(id, params) {
  const { name, arguments: args } = params;

  try {
    let result;
    if (name === 'agy_subagent') {
      result = await handleAgySubagent(args || {});
    } else if (name === 'agy_sidebar_dispatch') {
      result = await handleAgySidebarDispatch(args || {});
    } else if (name === 'agy_status') {
      result = await handleAgyStatus();
    } else {
      sendError(id, -32601, `Tool not found: ${name}`);
      return;
    }
    sendResponse(id, result);
  } catch (err) {
    sendResponse(id, {
      content: [
        {
          type: 'text',
          text: `Exception in ${name}: ${err.message}\n${err.stack}`
        }
      ],
      isError: true
    });
  }
}

rl.on('line', async (line) => {
  if (!line || !line.trim()) return;

  try {
    const message = JSON.parse(line);

    // Notifications (no id)
    if (message.id === undefined || message.id === null) {
      return;
    }

    const { id, method, params } = message;

    switch (method) {
      case 'initialize':
        handleInitialize(id, params);
        break;
      case 'ping':
        sendResponse(id, {});
        break;
      case 'tools/list':
        handleToolsList(id);
        break;
      case 'tools/call':
        await handleToolsCall(id, params);
        break;
      default:
        sendError(id, -32601, `Method not supported: ${method}`);
        break;
    }
  } catch (e) {
    // Malformed JSON
  }
});
