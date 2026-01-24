---
name: command-based-track-declaration
description: コマンドによる開発 Track の明示的な宣言パターン
extracted: 2026-01-24
context: User Story 駆動開発における Feature/Technical Track の選択を明示化する方法
---

# Command-Based Track Declaration Pattern

**Extracted:** 2026-01-24
**Context:** 開発 Track の選択を明示化し、ワークフローの混乱を防ぐ

## Problem

開発作業を Feature Track と Technical Track に分ける場合、以下の問題が発生する:

1. **Track 選択の曖昧さ**: 開発者が「どちらの Track で進めるべきか」を判断しづらい
2. **ワークフローの混在**: Feature Track のフローで Technical 作業を進めてしまう (逆も同様)
3. **後からの Track 変更**: 途中で「これは Technical だった」と気づいても変更が面倒

特に AI Agent を使った自動化では、Track 選択を誤ると:
- 不要な spec.md を生成してしまう
- Issue ベースで進めるべきところで speckit-impl-verifier を実行してしまう
- Branch 命名規則が混在する (001-feature vs technical/22-refactor)

## Solution

**コマンドで Track を宣言し、それに応じたワークフローを自動選択する**

| コマンド | Track | ワークフロー | Branch 命名 |
|---------|-------|-------------|------------|
| `/speckit.specify` | Feature Track | spec.md → plan.md → tasks.md → /implement | `001-feature-name` |
| `/technical` | Technical Track | Issue タスク → orchestrator → /pr | `technical/22-short-desc` |

### 設計原則

1. **コマンドが Track を決定**: ユーザーが明示的にコマンドを選ぶことで Track が確定
2. **Track 固有のワークフロー**: 各 Track は独立したフローを持つ (混在しない)
3. **Branch 命名で追跡可能**: Branch 名を見れば Track が分かる
4. **後戻りなし**: Track 選択後は変更不可 (新規作業として再開)

### Feature Track コマンド

```bash
/speckit.specify "feature description"
    │
    ├─ Branch: 001-feature-name
    ├─ Output: specs/feature/001-feature-name/spec.md
    ├─ Next: /speckit.plan → /speckit.tasks
    └─ Implementation: /implement (spec-based)
```

**特徴**:
- spec.md で仕様を詳細化
- speckit-impl-verifier で実装検証
- User Story, Acceptance Criteria, Success Criteria を記述

### Technical Track コマンド

```bash
/technical "improvement description"
# または
/technical #22
    │
    ├─ Branch: technical/22-short-desc
    ├─ Output: Issue #22 のタスクセクション更新
    ├─ Next: orchestrator が自動で実装開始
    └─ Implementation: Issue-based (spec なし)
```

**特徴**:
- spec.md を生成しない
- speckit-impl-verifier をスキップ
- GitHub Issue で管理

### Track 選択の判断基準

コマンド選択時に自己問答:

```
Q: この変更でユーザーが新しいことをできるようになるか？

Yes → /speckit.specify
  例: 新しいキーバインド、fuzzy search、trash bin

No → /technical
  例: app.zig 分割、ドキュメント整理、パフォーマンス改善
```

## When to Use

### Feature Track (`/speckit.specify`)
- **新機能追加**: ユーザーが新しい操作をできるようになる
- **UI/UX 改善**: ユーザーに見える挙動が変わる
- **仕様が必要**: Acceptance Criteria を明確にしたい
- **複数の選択肢**: 実装方法を検討してから決めたい

### Technical Track (`/technical`)
- **リファクタリング**: 挙動は変わらないがコード構造を改善
- **ドキュメント改善**: README, architecture.md の更新
- **ビルドシステム改善**: build.zig の最適化
- **テスト追加**: 既存機能のカバレッジ向上
- **既存 Issue**: 既に議論されている技術的改善

### 境界線の例

| 作業内容 | Track | 理由 |
|---------|-------|------|
| 検索に fuzzy matching を追加 | Feature | ユーザーが新しい検索方法を使える |
| 検索アルゴリズムを O(n²) → O(n) に改善 | Technical | ユーザーには速くなるだけ (仕様変更なし) |
| ファイル削除時に確認ダイアログを追加 | Feature | UX が変わる (仕様必要) |
| 削除確認ロジックを別モジュールに分離 | Technical | 内部構造の改善 (挙動変わらず) |

## Example Implementation (kaiu)

### Feature Track の開始

```bash
# ユーザー入力
/speckit.specify "incremental search with highlighting"

# Agent の動作
1. Branch 作成: 005-incremental-search
2. spec.md 作成: specs/feature/005-incremental-search/spec.md
3. 関連 Issue 検索:
   - #15: fuzzy search proposal → 参照するか確認
   - #23: search performance ideas → 参照するか確認
4. spec.md に Related Issues セクション追加
5. /speckit.plan へ誘導
```

### Technical Track の開始

```bash
# ユーザー入力
/technical "app.zig を複数モジュールに分割したい"

# Agent の動作
1. 関連 Issue 検索:
   - #22: refactor: split app.zig into modules
2. Issue #22 のタスクセクションを読み込み
3. Branch 作成: technical/22-split-app-module
4. orchestrator 起動 (Issue タスクベース)
5. 実装 → refactor → doc-updater → /pr
```

### 既存 Issue から開始

```bash
# ユーザー入力
/technical #22

# Agent の動作
1. gh issue view 22 でタスク取得
2. Branch 確認 (既存なら checkout、なければ作成)
3. orchestrator 起動 (Issue タスクベース)
4. 実装 → /pr (Closes #22)
```

## Benefits

1. **Track 選択の明確化**: コマンド名を見れば Track が分かる
2. **ワークフローの自動化**: コマンドに応じて適切な Agent が起動
3. **Branch 管理の簡素化**: 命名規則が Track ごとに異なる
4. **Issue との連携**: Technical Track は Issue と自然に統合
5. **AI Agent の最適化**: Track ごとに異なる検証戦略を適用可能

## Implementation Details (Agent 側)

### `/speckit.specify` の処理

```markdown
1. Branch 作成 (001-feature-name)
2. 関連 Issue 検索 (gh issue list)
3. spec.md 生成 (spec-template.md ベース)
4. Related Issues セクション追加 (選択された Issue)
5. 選択された Issue に `feature` ラベル追加
6. /speckit.plan へ誘導
```

### `/technical` の処理

```markdown
1. 入力解析 (#22 か "description" か)
2. 関連 Issue 収集 (gh issue list --label technical)
3. Issue のタスクセクション読み込み
4. Branch 作成/確認 (technical/{number}-{desc})
5. orchestrator 起動 (Technical Track モード)
   - speckit-impl-verifier スキップ
   - speckit-task-verifier スキップ
6. /pr で Issue クローズ (Closes #XX)
```

## Alternatives Considered

### A: Track を明示せず、自動判定
- **問題**: AI の判断ミスで間違った Track に進む
- **例**: リファクタリングを Feature Track と誤認 → 不要な spec.md 生成

### B: 全て `/speckit.specify` で統一、オプションで Track 指定
- **問題**: コマンドが複雑化 (`/speckit.specify --technical`)
- **例**: オプションの指定忘れで間違った Track に進む

### C: Track を分けない (全て spec.md ベース)
- **問題**: 技術的改善を User Story として書くのが不自然
- **例**: "As a developer, I want to refactor..." (開発者は User ではない)

## Related Patterns

- **Track Separation Pattern**: Feature/Technical の分離戦略
- **Issue-to-Spec Integration**: Feature 開始時に関連 Issue を統合
- **Constitution-Driven Development**: Track 判断基準を constitution.md に記載
