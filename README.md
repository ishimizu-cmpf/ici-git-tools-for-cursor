# ichi-git-tools

**注意: このツールはzsh専用です。bashでは動作しません。**

## セットアップ

**zsh専用**: このスクリプトはzshの機能（プロセス置換 `<<(...)` や連想配列 `typeset -A`）を使用しているため、zshでのみ動作します。

`.zshenv`などに以下のように記述することで、`gbh`コマンドが使えるようになります。

```zsh
source /path/to/.git_br_history.sh
```

これにより、`gbh`コマンドでブランチ履歴を確認・切り替えできるようになります。

## 使用方法

- `br_history`          - Git reflogからブランチ移動履歴を表示（最新20件）
- `br_history <index>`  - 指定したインデックスのブランチにチェックアウト
- `gbh`                 - br_historyのエイリアス（同じ機能）

### 例

```zsh
gbh          # 履歴を表示
gbh 3        # 3番目のブランチにチェックアウト
```
