# ichi-git-tools: zsh 用 git コマンド・プロンプト
#
# 前提: 先に confirm_msg / confirm / echo_execute / confirm_and_execute が定義されていること
# （~/.zshenv の「共通関数」ブロックなど）
#
_ichi_git_tools_root=${${(%):-%x}:A:h:h}
source "$_ichi_git_tools_root/.git_br_history.sh"
unset _ichi_git_tools_root

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
alias gp='git pull && git pull'
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

# 現在時刻をつけてPS1に表示
precmd() {
  PS1="[$(display_on_ps1) $(date "+%H:%M:%S")]\$ "
}

br_merger() {
  local _def cur
  _def=$(git_default_branch)
  cur=$(br_name)
  git branch --contains "$(git log "${_def}..HEAD" --merges --author="$(git config user.email)" -n 1 --format="%H^2")" | grep -vF "$cur"
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
  if ! [[ "$ISSUE_NO" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  git branch | grep "$ISSUE_NO" | sed -e 's/* //' -e 's/ //'
}

gco_remote() {
  _igi_require_git_dir || return
  local BR_NAME=$1
  echo_execute "git checkout -b $BR_NAME origin/$BR_NAME"
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
    echo_execute "git checkout $BR_NAME"
  elif br_exists_on_remote "$BR_NAME"; then
    confirm_and_execute "Do you want to checkout $BR_NAME from remote?" "gco_remote $BR_NAME"
  else
    confirm_and_execute "Do you want to create new branch $BR_NAME?" "git checkout -b $BR_NAME"
  fi
}

greset() {
  _igi_require_git_dir || return
  git checkout .
  git pull
}

set_nodenv_file() {
  # .node-versionを20.18.2にする 未来的に数値が変わったり不要になる可能性あり
  sed -i '' 's/20.19.4/20.18.2/' .node-version
}

restore_nodenv_file() {
  git checkout .node-version
}

gci() {
  _igi_require_git_dir || return
  local BR_NAME COMMIT_MESSAGE
  BR_NAME=$(br_name)
  COMMIT_MESSAGE=$1
  if [[ $BR_NAME == (master|main|production|staging) ]]; then
    echo "$BR_NAME is not allowed to commit locally"
    return 1
  fi
  set_nodenv_file
  echo_execute "git ci -m '$COMMIT_MESSAGE'"
  restore_nodenv_file
}

# デバグ用（gpush の zparseopts などの確認向け）
opttest() {
  echo "$1"
  if [[ -n ${y_option:-} ]]; then
    echo "option y is set"
    echo "$y_option"
    echo "$1"
  else
    echo "option y is not set"
  fi
}

gpush() {
  zparseopts -D -E y=y_option
  _igi_require_git_dir || return
  local BR_NAME=${1:-$(br_name)}
  if [[ $BR_NAME == (master|main|production|staging) ]]; then
    echo "$BR_NAME is not allowed to push directly"
    return 1
  fi
  if [[ -n ${y_option:-} ]]; then
    echo_execute "git push -u origin $BR_NAME:$BR_NAME"
  else
    confirm_and_execute "Are you sure you want to push $BR_NAME ?" "git push -u origin $BR_NAME:$BR_NAME"
  fi
}

gfetch() {
  _igi_require_git_dir || return
  local BR_NAME=${1:-$(br_name)}
  echo_execute "git fetch -u origin $BR_NAME:$BR_NAME"
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
    echo_execute "gfetch $BR_NAME && git merge --no-ff $BR_NAME"
  else
    confirm_and_execute "are you sure you want to merge $BR_NAME into $(br_name) ? " "gfetch $BR_NAME && git merge --no-ff $BR_NAME"
  fi && confirm_and_execute "gpush?" "gpush -y"
}

gcherry-pick() {
  _igi_require_git_dir || return
  local HASH=$1
  echo_execute "git cherry-pick -x $HASH"
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

change_br_name() {
  local BR_NAME_SNAKE=$1 NEW_BR_NAME
  NEW_BR_NAME="$(issue_name_by_branch)_${BR_NAME_SNAKE}"
  confirm_and_execute "rename branch to $NEW_BR_NAME ?" "git branch -m $NEW_BR_NAME"
}
