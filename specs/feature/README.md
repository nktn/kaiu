# Feature Track Specs

Feature Track の設計文書を格納するディレクトリ。

## 構造

```
specs/feature/
├── README.md
└── {NNN}-{short-name}/
    ├── spec.md     # 仕様書 (User Stories, AC, FR)
    ├── plan.md     # 技術設計
    └── tasks.md    # タスクリスト
```

## 命名規則

- ディレクトリ名: `{NNN}-{short-name}` (3桁の連番)
  - 例: `001-search-feature`
  - 例: `002-file-preview`

## Technical Track との違い

| 項目 | Feature Track | Technical Track |
|------|--------------|-----------------|
| 場所 | `specs/feature/{NNN}-{name}/` | `specs/technical/{issue-number}-{name}/` |
| spec.md | 必須 | なし (Issue が代替) |
| plan.md | 必須 | 必須 |
| tasks.md | 必須 | 必須 |
| 番号 | 連番 (001, 002, ...) | GitHub Issue 番号 |

## 参照

- `/speckit.specify` コマンド: `.claude/commands/speckit.specify.md`
- ワークフロー: `.claude/rules/workflow.md`
