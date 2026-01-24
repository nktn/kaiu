# /codex-fix - Codex レビュー修正ループ

Codex レビューと修正を自動でループ実行する。

## 使用方法

```
/codex-fix                    # デフォルト設定で実行 (最大3ラウンド)
/codex-fix --max-rounds=5     # 最大5ラウンド
/codex-fix --min-severity=medium  # MEDIUM以上のみ修正
```

## オプション

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `--max-rounds` | 3 | 最大ループ回数 |
| `--min-severity` | low | 修正対象の最小 Severity (low/medium/high) |
| `--auto` | false | 全指摘を自動承認 (確認なし) |

**注意**: デフォルトでは各指摘の修正前にユーザー承認を求めます。`--auto` で自動承認できますが、意図しない変更のリスクがあります。

## ワークフロー

```
/codex-fix
    │
    ├── Phase 1: Initial Review
    │   └── /codex 実行、指摘をパース
    │
    ├── Phase 2: Fix Loop (max N rounds)
    │   │
    │   ├── Round 1:
    │   │   ├── codex-fixer Agent 呼び出し
    │   │   │   ├── 指摘を分析
    │   │   │   ├── 修正を適用
    │   │   │   └── 変更をコミット
    │   │   │
    │   │   └── /codex 再実行
    │   │       ├── [指摘なし] → Phase 3 へ
    │   │       └── [指摘あり] → Round 2
    │   │
    │   ├── Round 2: ...
    │   │
    │   └── Round N または 指摘なし → Phase 3
    │
    └── Phase 3: Completion
        ├── 最終結果を報告
        └── 残った指摘があれば一覧表示
```

## 実行手順

### Step 1: 初回レビュー

```bash
# Codex CLI でレビュー実行
codex exec --full-auto --sandbox read-only --cd <project_directory> "Review the changes in this PR for code quality issues"
```

レビュー結果から指摘を抽出:
- HIGH: 重大な問題 (セキュリティ、バグ)
- MEDIUM: 改善推奨 (パフォーマンス、可読性)
- LOW: 軽微な指摘 (スタイル)

### Step 2: 修正ループ

指摘がある場合、`codex-fixer` Agent を呼び出し:

```
codex-fixer Agent に渡す情報:
- 指摘リスト (severity, issue, file, suggestion)
- --min-severity 設定
- --auto 設定
```

**修正方針の確認** (--auto でない場合):
```
=== 指摘 1/3 ===
File: src/app.zig:42
Issue: Memory leak
Severity: HIGH

修正方針: errdefer を追加

[Y] 適用  [N] スキップ  [E] 編集して適用  [A] 全て適用
```

ユーザーが承認した修正を適用後:
1. 変更をステージ
2. コミットメッセージ: `fix: address codex review feedback (round N)`
3. /codex で再レビュー

### Step 3: 完了判定

以下のいずれかで終了:
- 指摘が 0 件
- 最大ラウンド数に到達
- 修正不可能な指摘のみ残っている

## 出力例

```
=== Codex Review & Fix ===

Round 1:
  Review: 3 issues found (1 HIGH, 2 MEDIUM)
  Fixed: 3/3
  Committed: fix: address codex review feedback (round 1)

Round 2:
  Review: 1 issue found (1 LOW)
  Fixed: 1/1
  Committed: fix: address codex review feedback (round 2)

Round 3:
  Review: 0 issues found

✓ All issues resolved in 3 rounds

Summary:
  Total issues found: 4
  Total issues fixed: 4
  Rounds: 3
```

## 修正できない指摘

以下の指摘は自動修正せず、報告のみ:

1. **設計判断が必要**: アーキテクチャの変更が必要
2. **仕様の曖昧さ**: 要件の確認が必要
3. **トレードオフ**: パフォーマンス vs 可読性など

これらは最終レポートに記載し、手動対応を依頼。

## エラーハンドリング

### ビルドエラー発生時

```
修正適用後にビルドエラー
    │
    ├── zig-build-resolver で修正試行
    │
    ├── [成功] → 続行
    └── [失敗] → 変更を revert、次の指摘へ
```

### 無限ループ防止

- 同じ指摘が連続3回出たら自動修正を中止
- 最大ラウンド数のハードリミット

## 関連

- `/codex` - 単発レビュー
- `codex-fixer` Agent - 修正実行
- `/pr` - PR 作成

<user-request>
$ARGUMENTS
</user-request>
