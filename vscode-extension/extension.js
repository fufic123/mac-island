// Installed by Mac Island. When the island asks for a Claude session (it writes
// ~/.mac-island/vscode-focus.json with Claude's pid and its parent pids), the window whose
// terminal runs that process shows the terminal and answers with its workspace, so the island
// can raise that window. Nothing leaves the Mac.
const vscode = require('vscode');
const fs = require('fs');
const os = require('os');
const path = require('path');

const DIR = path.join(os.homedir(), '.mac-island');
const REQUEST = path.join(DIR, 'vscode-focus.json');

function activate(context) {
  let handled = '';

  async function check() {
    let request;
    try { request = JSON.parse(fs.readFileSync(REQUEST, 'utf8')); } catch { return; }
    if (!request || typeof request.id !== 'string' || request.id === handled) return;
    if (Date.now() - Number(request.at) > 5000) return;
    const pids = new Set((request.pids || []).filter(Number.isInteger));
    for (const terminal of vscode.window.terminals) {
      let pid;
      try { pid = await terminal.processId; } catch { continue; }
      if (!pid || !pids.has(pid)) continue;
      handled = request.id;
      terminal.show(false);
      const file = vscode.workspace.workspaceFile;
      const workspace = file && file.scheme === 'file'
        ? file.fsPath
        : (vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0]
          ? vscode.workspace.workspaceFolders[0].uri.fsPath : null);
      if (!/^[0-9A-Fa-f-]{36}$/.test(request.id)) return;
      try {
        fs.writeFileSync(path.join(DIR, `vscode-focus-${request.id}.json`), JSON.stringify({ workspace }));
      } catch {}
      return;
    }
  }

  try {
    fs.mkdirSync(DIR, { recursive: true });
    const watcher = fs.watch(DIR, () => { check(); });
    context.subscriptions.push({ dispose: () => watcher.close() });
  } catch {}
}

function deactivate() {}

module.exports = { activate, deactivate };
