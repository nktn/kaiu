---
name: track-separation-pattern
description: User Story 駆動開発における Feature Track と Technical Track の分離パターン
extracted: 2026-01-24
context: User Story 駆動開発のワークフローでリファクタリングや技術的改善をどう扱うか
---

# Track Separation Pattern

**Extracted:** 2026-01-24
**Context:** User Story 駆動開発において、技術的改善をどのように扱うか

## Problem

User Story 駆動開発では、全ての変更を spec.md → plan.md → tasks.md のフローで管理する。しかし、以下のような技術的改善はユーザー価値を直接提供しないため、このフローに乗せるのが不自然:

- リファクタリング (app.zig を複数モジュールに分割など)
- ドキュメント改善
- パフォーマンス最適化
- テストカバレッジ向上
- ビルドシステム改善

これらを無理に User Story として書くと:
- 仕様が冗長になる (技術的詳細を仕様に書くことになる)
- spec.md の目的 (ユーザー価値の記述) が曖昧になる
- 技術的改善のハードルが上がる (仕様書くのが面倒で後回しになる)

## Solution

開発作業を2つの Track に分ける:

| Track | コマンド | 用途 | 管理方法 |
|-------|---------|------|---------|
| **Feature Track** | `/speckit.specify` | ユーザー価値を提供する機能 | spec.md → plan.md → tasks.md |
| **Technical Track** | `/technical` | 開発者価値、リファクタリング、ドキュメント改善 | GitHub Issue のタスクセクション |

### 判断基準

**「この変更でユーザーが新しいことをできるようになるか？」**

- **Yes** → Feature Track
  - 例: fuzzy search、trash bin、新しいキーバインド
  - `/speckit.specify "feature description"` で開始
  - spec.md で仕様を明確化
  - speckit-impl-verifier で実装検証

- **No** → Technical Track
  - 例: app.zig 分割、ドキュメント整理、パフォーマンス改善
  - `/technical "improvement description"` または `/technical #22` で開始
  - GitHub Issue のタスクセクションで管理
  - speckit-impl-verifier をスキップ (技術的整合性のみ検証)

### Technical Track のフロー

```
/technical "改善の説明" または /technical #22
    │
    ▼
関連 Issue を収集・分析
    │
    ▼
タスクを整理・作成 (Issue の「タスク」セクションに書き込み)
    │
    ▼
Branch 作成 (technical/{issue-number}-{short-description})
    │
    ▼
orchestrator (Issue タスクベース)
    │
    ▼
zig-refactor-cleaner → doc-updater
    │
    ▼
/pr (Closes #XX でリンク) → /codex-fix
```

### Feature Track との統合

Feature 実装中に関連する Issue を発見した場合:

1. `/speckit.specify` 実行時に関連 Issue を検索して提案
2. ユーザーが選択した Issue に `feature` ラベルを追加
3. spec.md の "Related Issues" セクションに記載
4. Issue のアイデアを仕様に反映

これにより:
- Issue で議論されたアイデアが Feature に統合される
- Issue が Feature 実装でクローズされる (Closes #XX)
- 技術的議論と仕様が分離される (Issue → 議論、spec.md → 仕様)

## When to Use

### Feature Track を選ぶべき場合
- 新しいキーバインドを追加
- 新しい UI 要素を追加
- ユーザーが実行できる操作を追加
- ユーザーに見える挙動を変更

### Technical Track を選ぶべき場合
- コードをリファクタリング (挙動は変わらない)
- ドキュメントを改善
- ビルドシステムを改善
- テストを追加 (機能追加なし)
- パフォーマンスを最適化 (ユーザー体験は変わらない)

### 境界線が曖昧な場合

**例**: "検索パフォーマンスを改善したい"

- **Feature Track**: 「100ms で結果を返せるようにしたい」(ユーザー体験が変わる)
- **Technical Track**: 「アルゴリズムを O(n²) から O(n) に改善したい」(内部実装の改善)

**判断のコツ**: spec.md で Success Criteria を書いてみて、「ユーザーが測定できるか？」を確認する。
- ユーザーが測定できる (「検索が速くなった」と感じる) → Feature Track
- 開発者しか測定できない (「コード行数が減った」) → Technical Track

## Example (kaiu プロジェクト)

### Feature Track 例
```bash
/speckit.specify "incremental search with highlighting"
# → spec.md で仕様を詳細化
# → User Story: "As a user, I want to search files incrementally..."
# → Acceptance Criteria: "Search results appear as I type"
# → Success Criteria: "Search completes in under 50ms for 1000 files"
```

### Technical Track 例
```bash
/technical "app.zig を複数モジュールに分割したい"
# → Issue #22 を作成または参照
# → タスク:
#   - [ ] state.zig を作成 (App state 管理)
#   - [ ] event.zig を作成 (イベント処理)
#   - [ ] app.zig を簡略化
# → orchestrator が実行
```

## Benefits

1. **明確な責務分離**: 仕様 (spec.md) は純粋にユーザー価値を記述
2. **技術的改善のハードル低減**: Issue ベースで軽量に開始可能
3. **適切なレビュー**: Feature は spec との整合性、Technical はコード品質を重点的に検証
4. **Issue 活用**: GitHub Issue を技術的議論の場として活用
5. **トレーサビリティ**: どの変更がユーザー価値で、どれが技術的改善かが明確

## Alternatives Considered

### A: 全てを Feature Track で管理
- **問題**: 技術的改善を User Story として書くのが不自然
- **例**: "As a developer, I want to refactor app.zig..." (開発者は User ではない)

### B: 全てを Technical Track で管理
- **問題**: ユーザー価値の仕様が曖昧になる
- **例**: 検索機能を Issue で議論すると、Acceptance Criteria が不明確になる

### C: Feature/Technical の区別なし
- **問題**: レビュー観点が混在して品質が低下
- **例**: リファクタリング PR で spec との整合性を検証してしまう (無駄)

## Related Patterns

- **Constitution-Driven Development**: constitution.md に Track 判断基準を記載
- **Issue-to-Spec Integration**: Feature 開始時に関連 Issue を検索・統合
- **Command-Based Track Declaration**: `/speckit.specify` vs `/technical` で Track を明示
