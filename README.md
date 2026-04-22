# ichi-git-tools

**注意: このツールはzsh専用です。bashでは動作しません。**

## セットアップ

**zsh専用**: このスクリプトはzshの機能（プロセス置換 `<<(...)` や連想配列 `typeset -A`）を使用しているため、zshでのみ動作します。

`.zshenv`などに以下のように記述することで、`gbh`コマンドが使えるようになります。

```zsh
source /path/to/.git_br_history.sh
```

これにより、`gbh`コマンドでブランチ履歴を確認・切り替えできるようになります。

### オプション: Cursor / VS Code のターミナルでブランチ名をクリックして checkout

統合ターミナル上で `gbh` の一覧のブランチ名を **cmd+クリック** して同じ `gbh <番号>` を送るには、同梱のローカル拡張を入れます（初回・更新時）。リポジトリのルートで:

```zsh
bash vscode-br-history-uri-handler/install.sh
```

インストール後、Cursor または VS Code を再読み込みしてください。リンクが点線にならない場合は、ユーザー設定の `terminal.integrated.allowedLinkSchemes` に `cursor` または `vscode` を含めてください。外部から `cursor://` / `vscode://` を踏む心配がある場合は、設定 `gbhTerminalLink.requireConfirmation` を `true` にすると、実行前に確認ダイアログを出せます（既定は `false`）。

## 使用方法

- `br_history`          - Git reflogからブランチ移動履歴を表示（最新20件）
- `br_history <index>`  - 指定したインデックスのブランチにチェックアウト
- `gbh`                 - br_historyのエイリアス（同じ機能）

### 例

```zsh
gbh          # 履歴を表示
gbh 3        # 3番目のブランチにチェックアウト
```
