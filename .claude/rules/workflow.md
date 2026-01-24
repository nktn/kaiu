# 開発ワークフロー

kaiu 開発における計画から実装までの全体フロー。

---

## Track Selection

開発作業は2つの Track に分かれる:

| Track | コマンド | 用途 | Label |
|-------|---------|------|-------|
| **Feature Track** | `/speckit.specify` | ユーザー価値を提供する機能 | `feature` |
| **Technical Track** | `/technical` | 開発者価値、リファクタリング、ドキュメント改善 | `technical` |

**判断基準**: 「この変更でユーザーが新しいことをできるようになるか？」
- Yes → Feature Track (`/speckit.specify`)
- No → Technical Track (`/technical`)

---

## Technical Track

### 概要図

```
/technical "改善の説明" または /technical #22
    │
    ▼
関連 Issue を収集・分析
    │   - 既存 Issue があれば参照
    │   - 関連する他の Issue も確認
    │
    ▼
タスクを整理・作成
    │   - Issue の「タスク」セクションを更新
    │   - 依存関係を整理
    │
    ▼
Branch 作成 (未作成の場合)
    │
    ▼
orchestrator (Issue タスクベース)
    │   - zig-architect → zig-tdd → build-resolver
    │
    ▼
zig-refactor-cleaner
    │
    ▼
doc-updater
    │
    ▼
/pr (Closes #XX でリンク)
    │
    ▼
/codex-fix → 手動テスト → マージ
    │
    ▼
Issue も自動クローズ
```

### /technical コマンド

**入力形式**:
- `/technical "改善の説明"` - 新規 Issue を作成
- `/technical #22` - 既存 Issue を参照

**実行内容**:
1. 関連 Issue を収集・分析
2. タスクを整理し Issue の「タスク」セクションに書き込み
3. Branch を作成 (`technical/{issue-number}-{short-description}`)
4. orchestrator を起動

**Issue テンプレート** (新規作成時):
```markdown
## 概要
[改善の説明]

## 背景
[なぜ必要か]

## 方針
[どう実現するか]

## タスク
- [ ] タスク1
- [ ] タスク2
- [ ] ...
```

### orchestrator (Technical Track)

Feature Track との違い:
- spec.md ではなく Issue の「タスク」セクションを参照
- speckit-impl-verifier をスキップ
- speckit-task-verifier をスキップ

**実行フロー**:
1. Issue のタスクを読み込み
2. タスクごとに: zig-architect → zig-tdd → (失敗時) build-resolver
3. 全タスク完了後: zig-refactor-cleaner
4. doc-updater

---

## Feature Track

### 概要図

