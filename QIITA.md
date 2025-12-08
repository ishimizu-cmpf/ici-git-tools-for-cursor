### はじめに
こんにちは。CAMPFIRE開発部DXチームのishimizuです。普段は経理周りやバックエンドのシステム開発やパートナーシステムの開発などを担当しています。

### みなさんGit使ってますか？
 私は毎日使っています。この業界で使ってない人なんてまあ居ないですよね。毎日、毎日GITキーを叩きすぎてそのキーボードのボタンだけ色が薄くなっている人も多いのではないでしょうか。

 しかしある日ふと思うわけです。
 git pushするとき、普通は
 ```
 git push -u origin test_branch:test_branch
 ```
のように同じブランチ名を何度も打たなきゃならない。しかも打った瞬間に確認なしでpushが実行されるので怖い。

PRのレビューなどでリモートのブランチをチェックアウトする時は
```
git checkout -b remote_branch origin/remote_branch
```
とこの時もやはり同じブランチ名を何度も書くことになるわけです。

とまあこのような不便を解消するために数年前このような記事を書いたのですが、

https://qiita.com/ishimizu-cmpqiita/items/66f01ba3a150da520441

それから時代は流れ、私のMacではbashは使えなくなりzshに移植しまして、AIに色々聞くと、もっとスッキリ書けるということを知りまして、特にgitのブランチ切り替え履歴をhistoryコマンドのように表示してインデックス指定でそのブランチをチェックアウトできるようにするコマンドが非常に便利ですので、紹介したいと思います。

## git reflogとは
`git reflog` は、Gitリポジトリ内の参照（ブランチやHEADなど）が変更された履歴を記録するコマンドです。通常の `git log` では見えない、削除されたコミットやリセットされた変更も追跡できます。

私は知らなかったのですが、ここにはブランチの移動履歴や移動した時刻も全て保存されています。
![image.png](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/851627/5bcadbda-0963-4dc2-a942-c0df23d14093.png)

前述した数年前の記事ではgitのブランチ移動履歴を残すためにブランチ切り替え専用のコマンドを作って`~/.bash_history`に似せた履歴ファイルを生成して読みこむ仕様にしていました。

が`git reflog`を使ってmoving from (...) to (...)を抜き出せば、その必要はなさそうじゃないか。

## やりたいこと
・git reflogからブランチの履歴を抜き出して
・historyコマンドのようにブランチの移動履歴を履歴番号付き（インデックス番号）で表示したい。
・インデックス番号を引数としてコマンド実行するとそのブランチをチェックアウトできるようにしたい。
・ただし同じブランチ名は何度も表示したくない。
・masterブランチは表示しなくてよい。（基本的にmasterに戻るコマンドは別に用意してるので）
・全履歴の読み込みは時間がかかるので読み込み上限数と表示上限数は制御できるように

といったことをCursorに関数名をbr_historyで作ってとお願いしたら、作ってくれました。

## 前提となる関数とalias
```zsh
# 現在のブランチ名を取得
alias br_name="git symbolic-ref --short HEAD 2>/dev/null"
# 今のディレクトリがgit管理下かどうかを返す
alias is_git_dir='git rev-parse 2> /dev/null'

#リモートにブランチが存在するかどうかをチェックする
br_exists_on_remote() {
  local branch="$1"
  git branch -r | grep -q "origin/${branch}"
}

```


git reflogを加工して履歴を表示するコマンド(br_history)の本体
```zsh
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

    echo "$display_count => $br_date $br_name$deleted_marker"
    ((display_count++))
  done | less -X
}

```
エイリアスの設定（gbhだけで呼べるようにする）
```zsh
alias gbh='br_history'
```

## 使い方
1. 引数なしで実行（リモートになくなっているブランチはdeletedとなっている。非表示にできるが未対応）
![image.png](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/851627/8c3f2df4-147c-4250-b3d8-c647ab49e77f.png)
履歴が表示されブランチに移動した時刻とインデックス番号が付加される

2. 引数にインデックス番号を指定して実行
指定した番号のブランチがチェックアウトされます。
![image.png](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/851627/34b05efa-ca71-42ee-850f-8a0afbdd770c.png)

## githubに公開しています。
ご意見・PRいただけましたら、感謝です。
https://github.com/ishimizu-cmpf/ichi-git-tools/blob/main/.git_br_history.sh

## さいごに

弊社では、私達と一緒に働ける方の求人を募集しています。bashやgitに限らず、rubyやvue.jsでお金の流れの新しい世界を一緒に作っていきませんか?

https://campfire.co.jp/careers/
