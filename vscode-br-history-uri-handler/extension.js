"use strict";
const vscode = require("vscode");

function activate(context) {
  context.subscriptions.push(
    vscode.window.registerUriHandler({
      async handleUri(uri) {
        try {
          if (uri.path.replace(/^\//, "") !== "gbh") {
            return;
          }
          const n = new URLSearchParams(uri.query).get("n");
          if (!n || !/^\d+$/.test(n)) {
            return;
          }
          await vscode.commands.executeCommand("workbench.action.terminal.sendSequence", {
            text: `gbh ${n}\r`,
          });
        } catch (e) {
          console.error("[local.terminal-link]", e);
        }
      },
    }),
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
