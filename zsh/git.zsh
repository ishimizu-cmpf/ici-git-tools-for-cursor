# ichi-git-tools: zsh 用 git コマンド・プロンプト
#
# 前提: 先に confirm_msg / confirm / echo_execute / confirm_and_execute が定義されていること
# （~/.zshenv の「共通関数」ブロックなど）
#
_ichi_git_tools_root=${${(%):-%x}:A:h:h}
source "$_ichi_git_tools_root/.git_br_history.sh"
unset _ichi_git_tools_root

# gci: set_nodenv 前の .node-version スナップ（restore はこのコピーへ戻し、意図しない上書きを減らす）
IGI__nodenv_saved=""

# is_git_dir は .git_br_history.sh の alias（git rev-parse）
_igi_require_git_dir() {
  if ! is_git_dir 2>/dev/null; then
    echo "not a git directory"
    return 1
  fi
}

alias ggrep='git grep -n --color=auto'
alias dgrep='git ls-files | grep --color=auto'

alias gpull='git pull'
alias gp='git pull'
git_url() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || return 1
  if [[ -z "$url" ]]; then
    return 1
  fi
  # SSH形式: git@host:path.git -> https://host/path
  # HTTPS形式: https://host/path.git -> https://host/path
  echo "$url" | sed -E 's|^git@([^:]+):(.+)\.git$|https://\1/\2|; s|^https://(.+)\.git$|https://\1|'
}

# リモートのデフォルトブランチ（例: main / master）。origin/HEAD が取れなければローカルの main / master の存在で推測。
git_default_branch() {
  local b
  b=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || true
  if [[ -n "$b" ]]; then
    print -r -- "$b"
    return
  fi
  if git show-ref -q --verify refs/heads/main 2>/dev/null; then
    print -r -- main
    return
  fi
  if git show-ref -q --verify refs/heads/master 2>/dev/null; then
    print -r -- master
    return
  fi
  print -r -- main
}
alias glog='git log --pretty=format:"%H (%ai) %s"'

parse_git_branch() {
  br_name |
    # ブランチ名からfeature/ishimizu_を削る
    sed -e 's/^feature\/ishimizu_\(.*\)/\1/' -e 's/^feature\/ishimizu\(.*\)/\1/'
}

# 現在のブランチ名とディレクトリ名を取得（グローバル br_name エイリアスと衝突しないよう別名）
display_on_ps1() {
  local branch dir
  branch=$(parse_git_branch)
  dir=$(basename "$PWD")
  if [[ -n "$branch" ]]; then
    print -rn -- "$branch on $dir"
  else
    print -rn -- "$dir"
  fi
}

# 現在時刻をつけてPS1に表示（他の precmd と合成するため add-zsh-hook を使う）
autoload -Uz add-zsh-hook
_ichi_git_tools_precmd_ps1() {
  PS1="[$(display_on_ps1) $(date "+%H:%M:%S")]\$ "
}
add-zsh-hook precmd _ichi_git_tools_precmd_ps1

br_merger() {
  local _def cur merge_base
  _def=$(git_default_branch)
  cur=$(br_name)
  merge_base=$(git log "${_def}..HEAD" --merges --author="$(git config user.email)" -n 1 --format="%H^2" 2>/dev/null) || true
  [[ -n "$merge_base" ]] || return 0
  if [[ -n "$cur" ]]; then
    git branch --format='%(refname:short)' --contains "$merge_base" | grep -vFx -- "$cur"
  else
    git branch --format='%(refname:short)' --contains "$merge_base"
  fi
}

br_parents() {
  local _def PREV_IFS LINE REFS MSG WORD
  _def=$(git_default_branch)
  PREV_IFS=$IFS
  IFS=$'\n'
  for LINE in $(git log "${_def}..HEAD" --format='%d:%s' | grep -e "(" -e "Merge"); do
    REFS=$(echo "$LINE" | cut -d ':' -f 1 | tr -d '()')
    MSG=$(echo "$LINE" | cut -d ':' -f 2)
    if [[ "$MSG" =~ ^.*Merge.*into.*$ ]]; then
      echo "$MSG" | sed -E "s/^.*into (.+).*$/\1/"
      echo "$MSG" | sed -E "s/^.*Merge branch '(.+)' .*$/\1/"
    fi
    if [[ -n "$REFS" ]]; then
      IFS=","
      for WORD in $REFS; do
        echo "$WORD" | sed -E "s/origin\/(.+)/\1/" | sed -E "s/HEAD -> (.+)/\1/" | tr -d " "
      done
    fi
  done | grep -vF "$_def" | grep -v "qa/" | uniq
  IFS=$PREV_IFS
}

