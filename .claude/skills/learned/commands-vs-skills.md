---
name: commands-vs-skills
description: Claude Code の commands/ と skills/ ディレクトリの違いと移行ガイド
---

# Commands vs Skills in Claude Code

**Extracted:** 2026-01-23
**Context:** Claude Code のカスタムスラッシュコマンド設定時

## Problem

`.claude/commands/` と `.claude/skills/` の違いが不明確で、どちらを使うべきか判断できなかった。

## Solution

### 機能比較

| 特性 | commands/ | skills/ |
|------|-----------|---------|
| ファイル構造 | ファイルのみ | ディレクトリ + SKILL.md |
| サポートファイル | ❌ | ✅（テンプレート、例、スクリプト） |
| 自動起動制御 | 限定的 | ✅ frontmatter で完全制御 |
| 権限設定 | 基本的 | ✅ allowed-tools など高度な設定 |
| subagent 実行 | ❌ | ✅ `context: fork` |

### ディレクトリ構造

**commands/ (旧方式):**
```
.claude/commands/
├── review.md
└── deploy.md
```

**skills/ (推奨):**
```
.claude/skills/
└── my-skill/
    ├── SKILL.md           # 必須
    ├── reference.md       # オプション
    └── examples.md        # オプション
```

### SKILL.md フロントマター

```markdown
---
name: fix-issue
description: GitHub issue を修正
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Grep, Bash
context: fork
agent: Explore
---
```

## When to Use

- **新規作成**: 常に `skills/` を使用
- **既存 commands/**: 動作し続けるが、高度な機能が必要なら移行
- **同名がある場合**: `skills/` が優先される

## Key Points

1. **既存の commands/ は動作し続ける** - 急いで移行する必要はない
2. **skills/ が公式推奨** - 新規作成はすべて skills/ で
3. **高度な機能は skills/ のみ** - subagent、権限制御、サポートファイル

## Related

- https://code.claude.com/docs/en/slash-commands
- https://code.claude.com/docs/en/best-practices
