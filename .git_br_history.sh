alias br_name="git symbolic-ref --short HEAD 2>/dev/null"
alias is_git_dir='git rev-parse 2> /dev/null'

br_exists_on_remote() {
  local branch="$1"
  git branch -r | grep -q "origin/${branch}"
}

# ターミナルでブランチ名に OSC8 リンク（cmd+クリックで gbh N）。要: このリポジトリの vscode-br-history-uri-handler/install.sh を bash で実行。
# BR_HISTORY_URI_SCHEME=… で上書き。未指定時は環境で自動: Cursor なら cursor、それ以外（純 VS Code 等）なら vscode。
# BR_HISTORY_NO_TERMINAL_LINKS=1 / BR_HISTORY_FORCE_TERMINAL_LINKS=1
# リンクが出ない: settings の terminal.integrated.allowedLinkSchemes に cursor（または vscode）を追加
#
# 統合ターミナルで CURSOR_* / VSCODE_IPC_HOOK が付かないことがある。そのときは PPID 列を辿って
# Cursor.app / Visual Studio Code.app / Linux の code・cursor バイナリパスを見る。
_br_history_process_tree_scheme() {
  local pid line lc i next
  pid=${PPID:-0}
  i=0
  while [[ "${pid:-0}" -gt 1 && i -lt 24 ]]; do
    line=$(ps -p "$pid" -o args= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
    if [[ -z "$line" ]]; then
      line=$(ps -p "$pid" -o command= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
    fi
    if [[ -n "$line" ]]; then
      lc=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
      if [[ "$lc" == *cursor.app* || "$lc" == */cursor/cursor* || "$lc" == *cursor.exe* ]]; then
        printf cursor
        return 0
      fi
      if [[ "$lc" == *"visual studio code.app"* || "$lc" == *"visual studio code - insiders.app"* || \
            "$lc" == *vscode.app* || "$lc" == */code/code* ]]; then
        printf vscode
        return 0
      fi
    fi
    next=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d '[:space:]')
    [[ -z "$next" || "$next" == "$pid" ]] && break
    pid=$next
    i=$((i + 1))
  done
  return 1
}

_br_history_uri_scheme() {
  if [[ -n "${BR_HISTORY_URI_SCHEME:-}" ]]; then
    printf '%s' "$BR_HISTORY_URI_SCHEME"
    return
  fi
  # TERM_PROGRAM はどちらも vscode になることが多い。Cursor 専用の痕跡で切り分ける。
  # 新しい Cursor では VSCODE_IPC_HOOK がターミナルに渡らない／パス表記が変わることがあるため
  # CURSOR_* を先に見る（例: https://github.com/anthropics/claude-code/issues/44466）。
  if [[ -n "${CURSOR_AGENT:-}" || -n "${CURSOR_CLI:-}" ]]; then
    printf cursor
    return
  fi
  if [[ -n "${CURSOR_TRACE_ID:-}" ]]; then
    printf cursor
    return
  fi
  if [[ -n "${VSCODE_IPC_HOOK:-}" ]]; then
    local _hook_lc
    _hook_lc=$(printf '%s' "$VSCODE_IPC_HOOK" | tr '[:upper:]' '[:lower:]')
    if [[ "$_hook_lc" == *cursor.app* || "$_hook_lc" == */cursor/* || \
          "$_hook_lc" == *programs/cursor/* || "$_hook_lc" == *programs\\cursor\\* ]]; then
      printf cursor
      return
    fi
  fi
  local _tree
  if _tree=$(_br_history_process_tree_scheme); then
    printf '%s' "$_tree"
    return
  fi
  printf vscode
}

_br_history_print_branch_link() {
  local n="$1"
  local label="$2"

  if [[ "${BR_HISTORY_NO_TERMINAL_LINKS:-}" == "1" ]]; then
    printf '%s' "$label"
    return
  fi

  local use_links=0
  if [[ "${BR_HISTORY_FORCE_TERMINAL_LINKS:-}" == "1" ]]; then
    use_links=1
  elif [[ -t 1 && "${TERM_PROGRAM:-}" == "vscode" ]]; then
    use_links=1
  fi

  if [[ "$use_links" != "1" ]]; then
    printf '%s' "$label"
    return
  fi

  local scheme
  scheme="$(_br_history_uri_scheme)"
  printf '\033]8;;%s://local.terminal-link/gbh?n=%s\033\\%s\033]8;;\033\\' "$scheme" "$n" "$label"
}


# 使用方法:
#   br_history          - Git reflogからブランチ移動履歴を表示（最新20件）
#   br_history <index>  - 指定したインデックスのブランチにチェックアウト
#   gbh                 - br_historyのエイリアス（同じ機能）
#
# 例:
#   br_history          # 履歴を表示
#   br_history 3        # 3番目のブランチにチェックアウト
#   gbh                 # 履歴を表示（エイリアス使用）
br_history() {
  if ! is_git_dir; then
    echo "not a git directory"
    return 1
  fi

  local br_index=$1
  local current_branch=$(br_name)
  typeset -A seen_branches
  local branch_list=()
  local branch_dates=()
  local count=0
  local max_display=20
  # 必要な分だけ読み込む（表示件数の5倍程度、重複を考慮）
  local max_read=$((max_display * 5))

  # Git reflogからブランチ移動履歴を取得
  # 形式: "HEAD@{2025-08-18 13:42:57} checkout: moving from master to feature/xxx"
  # 
  # プロセス置換 < <(...) を使用:
  # - whileループは現在のシェルで実行され、変数の変更が正しく反映される
  while IFS= read -r line; do
    # 必要な件数に達したら早期終了
    [[ $count -ge $max_display ]] && break
    [[ -z "$line" ]] && continue

    # reflogの行をパース（sedで抽出）
    # 例: "HEAD@{2025-08-18 13:42:57} checkout: moving from master to feature/xxx"
    local entry_date=$(echo "$line" | sed -E 's/^HEAD@\{([0-9-]+ [0-9:]+)\} .*/\1/')
    local message=$(echo "$line" | sed -E 's/^HEAD@\{[^}]+\} (.*)/\1/')

    # "checkout: moving from A to B" の形式からブランチ名を抽出
    if [[ "$message" =~ "checkout: moving from" ]]; then
      local target_branch=$(echo "$message" | sed -E 's/.*checkout: moving from [^ ]+ to ([^ ]+).*/\1/')

      # 有効なブランチ名かチェック（HEAD、master、main、コミットハッシュを除外）
      if [[ -n "$target_branch" && "$target_branch" != "HEAD" && "$target_branch" != "master" && "$target_branch" != "main" && ! "$target_branch" =~ ^[0-9a-f]{7,40}$ ]]; then
        # 連想配列で重複チェック（O(1)）
        if [[ -z "${seen_branches[$target_branch]}" ]]; then
          branch_list+=("$target_branch")
          branch_dates+=("$entry_date")
          seen_branches[$target_branch]=1
          ((count++))
        fi
      fi
    fi
  # プロセス置換: git reflog の結果をwhileループに渡す
  # この方法により、whileループ内での変数変更（branch_list、countなど）が親シェルに反映される
  done <<(git reflog -n $max_read --date=format:'%Y-%m-%d %H:%M:%S' --format="%gd %gs" 2>/dev/null | grep "checkout: moving from")

  # インデックス指定時は該当ブランチにチェックアウト
  if [[ -n "$br_index" ]]; then
    if [[ "$br_index" =~ ^[0-9]+$ ]] && [[ $br_index -ge 1 && $br_index -le ${#branch_list[@]} ]]; then
      # 配列は新しいものから順（インデックス0が最新）
      local array_index=$((br_index - 1))
      local target_branch="${branch_list[$array_index]}"
      if [[ -n "$target_branch" ]]; then
        git checkout "$target_branch"
      else
        echo "Invalid branch index: $br_index"
        return 1
      fi
    else
      echo "Invalid index: $br_index (valid range: 1-${#branch_list[@]})"
      return 1
    fi
    return
  fi

  # 履歴表示（historyコマンド風、最新が上）
  echo "(current on $current_branch)"

  local display_count=1
  for ((i=0; i<${#branch_list[@]}; i++)); do
    local br_name="${branch_list[$i]}"
    local br_date="${branch_dates[$i]}"
    local deleted_marker=""
    
    # ブランチが削除されているかチェック
    if ! br_exists_on_remote "$br_name" 2>/dev/null; then
      deleted_marker=" (deleted)"
    fi

    # 現在のブランチにはマークを付ける
    if [[ "$br_name" == "$current_branch" ]]; then
      printf '%s' '* '
    fi

    printf '%s => %s ' "$display_count" "$br_date"
    _br_history_print_branch_link "$display_count" "$br_name"
    printf '%s\n' "$deleted_marker"
    ((display_count++))
  done
}

alias gbh='br_history'
