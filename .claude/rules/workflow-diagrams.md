# Workflow Diagrams

kaiu 開発ワークフローの Mermaid 図式。詳細は `.claude/rules/workflow.md` を参照。

---

## 1. Track Selection

```mermaid
flowchart TB
    Start([開発作業開始]) --> Decision{ユーザーが<br/>新しいことを<br/>できるようになる?}
    Decision -->|Yes| Feature[Feature Track]
    Decision -->|No| Technical[Technical Track]

    Feature --> FeatureCmd["/speckit.specify"]
    Technical --> TechCmd["/technical"]

    FeatureCmd --> FeatureFlow[計画 → 実装 → レビュー → マージ]
    TechCmd --> TechFlow[Issue分析 → 実装 → レビュー → マージ]

    style Feature fill:#4CAF50,color:#fff
    style Technical fill:#2196F3,color:#fff
```

---

## 2. Feature Track

```mermaid
flowchart TB
    subgraph Planning["計画フェーズ"]
        direction TB
        Specify["/speckit.specify<br/>仕様作成"] --> Plan["/speckit.plan<br/>技術設計"]
        Plan --> Tasks["/speckit.tasks<br/>タスク生成"]
        Tasks --> TaskVerify["/speckit.task-verify"]
        TaskVerify --> GapCheck{GAP?}
        GapCheck -->|あり| Tasks
        GapCheck -->|なし| TasksComplete([tasks.md 完成])
    end

    subgraph Implementation["実装フェーズ"]
        direction TB
        Implement["/implement"] --> Orchestrator

        subgraph Orchestrator["orchestrator"]
            OrcPlan["Phase 1: Planning<br/>タスク分析 → ユーザー承認"]
            OrcPlan --> OrcExec

            subgraph OrcExec["Phase 2: Execution"]
                TaskLoop["各タスク実行"]
                TaskLoop --> Architect["zig-architect"]
                Architect --> TDD["zig-tdd"]
                TDD --> BuildCheck{ビルド成功?}
                BuildCheck -->|失敗| BuildResolver["zig-build-resolver"]
                BuildResolver --> TDD
                BuildCheck -->|成功| PhaseCheck{Phase完了?}
                PhaseCheck -->|Yes| ImplVerifyPartial["speckit-impl-verifier<br/>(部分検証)"]
                ImplVerifyPartial --> TaskLoop
                PhaseCheck -->|No| TaskLoop
            end

            OrcExec --> OrcComplete["Phase 3: Completion"]
            OrcComplete --> RefactorCleaner["zig-refactor-cleaner"]
            RefactorCleaner --> ImplVerify1["speckit-impl-verifier<br/>(最終検証)"]
        end

        ImplVerify1 --> DocUpdater["doc-updater<br/>ドキュメント更新 + パターン学習"]
    end

    subgraph Review["レビューフェーズ"]
        direction TB
        PR["/pr<br/>PR作成"] --> CodexFix

        subgraph CodexFix["/codex-fix ループ"]
            CodexReview["codex レビュー"]
            CodexReview --> IssueCheck{指摘あり?}
            IssueCheck -->|Yes| Fix["修正 + Decision Log"]
            Fix --> CodexReview
            IssueCheck -->|No| ReviewDone([レビュー完了])
        end

        ReviewDone --> ImplVerify2["speckit-impl-verifier<br/>(レビュー修正後)"]
        ImplVerify2 --> ManualTest["手動テスト"]
        ManualTest --> Merge["/pr merge"]
    end

    TasksComplete -.->|別セッション| Implementation
    DocUpdater --> Review

    style Planning fill:#E3F2FD
    style Implementation fill:#E8F5E9
    style Review fill:#FFF3E0
```

---

## 3. Technical Track

