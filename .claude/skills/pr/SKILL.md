---
name: pr
description: >
  Pull Request の作成・管理を行う。
  トリガー: "pr", "プルリクエスト", "/pr"
---

# /pr - Pull Request 操作

現在のブランチに関連する Pull Request の操作を行う。

## 使用方法

```
/pr                    # PR 作成
/pr status             # PR 状態確認
/pr comment <内容>     # PR にコメント追加
/pr revert             # PR をリバート
/pr merge              # PR をマージ
```

## サブコマンド

### /pr (作成)

現在のブランチから PR を作成。

```bash
git status                      # 未コミット変更確認
git log @{upstream}..HEAD       # コミット確認
git diff @{upstream}...HEAD     # 差分確認
gh pr create --title "..." --body "..." --label "<auto>" --assignee "@me"
```

**ラベル自動付与:**

| Commit Type | Label |
|-------------|-------|
| feat | enhancement |
| fix | bug |
| docs | documentation |
| refactor | refactor |
| chore, perf, ci, test | enhancement |

**出力:**
```
PR #42 を作成しました
https://github.com/user/repo/pull/42

Next: /codex でコードレビュー
```

### /pr status

```bash
gh pr view --json number,title,state,reviews,checks
```

### /pr comment <内容>

```bash
gh pr view --json number -q .number
gh pr comment <番号> --body "<内容>"
```

### /pr revert

マージ済み PR をリバート。

### /pr merge

```bash
gh pr merge --squash
```

## ワークフロー

```
/implement → /pr → /codex → /pr comment → 修正 → /pr merge
```

<user-request>
$ARGUMENTS
</user-request>