```
┌─────────────────────────────────────────────────────────────────┐
│                      計画フェーズ                                │
│                                                                 │
│  /speckit.specify → /speckit.plan → /speckit.tasks             │
│                                          │                      │
│                                          ▼                      │
│                               /speckit.task-verify              │
│                                          │                      │
│                          [GAP] ←─────────┼──────────→ [PASS]   │
│                            │                            │       │
│                            ▼                            ▼       │
│                    タスク追加して再検証          tasks.md 完成   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼ (別セッション/別タイミング)
┌─────────────────────────────────────────────────────────────────┐
│                      実装フェーズ                                │
│                                                                 │
│  /implement                                                     │
│      │                                                          │
│      ▼                                                          │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ orchestrator                                               │ │
│  │                                                            │ │
│  │ Phase 1: Planning                                          │ │
│  │   └── タスク分析 → 計画出力 → ユーザー承認待ち              │ │
│  │                                                            │ │
│  │ Phase 2: Execution (承認後)                                │ │
│  │   ├── 各タスク:                                            │ │
│  │   │   zig-architect → zig-tdd → (失敗時) build-resolver   │ │
│  │   │                                                        │ │
│  │   └── Phase 完了ごと:                                      │ │
│  │       speckit-impl-verifier (部分検証)                     │ │
│  │           └── [GAP] → 追加タスク                           │ │
│  │                                                            │ │
│  │ Phase 3: Completion                                        │ │
│  │   ├── zig-refactor-cleaner (クリーンアップ)                │ │
│  │   └── speckit-impl-verifier (実装検証 1回目)               │ │
│  │                                                            │ │
│  └───────────────────────────────────────────────────────────┘ │
│      │                                                          │
│      ▼ [検証 PASS]                                              │
│  doc-updater (ドキュメント更新 + パターン学習)                   │
│      │                                                          │
│      ▼                                                          │
│  /pr (Pull Request 作成)                                        │
│      │                                                          │
│      ▼                                                          │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ /codex-fix ループ                                          │ │
│  │                                                            │ │
│  │   codex レビュー                                           │ │
│  │       │                                                    │ │
│  │       ├── [指摘あり] → 修正 → Decision Log → 再レビュー ──┐│ │
│  │       │                                                   ││ │
│  │       └── [指摘なし] ─────────────────────────────────────┘│ │
│  │                                                            │ │
│  └───────────────────────────────────────────────────────────┘ │
│      │                                                          │
│      ▼ [レビュー完了]                                           │
│  speckit-impl-verifier (実装検証 2回目: レビュー修正後)          │
│      │                                                          │
│      ▼ [検証 PASS]                                              │
│  手動テスト (ユーザーによる動作確認)                             │
│      │                                                          │
│      ▼ [確認 OK]                                                │
│  マージ                                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 計画フェーズ詳細

### 1. /speckit.specify

機能仕様を作成。ブランチも作成される。

**ブランチ**: `NNN-feature-name` (例: `001-search-feature`)
**出力**: `$FEATURE_DIR/spec.md`

**内容**:
- User Stories (US1, US2, ...) + Priority (P1, P2, P3)
- Acceptance Criteria (AC)
- Functional Requirements (FR)
- Success Criteria (SC)
- Out of Scope

**注**: `$FEATURE_DIR` は `check-prerequisites.sh` で取得 (例: `/path/to/repo/specs/001-feature`)

### 2. /speckit.plan

技術設計を作成。

**出力**: `$FEATURE_DIR/plan.md`

**内容**:
- Tech Stack
- Architecture
- Data Model
- Implementation Strategy

### 3. /speckit.tasks

タスクリストを生成。

**出力**: `$FEATURE_DIR/tasks.md`

**内容**:
- Phase 1: Setup
- Phase 2: Foundational
- Phase 3+: User Story ごと
- Final Phase: Polish

### 4. /speckit.task-verify

タスクカバレッジを検証。

**検証項目**:
- 全 User Story にタスクがあるか
- 全 Acceptance Criteria がカバーされているか
- Priority 整合性 (P1 が早い Phase にあるか)

**出力**: Coverage Matrix、Gap List

---

## 実装フェーズ詳細

### 1. /implement → orchestrator

**Phase 1: Planning**
- `check-prerequisites.sh --json --require-tasks --include-tasks` で FEATURE_DIR を取得
- `$FEATURE_DIR/spec.md` と `$FEATURE_DIR/tasks.md` を分析
- 実行計画を出力
- **ユーザー承認を待つ** (承認までコードを書かない)

**Phase 2: Execution**

各タスクで Agent を順番に呼び出し:

| Agent | 役割 | 条件 |
|-------|------|------|
| `zig-architect` | 設計判断、architecture.md 更新 | 必須 |
| `zig-tdd` | RED → GREEN → REFACTOR | 必須 |
| `zig-build-resolver` | ビルドエラー修正 | **ビルド失敗時のみ** |

Phase 完了ごとに `speckit-impl-verifier` で部分検証。

**Phase 3: Completion**
- `zig-refactor-cleaner`: 未使用コード削除、イディオム適用
- `speckit-impl-verifier`: 最終検証

### 2. speckit-impl-verifier (1回目)

実装完了後、spec との整合性を検証。

**検証項目**:
- Functional Requirements の実装確認
- Acceptance Scenarios のコードパス存在確認
- Out of Scope 機能が実装されていないか確認

### 3. doc-updater

**ドキュメント更新**:
- README.md (キーバインド表)
- architecture.md (状態遷移図)

**パターン学習**:
- セッションから有用なパターンを抽出
- `.claude/skills/learned/` に保存

### 4. /pr → /codex-fix

- `/pr`: Pull Request 作成
- `/codex-fix`: コードレビュー + 自動修正ループ
- `/codex`: 単発レビュー (手動修正する場合)

**`/codex-fix` ループ**:
```
codex レビュー
    ↓
[指摘あり] → 修正 → Decision Log 追加 → 再レビュー → ...
    ↓