```mermaid
flowchart TB
    Start["/technical #22<br/>または<br/>/technical '説明'"] --> IssueAnalysis["Issue 収集・分析"]
    IssueAnalysis --> CreateSpecs["specs/technical/ 作成<br/>├── plan.md<br/>└── tasks.md"]
    CreateSpecs --> UserApproval{ユーザー承認?}
    UserApproval -->|Yes| Branch["Branch 作成"]

    Branch --> Orchestrator

    subgraph Orchestrator["orchestrator"]
        TaskLoop["各タスク実行"]
        TaskLoop --> Architect["zig-architect"]
        Architect --> TDD["zig-tdd"]
        TDD --> BuildCheck{ビルド成功?}
        BuildCheck -->|失敗| BuildResolver["zig-build-resolver"]
        BuildResolver --> TDD
        BuildCheck -->|成功| NextTask{次のタスク?}
        NextTask -->|Yes| TaskLoop
        NextTask -->|No| RefactorCleaner["zig-refactor-cleaner"]
    end

    RefactorCleaner --> DocUpdater["doc-updater"]
    DocUpdater --> PR["/pr<br/>Closes #XX"]
    PR --> CodexFix["/codex-fix"]
    CodexFix --> ManualTest["手動テスト"]
    ManualTest --> Merge["/pr merge"]
    Merge --> IssueClosed([Issue 自動クローズ])

    style Orchestrator fill:#E8F5E9
```

---

## 4. Agent 連携図

```mermaid
flowchart LR
    subgraph Skills["Skills (ユーザー呼び出し)"]
        Specify["/speckit.specify"]
        SpecPlan["/speckit.plan"]
        SpecTasks["/speckit.tasks"]
        Implement["/implement"]
        Technical["/technical"]
        PR["/pr"]
        Codex["/codex"]
        CodexFix["/codex-fix"]
    end

    subgraph Agents["Agents (自動呼び出し)"]
        Orchestrator["orchestrator"]
        Architect["zig-architect"]
        TDD["zig-tdd"]
        BuildResolver["zig-build-resolver"]
        RefactorCleaner["zig-refactor-cleaner"]
        TaskVerifier["speckit-task-verifier"]
        ImplVerifier["speckit-impl-verifier"]
        DocUpdater["doc-updater"]
        CodexFixer["codex-fixer"]
    end

    Implement --> Orchestrator
    Technical --> Orchestrator

    Orchestrator --> Architect
    Orchestrator --> TDD
    Orchestrator --> BuildResolver
    Orchestrator --> RefactorCleaner
    Orchestrator --> ImplVerifier

    SpecTasks --> TaskVerifier
    CodexFix --> CodexFixer

    ImplVerifier -.-> DocUpdater

    style Skills fill:#BBDEFB
    style Agents fill:#C8E6C9
```

---

## 5. /codex-fix ループ詳細

```mermaid
flowchart TB
    Start["/codex-fix"] --> InitReview["codex exec --full-auto<br/>--sandbox read-only"]
    InitReview --> ParseIssues["指摘を解析"]
    ParseIssues --> HasIssues{指摘あり?}

    HasIssues -->|No| Complete([完了])
    HasIssues -->|Yes| ShowIssues["指摘一覧を提示"]

    ShowIssues --> UserApproval["AskUserQuestion<br/>修正方針の承認"]
    UserApproval --> ApplyFixes["承認された修正を適用<br/>(Edit ツール)"]
    ApplyFixes --> RunTests["zig build test"]
    RunTests --> TestPass{テスト通過?}

    TestPass -->|No| FixTests["テスト修正"]
    FixTests --> RunTests
    TestPass -->|Yes| Commit["git commit<br/>'fix: address codex review<br/>feedback (round N)'"]

    Commit --> ReReview["再レビュー<br/>codex exec"]
    ReReview --> RoundCheck{指摘あり?}

    RoundCheck -->|Yes| MaxRounds{最大ラウンド?}
    MaxRounds -->|No| ShowIssues
    MaxRounds -->|Yes| ForceComplete
    RoundCheck -->|No| ForceComplete["Decision Log を<br/>PR コメントに追加"]

    ForceComplete --> Push["git push"]
    Push --> Complete

    style Complete fill:#4CAF50,color:#fff
```

---

## 6. タイムライン概要

