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
  # Legacy install paths; remove old local.terminal-link dirs/symlinks so the name
  # always matches package.json (publisher.name-version). Then we link to this repo.
  shopt -s nullglob
  for old in \
    "$d"/brhistory.terminal-link-0.0.1 \
    "$d"/brhistory.terminal-link-0.0.2 \
    "$d"/local.terminal-link-0.0.2 \
    "$d"/local.terminal-link-*; do
    [[ -e $old ]] && rm -rf "$old"
  done
  shopt -u nullglob
  # 従来の cp 展開や、リポと別物の同パスをシンボリックリンク先に差し替える
  if [[ -e "$d/$ext" || -L "$d/$ext" ]]; then
    rm -rf "$d/$ext"
  fi
  ln -s "$src" "$d/$ext"
done
