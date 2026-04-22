alias br_name="git symbolic-ref --short HEAD 2>/dev/null"
alias is_git_dir='git rev-parse 2> /dev/null'

br_exists_on_remote() {
  local branch="$1"
  git branch -r | grep -q "origin/${branch}"
}

# ターミナルでブランチ名に OSC8 リンク（cmd+クリックで gbh N）。要: ~/ichi-git-tools/vscode-br-history-uri-handler/install.sh
# BR_HISTORY_URI_SCHEME=vscode（純 VS Code）/ BR_HISTORY_NO_TERMINAL_LINKS=1 / BR_HISTORY_FORCE_TERMINAL_LINKS=1
# リンクが出ない: settings の terminal.integrated.allowedLinkSchemes に cursor（または vscode）を追加
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

  local scheme="${BR_HISTORY_URI_SCHEME:-cursor}"
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

      # 有効なブランチ名かチェック（HEAD、master、コミットハッシュを除外）
      if [[ -n "$target_branch" && "$target_branch" != "HEAD" && "$target_branch" != "master" && ! "$target_branch" =~ ^[0-9a-f]{7,40}$ ]]; then
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
      echo -n "* "
    fi

    printf '%s => %s ' "$display_count" "$br_date"
    _br_history_print_branch_link "$display_count" "$br_name"
    printf '%s\n' "$deleted_marker"
    ((display_count++))
  done
}

alias gbh='br_history'
