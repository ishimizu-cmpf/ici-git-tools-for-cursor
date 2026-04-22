#!/usr/bin/env bash
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)"
ext="local.terminal-link-0.0.3"
for d in "${HOME}/.cursor/extensions" "${HOME}/.vscode/extensions"; do
  mkdir -p "$d"
  rm -rf "$d"/brhistory.terminal-link-0.0.1 "$d"/brhistory.terminal-link-0.0.2 "$d"/local.terminal-link-0.0.2 "$d/$ext"
  cp -R "$src" "$d/$ext"
done
