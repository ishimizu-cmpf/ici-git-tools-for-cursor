# ichi-git-tools

## セットアップ

`.zshenv`などに以下のように記述することで、`gh`コマンドが使えるようになります。

```bash
source /path/to/.git_br_history.sh
```

これにより、`gh`コマンドでブランチ履歴を確認・切り替えできるようになります。

## 使用方法

- `br_history`          - Git reflogからブランチ移動履歴を表示（最新20件）
- `br_history <index>`  - 指定したインデックスのブランチにチェックアウト
- `gh`                  - br_historyのエイリアス（同じ機能）

### 例

```bash
gh          # 履歴を表示
gh 3        # 3番目のブランチにチェックアウト
```
