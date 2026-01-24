# Technical Track Specs

Technical Track の設計文書を格納するディレクトリ。

## 構造

```
specs/technical/
├── README.md
└── {issue-number}-{short-name}/
    ├── plan.md    # 方針・設計
    └── tasks.md   # タスクリスト
```

## 命名規則

- ディレクトリ名: `{issue-number}-{short-name}`
  - 例: `25-technical-track-specs`
  - 例: `30-app-module-split`

## Feature Track との違い

| 項目 | Feature Track | Technical Track |
|------|--------------|-----------------|
| 場所 | `specs/{NNN}-{name}/` | `specs/technical/{issue}-{name}/` |
| spec.md | 必須 | なし (Issue が代替) |
| plan.md | 必須 | 必須 |
| tasks.md | 必須 | 必須 |

## 参照

- `/technical` コマンド: `.claude/commands/technical.md`
- ワークフロー: `.claude/rules/workflow.md`