[指摘なし] → 完了
```

**Decision Log**: レビュー指摘の採用/スキップ理由を PR コメントに記録。

### 5. speckit-impl-verifier (2回目)

レビュー修正後、spec との整合性を再検証。

**目的**: `/codex-fix` での修正が spec から外れていないか確認。

### 6. 手動テスト

ユーザーによる動作確認。

**テストファイルの準備**:
ユーザーが「手動テストしたい」と言ったら、テスト用のファイル/ディレクトリを作成する。

```bash
# 例: test_files/ にテスト用構造を作成
mkdir -p test_files/{docs,src/{components,utils},assets}
echo "test content" > test_files/src/main.zig
echo "delete me" > test_files/delete_me.txt
echo "rename me" > test_files/rename_me.txt
# ... 機能に応じたテストファイル
```

**テストファイルの内容**:
- 通常のファイル/ディレクトリ（操作確認用）
- 隠しファイル（`.` で始まるファイル）
- 削除/リネーム用のダミーファイル
- 一括操作用の複数ファイル（bulk1.txt, bulk2.txt, ...）

**確認項目**:
- 主要機能が期待通り動作するか
- エッジケースでクラッシュしないか
- UX が仕様通りか

### 7. マージ

全ての検証が PASS したら PR をマージ。

---

## Agent 一覧

| Agent | 役割 | 呼び出しタイミング | Track |
|-------|------|------------------|-------|
| `orchestrator` | タスク管理・実行制御 | `/implement`, `/technical` | 両方 |
| `zig-architect` | 設計判断 | 各タスクの最初 | 両方 |
| `zig-tdd` | TDD サイクル | 設計判断後 | 両方 |
| `zig-build-resolver` | ビルド修正 | **ビルド失敗時のみ** | 両方 |
| `zig-refactor-cleaner` | リファクタリング | 全タスク完了後 | 両方 |
| `speckit-task-verifier` | Task カバレッジ検証 | `/speckit.tasks` 後 | Feature のみ |
| `speckit-impl-verifier` | 実装検証 | Phase 完了後、最終 | Feature のみ |
| `doc-updater` | ドキュメント + 学習 | 検証 PASS 後 | 両方 |
| `codex-fixer` | レビュー指摘修正 | `/codex-fix` 実行時 | 両方 |

---

## コマンド一覧

### 計画系 (/speckit.*)

| コマンド | 役割 |
|----------|------|
| `/speckit.specify` | 仕様作成 |
| `/speckit.clarify` | 仕様の曖昧点を質問 |
| `/speckit.plan` | 技術設計 |
| `/speckit.tasks` | タスク生成 |
| `/speckit.task-verify` | タスクカバレッジ検証 |
| `/speckit.analyze` | 一貫性分析 |
| `/speckit.impl-verify` | 実装検証 |

### 実装系

| コマンド | 役割 | Track |
|----------|------|-------|
| `/implement` | Feature 実装 (orchestrator 起動) | Feature |
| `/technical` | Technical 実装 (Issue ベース) | Technical |
| `/build-fix` | ビルドエラー修正 | 両方 |
| `/tdd` | TDD サイクル | 両方 |

### その他

| コマンド | 役割 |
|----------|------|
| `/pr` | Pull Request 作成 |
| `/codex` | コードレビュー (単発) |
| `/codex-fix` | レビュー + 自動修正ループ |

---

## 典型的な開発フロー例

```bash
# 1. 計画フェーズ (セッション A)
/speckit.specify "検索機能を追加したい"
/speckit.plan
/speckit.tasks
/speckit.task-verify
# → tasks.md 完成、GAP なし

# 2. 実装フェーズ (セッション B)
/implement
# → orchestrator が計画出力
# → "この計画で進めていいですか？" → はい
# → 各タスク実行...
# → speckit-impl-verifier (1回目: 実装検証)
# → doc-updater 実行

# 3. PR 作成 + レビュー
/pr
/codex-fix
# → 自動で指摘修正 → Decision Log 追加 → 再レビュー
# → ... (指摘なくなるまで)

# 4. 最終検証 + 手動テスト
/speckit.impl-verify
# → spec との整合性を再確認 (レビュー修正後)
# → 手動でアプリを動作確認
# → 問題なければマージ
```

### Technical Track 例

```bash
# 1. Technical 作業開始
/technical #22
# または
/technical "app.zig を複数モジュールに分割したい"

# → 関連 Issue を分析
# → タスクを整理して Issue に書き込み
# → Branch 作成

# 2. 実装
# → orchestrator がタスクを実行
# → zig-architect → zig-tdd → build-resolver
# → zig-refactor-cleaner
# → doc-updater

# 3. PR 作成 + レビュー
/pr
# → "Closes #22" で Issue とリンク
/codex-fix
# → 自動で指摘修正 → Decision Log 追加

# 4. 手動テスト + マージ
# → 動作確認
# → マージすると Issue も自動クローズ
```
