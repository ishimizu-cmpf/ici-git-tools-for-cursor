#!/usr/bin/env bash
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)"
ext="$(
  cd "$src" && node -e "
const p = require('./package.json');
process.stdout.write(p.publisher + '.' + p.name + '-' + p.version);
"
)"
for d in "${HOME}/.cursor/extensions" "${HOME}/.vscode/extensions"; do
  mkdir -p "$d"
  # Legacy install paths; remove all local.terminal-link copies so the folder name
  # always matches package.json (publisher.name-version).
  shopt -s nullglob
  for old in \
    "$d"/brhistory.terminal-link-0.0.1 \
    "$d"/brhistory.terminal-link-0.0.2 \
    "$d"/local.terminal-link-0.0.2 \
    "$d"/local.terminal-link-*; do
    [[ -e $old ]] && rm -rf "$old"
  done
  shopt -u nullglob
  cp -R "$src" "$d/$ext"
done