```mermaid
gantt
    title Feature Track タイムライン
    dateFormat X
    axisFormat %s

    section 計画
    /speckit.specify     :a1, 0, 1
    /speckit.plan        :a2, after a1, 1
    /speckit.tasks       :a3, after a2, 1
    /speckit.task-verify :a4, after a3, 1

    section 実装
    /implement (orchestrator) :b1, after a4, 3
    doc-updater              :b2, after b1, 1

    section レビュー
    /pr                  :c1, after b2, 1
    /codex-fix           :c2, after c1, 2
    speckit-impl-verifier :c3, after c2, 1
    手動テスト            :c4, after c3, 1
    /pr merge            :c5, after c4, 1
```

---

## 7. Worktree 並行開発

```mermaid
flowchart TB
    subgraph Worktrees["Git Worktrees"]
        Main["kaiu/<br/>(main)<br/>安定版・レビュー用"]
        WT41["kaiu-41/<br/>(technical/41-*)<br/>Issue #41 作業"]
        WT43["kaiu-43/<br/>(technical/43-*)<br/>Issue #43 作業"]
    end

    Main -.->|"git worktree add"| WT41
    Main -.->|"git worktree add"| WT43

    WT41 -->|完了| PR41["PR #41"]
    WT43 -->|完了| PR43["PR #43"]

    PR41 -->|merge| Main
    PR43 -->|merge| Main

    WT41 -.->|"git worktree remove"| Removed41([削除])
    WT43 -.->|"git worktree remove"| Removed43([削除])

    style Main fill:#4CAF50,color:#fff
    style WT41 fill:#2196F3,color:#fff
    style WT43 fill:#FF9800,color:#fff
```

### Worktree ライフサイクル

```mermaid
sequenceDiagram
    participant M as main (kaiu/)
    participant W as worktree (kaiu-41/)
    participant R as origin/main

    M->>M: git fetch origin main
    M->>M: git checkout main
    M->>M: git pull origin main

    M->>W: git worktree add ../kaiu-41 -b technical/41-*

    loop 開発サイクル
        W->>W: 実装 + テスト
        W->>W: git commit
    end

    W->>R: git push -u origin technical/41-*
    W->>R: gh pr create

    Note over W,R: /codex-fix + 手動テスト

    R->>M: gh pr merge --squash
    M->>M: git worktree remove ../kaiu-41
```

### コンフリクト解決フロー

```mermaid
flowchart TB
    Conflict([コンフリクト発生]) --> Fetch["git fetch origin main"]
    Fetch --> Rebase["git rebase origin/main"]
    Rebase --> ResolveCheck{解決可能?}

    ResolveCheck -->|Yes| Resolve["コンフリクト解決"]
    ResolveCheck -->|No| Abort["git rebase --abort"]
    Abort --> Consult["相談して決定"]

    Resolve --> Stage["git add <files>"]
    Stage --> Continue["git rebase --continue"]
    Continue --> Test["zig build test"]
    Test --> TestPass{テスト通過?}

    TestPass -->|No| Fix["修正"]
    Fix --> Test
    TestPass -->|Yes| Done([解決完了])

    subgraph Priority["優先順位"]
        P1["1. main が正"]
        P2["2. Feature > Technical"]
        P3["3. P1 > P2 > P3"]
        P4["4. 先にマージした方が正"]
        P5["5. Issue 番号が小さい方"]
    end

    Resolve -.-> Priority
```

### ホットスポットファイル

```mermaid
mindmap
  root((コンフリクト<br/>しやすいファイル))
    src/app.zig
      状態管理
      キーハンドリング
      Issue #41 で分割予定
    architecture.md
      状態遷移図
      Design Decisions
    README.md
      キーバインド表
      機能一覧
    workflow.md
      Agent 一覧
      コマンド一覧
```

---

## 8. コマンド早見表

| Phase | Feature Track | Technical Track |
|-------|---------------|-----------------|
| 開始 | `/speckit.specify` | `/technical` |
| 計画 | `/speckit.plan` → `/speckit.tasks` | (自動生成) |
| 検証 | `/speckit.task-verify` | - |
| 実装 | `/implement` | (自動) |
| PR | `/pr` | `/pr` |
| レビュー | `/codex-fix` | `/codex-fix` |
| マージ | `/pr merge` | `/pr merge` |