br_parent() {
  local PR_BRANCH cur
  cur=$(br_name)
  PR_BRANCH=$(br_parents | grep -vF "$cur" | head -1)
  if [[ -z "$PR_BRANCH" ]] || ! br_exists_on_remote "$PR_BRANCH"; then
    git_default_branch
  else
    print -r -- "$PR_BRANCH"
  fi
}

br_name_by_issue() {
  local ISSUE_NO=$1
  local -a m
  if ! [[ "$ISSUE_NO" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  m=(${(f)"$(git branch --format='%(refname:short)' 2>/dev/null | command grep -F -- "$ISSUE_NO" 2>/dev/null)"})
  if (( ${#m[@]} == 0 )); then
    echo "gcb: no local branch name contains: $ISSUE_NO" >&2
    return 1
  fi
  if (( ${#m[@]} > 1 )); then
    echo "gcb: multiple branches match; specify branch name instead of issue number: ${m[*]}" >&2
    return 1
  fi
  print -r -- "$m[1]"
}

gco_remote() {
  _igi_require_git_dir || return
  local BR_NAME=$1 REMOTE_REF="origin/$BR_NAME"
  echo_execute "git checkout -b ${(q)BR_NAME} ${(q)REMOTE_REF}"
}

gbr() {
  _igi_require_git_dir || return
  local BR_NAME=${1:-$(br_name)}
  git branch --list "*${BR_NAME}*"
}

gco() {
  _igi_require_git_dir || return
  local BR_NAME=${1:-$(git_default_branch)}
  git checkout "$BR_NAME"
}

# 注意: ローカルに存在するが origin に同名ブランチが無いとき、現在ブランチでなければ
# ローカルブランチを削除する副作用がある（gcb 等の「存在判定」に使われている）。
br_exists() {
  local BR_NAME=$1
  local current upstream remote_branch
  current=$(git branch --show-current 2>/dev/null)
  # ローカルブランチが存在するかチェック
  if git branch | grep -q " $BR_NAME\$" || git branch | grep -q "^\* $BR_NAME\$"; then
    if [[ "$BR_NAME" == "$current" ]]; then
      upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
      if [[ -n "$upstream" ]]; then
        remote_branch=${upstream#origin/}
        git ls-remote --heads origin "$remote_branch" | grep -q "$remote_branch"
        return $?
      fi
    fi
    if ! br_exists_on_remote "$BR_NAME"; then
      if [[ "$BR_NAME" != "$current" ]]; then
        echo "Removing local branch $BR_NAME (remote branch deleted)"
        git branch -d "$BR_NAME" 2>/dev/null || git branch -D "$BR_NAME" 2>/dev/null
      fi
      return 1
    fi
    return 0
  fi
  return 1
}

br_cleaned() {
  git status 2>/dev/null | grep -q "nothing to commit"
}

gcb() {
  _igi_require_git_dir || return

  local BR_NAME CUR_BRANCH
  if [[ "$1" =~ ^[0-9]+$ ]]; then
    BR_NAME=$(br_name_by_issue "$1")
  else
    BR_NAME=$1
  fi

  BR_NAME=${BR_NAME:-$(git_default_branch)}
  CUR_BRANCH=$(br_name)
  if [[ "$BR_NAME" == "$CUR_BRANCH" ]]; then
    echo "already on $BR_NAME"
    return
  fi
  if br_exists "$BR_NAME"; then
    echo_execute "git checkout ${(q)BR_NAME}"
  elif br_exists_on_remote "$BR_NAME"; then
    confirm_and_execute "Do you want to checkout $BR_NAME from remote?" "gco_remote ${(q)BR_NAME}"
  else
    confirm_and_execute "Do you want to create new branch $BR_NAME?" "git checkout -b ${(q)BR_NAME}"
  fi
}

greset() {
  _igi_require_git_dir || return
  git checkout .
  git pull
}

set_nodenv_file() {
  # .node-versionを20.18.2にする 未来的に数値が変わったり不要になる可能性あり
  [[ -f .node-version ]] || return 0
  IGI__nodenv_saved=$(mktemp "${TMPDIR:-/tmp}/ichi-gci_nodever.XXXXXX") 2>/dev/null || { IGI__nodenv_saved=; return 0; }
  if ! cp -p .node-version "$IGI__nodenv_saved" 2>/dev/null; then
    rm -f "$IGI__nodenv_saved"
    IGI__nodenv_saved=
    return 0
  fi
  if sed --version >/dev/null 2>&1; then
    sed -i 's/20.19.4/20.18.2/' .node-version
  else
    sed -i '' 's/20.19.4/20.18.2/' .node-version
  fi
}

restore_nodenv_file() {
  if [[ -n $IGI__nodenv_saved && -f $IGI__nodenv_saved ]]; then
    command mv -f -- "$IGI__nodenv_saved" .node-version
  fi
  IGI__nodenv_saved=
}

gci() {
  _igi_require_git_dir || return
  local BR_NAME COMMIT_MESSAGE tmp ret
  BR_NAME=$(br_name)
  COMMIT_MESSAGE=$1
  if [[ $BR_NAME == (master|main|production|staging) ]]; then
    echo "$BR_NAME is not allowed to commit locally"
    return 1
  fi
  if [[ -z "$COMMIT_MESSAGE" ]]; then
    echo "usage: gci <commit message>"
    return 1
  fi
  set_nodenv_file
  tmp=
  if ! tmp=$(mktemp "${TMPDIR:-/tmp}/ichi-gci.XXXXXX") 2>/dev/null; then
    restore_nodenv_file
    return 1
  fi
  print -r -- "$COMMIT_MESSAGE" >"$tmp" || {
    rm -f "$tmp"
    restore_nodenv_file
    return 1
  }
  # メッセージに ' や " を含めても安全（eval しない）。改行もそのまま渡せる。
  print -r -- "git commit -F $tmp"
  git commit -F "$tmp"
  ret=$?
  rm -f -- "$tmp" 2>/dev/null
  restore_nodenv_file
  return $ret
}

gpush() {
  local -a y_option
  zparseopts -D -E y=y_option
  _igi_require_git_dir || return
  local BR_NAME=${1:-$(br_name)}
  if [[ $BR_NAME == (master|main|production|staging) ]]; then
    echo "$BR_NAME is not allowed to push directly"
    return 1
  fi
  if (( $#y_option )); then
    echo_execute "git push -u origin ${(q)BR_NAME}:${(q)BR_NAME}"
  else
    confirm_and_execute "Are you sure you want to push $BR_NAME ?" "git push -u origin ${(q)BR_NAME}:${(q)BR_NAME}"
  fi
}

gfetch() {
  _igi_require_git_dir || return
  local BR_NAME=${1:-$(br_name)}
  echo_execute "git fetch origin ${(q)BR_NAME}:${(q)BR_NAME}"
}

gmerge() {
  _igi_require_git_dir || return
  local BR_NAME parent_hint _def
  parent_hint=$(br_parent)
  BR_NAME=${1:-$parent_hint}
  if [[ -n "$parent_hint" ]]; then
    echo "parent branch is found [$parent_hint]"
  fi
  _def=$(git_default_branch)
  BR_NAME=${BR_NAME:-$_def}
  if [[ "$BR_NAME" == "$_def" ]]; then
    echo_execute "gfetch ${(q)BR_NAME} && git merge --no-ff ${(q)BR_NAME}"
  else
    confirm_and_execute "are you sure you want to merge $BR_NAME into $(br_name) ? " "gfetch ${(q)BR_NAME} && git merge --no-ff ${(q)BR_NAME}"
  fi && confirm_and_execute "gpush?" "gpush -y"
}

gcherry-pick() {
  _igi_require_git_dir || return
  local HASH=$1
  echo_execute "git cherry-pick -x ${(q)HASH}"
}

pr_url() {
  _igi_require_git_dir || return
  local BR_PARENT=${1:-$(br_parent)}
  if [[ -n "$BR_PARENT" ]]; then
    echo "$(git_url)/compare/$BR_PARENT...$(br_name)"
  else
    echo "$(git_url)/compare/$(br_name)"
  fi
}

# change_br_name より前に ~/.zshenv で定義していればそちらが優先される
if ! (( ${+functions[issue_name_by_branch]} )); then
  issue_name_by_branch() {
    parse_git_branch | tr '/' '_' | tr -cd '[:alnum:]_-'
  }
fi

change_br_name() {
  local BR_NAME_SNAKE=$1 NEW_BR_NAME
  if [[ -z $BR_NAME_SNAKE ]]; then
    echo "usage: change_br_name <name_suffix>"
    return 1
  fi
  NEW_BR_NAME="$(issue_name_by_branch)_${BR_NAME_SNAKE}"
  confirm_and_execute "rename branch to $NEW_BR_NAME ?" "git branch -m ${(q)NEW_BR_NAME}"
}
