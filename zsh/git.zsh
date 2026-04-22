# ichi-git-tools: zsh 用 git コマンド・プロンプト
#
# 前提: 先に confirm_msg / confirm / echo_execute / confirm_and_execute が定義されていること
# （~/.zshenv の「共通関数」ブロックなど）
#
_ichi_git_tools_root=${${(%):-%x}:A:h:h}
source "$_ichi_git_tools_root/.git_br_history.sh"
unset _ichi_git_tools_root

alias ggrep='git grep -n --color=auto'
alias dgrep='git ls-files | grep --color=auto'

alias gpull='git pull'
alias gp='git pull && git pull'
git_url() {
  local url=$(git remote get-url origin 2>/dev/null)
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
# 現在のブランチ名とディレクトリ名を取得
dispay_on_ps1() {
  br_name=`parse_git_branch`
  if [ -n "$br_name" ]; then
    echo -n "$br_name on $(basename `pwd`)"
  else
  echo -n "$(basename `pwd`)"
  fi
}
# 現在時刻をつけてPS1に表示
function precmd() {
    PS1="[$(dispay_on_ps1) $(date "+%H:%M:%S")]\$ "
}

br_merger() {
  local _def=$(git_default_branch)
  git branch --contains $(git log "${_def}..HEAD" --merges --author="$(git config user.email)" -n 1 --format="%H^2") | grep -v `br_name`
}

br_parents() {
  local _def=$(git_default_branch)
  PREV_IFS=$IFS
  IFS="
"
  for LINE in $(git log "${_def}..HEAD" --format='%d:%s' | grep -e "(" -e "Merge" )
  do
    REFS=`echo "$LINE" | cut -d ':' -f 1 | tr -d '()'`
    MSG=`echo "$LINE" | cut -d ':' -f 2`
    if [[ "$MSG" =~ ^.*Merge.*into.*$ ]]; then
      echo $MSG | sed -E "s/^.*into (.+).*$/\1/"
      echo $MSG | sed -E "s/^.*Merge branch '(.+)' .*$/\1/"
    fi
    if [ -n "$REFS" ]; then
      IFS=","
      for WORD in $REFS
      do
        echo $WORD | sed -E "s/origin\/(.+)/\1/" |  sed -E "s/HEAD -> (.+)/\1/" | tr -d " "
      done
    fi
  done | grep -vF "$_def" | grep -v "qa/" | uniq
  IFS=$PREV_IFS
}

br_parent() {
  PR_BRANCH=$(br_parents | grep -v "`br_name`" | head -1)
  if ! br_exists_on_remote $PR_BRANCH ; then
    git_default_branch
  else
    echo $PR_BRANCH
  fi
}

br_name_by_issue() {
  ISSUE_NO=$1
  if ! [[ "$ISSUE_NO" =~ ^[0-9]+$ ]]; then
    return;
  fi
  git branch | grep "$ISSUE_NO" | sed -e 's/* //' -e 's/ //'
}
gco_remote() {
  if ! `is_git_dir` ; then
    echo "not a git directory"
    return
  fi
  BR_NAME=$1
  echo_execute "git checkout -b $BR_NAME origin/$BR_NAME"
}
gbr() {
  if ! `is_git_dir` ; then
    echo "not a git directory"
    return
  fi
  BR_NAME=$1
  BR_NAME=${BR_NAME:-`br_name`}
  git branch | grep -7 -w $BR_NAME
}
gco() {
  if ! `is_git_dir` ; then
    echo "not a git directory"
    return
  fi
  BR_NAME=$1
  BR_NAME=${BR_NAME:-$(git_default_branch)}
  git checkout $BR_NAME
}
br_exists() {
  BR_NAME=$1
  # ローカルブランチが存在するかチェック
  if git branch | grep -q " $BR_NAME$" || git branch | grep -q "^* $BR_NAME$"; then
    # ローカルブランチが存在する場合、リモートブランチも存在するかチェック
    # 現在のブランチでupstreamが設定されている場合
    if [ "$BR_NAME" = "$(git branch --show-current 2>/dev/null)" ]; then
      # upstreamブランチが存在するかチェック
      UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
      if [ -n "$UPSTREAM" ]; then
        # upstreamが設定されている場合、そのブランチがリモートに存在するかチェック
        REMOTE_BRANCH=$(echo "$UPSTREAM" | sed 's/^origin\///')
        git ls-remote --heads origin "$REMOTE_BRANCH" | grep -q "$REMOTE_BRANCH"
        return $?
      fi
    fi
    # ローカルブランチが存在する場合、リモートブランチも存在するかチェック
    # リモートブランチが存在しない場合はローカルブランチを削除
    if ! `br_exists_on_remote $BR_NAME`; then
      # 現在のブランチでない場合のみ削除
      if [ "$BR_NAME" != "$(git branch --show-current 2>/dev/null)" ]; then
        echo "Removing local branch $BR_NAME (remote branch deleted)"
        git branch -d "$BR_NAME" 2>/dev/null || git branch -D "$BR_NAME" 2>/dev/null
      fi
      return 1
    fi
    # ローカルブランチが存在し、リモートブランチも存在する場合はtrue
    return 0
  fi
  # ローカルブランチが存在しない場合はfalse
  return 1
}
br_cleaned() {
  test -n "`git status | grep "nothing to commit"`"
}

gcb() {
  if ! `is_git_dir` ; then
    echo "not a git directory"
    return
  fi

  if [[ "$1" =~ ^[0-9]+$ ]]; then
    BR_NAME=`br_name_by_issue $1`
  else
    BR_NAME=$1
  fi

  BR_NAME=${BR_NAME:-$(git_default_branch)}
  CUR_BRANCH=`br_name`
  if [ "$BR_NAME" = "$CUR_BRANCH" ] ; then
    echo "already on $BR_NAME"
    return;
  fi
  if `br_exists $BR_NAME` ; then
    echo_execute "git checkout $BR_NAME"
  else
    if `br_exists_on_remote $BR_NAME` ; then
      confirm_and_execute "Do you want to checkout $BR_NAME from remote?" "gco_remote $BR_NAME"
    else
      confirm_and_execute "Do you want to create new branch $BR_NAME?" "git checkout -b $BR_NAME"
    fi
  fi
}

greset() {
  if ! `is_git_dir` ; then
    echo "not a git directory"
    return
  fi
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
  if ! `is_git_dir` ; then
    echo "not a git directory"
    return
  fi
  BR_NAME=`br_name`
  COMMIT_MESSAGE=$1
  if [[ $BR_NAME = 'master' || $BR_NAME = 'main' || $BR_NAME = 'production' || $BR_NAME = 'staging' ]]; then
    echo "$BR_NAME is not allowed to commit locally"
    return;
  fi
  set_nodenv_file
  echo_execute "git ci -m '$COMMIT_MESSAGE'"
  restore_nodenv_file
}

opttest() {
  # -y オプションの解析（値を取らないフラグとして扱う）

  echo $1;
  if [[ -n $y_option ]]; then
    echo "option y is set"
    echo $y_option;
    echo $1;
  else
    echo "option y is not set"
  fi
}
gpush() {
  zparseopts -D -E y=y_option
  if ! `is_git_dir` ; then
    echo "not a git directory"
    return
  fi
  BR_NAME=$1
  BR_NAME=${BR_NAME:-`br_name`}
  if [[ $BR_NAME = 'master' || $BR_NAME = 'main' || $BR_NAME = 'production' || $BR_NAME = 'staging' ]]; then
    echo "$BR_NAME is not allowed to push directly"
    return;
  fi
  if [ -n "$y_option" ]; then
    echo_execute "git push -u origin $BR_NAME:$BR_NAME"
  else
    confirm_and_execute "Are you sure you want to push $BR_NAME ?" "git push -u origin $BR_NAME:$BR_NAME"
  fi
}

gfetch() {
  if ! `is_git_dir` ; then
    echo "not a git directory"
    return
  fi
  BR_NAME=$1
  BR_NAME=${BR_NAME:-`br_name`}
  echo_execute "git fetch -u origin $BR_NAME:$BR_NAME"
}
gmerge() {
  if ! `is_git_dir` ; then
    echo "not a git directory"
    return
  fi
  BR_NAME=$1
  BR_NAME=${BR_NAME:-`br_parent`}
  if [ -n "`br_parent`" ]; then
    echo "parent branch is found [`br_parent`]"
  fi
  local _def=$(git_default_branch)
  BR_NAME=${BR_NAME:-$_def}
  if [[ "$BR_NAME" == "$_def" ]]; then
    echo_execute "gfetch $BR_NAME && git merge --no-ff $BR_NAME"
  else
    confirm_and_execute "are you sure you want to merge $BR_NAME into `br_name` ? " "gfetch $BR_NAME && git merge --no-ff $BR_NAME"
  fi && confirm_and_execute "gpush?" "gpush -y"

}
gcherry-pick() {
  if ! `is_git_dir` ; then
    echo "not a git directory"
    return
  fi
  HASH=$1
  echo_execute "git cherry-pick -x $HASH"
}

pr_url() {
  if ! `is_git_dir` ; then
    echo "not a git directory"
    return
  fi
  BR_PARENT=$1
  BR_PARENT=${BR_PARENT:-`br_parent`}

  if [ -n "$BR_PARENT" ]; then
    echo "`git_url`/compare/$BR_PARENT...`br_name`"
  else
    echo "`git_url`/compare/`br_name`"
  fi
}

change_br_name() {
  BR_NAME_SNAKE=$1
  NEW_BR_NAME="`issue_name_by_branch`_$BR_NAME_SNAKE"
  confirm_and_execute "rename branch to $NEW_BR_NAME ?" "git branch -m $NEW_BR_NAME"
}
