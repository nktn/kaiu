# Technical Plan: Phase 3.5 spec.md にペルソナセクションを追加

**Issue**: #71
**Branch**: `verify-phase35-persona`
**Created**: 2026-01-29

## 概要

Phase 3.5 (`specs/feature/045-ui-ux-enhancements/spec.md`) に Target Persona セクションがないため、他の Feature Specification との一貫性を保つために追加する。

## 背景

他の Feature Specification には Target Persona セクションがあり、ユーザー像（田中さん）の背景、ニーズ、コンテキストが記載されている:

| Spec | Persona セクション |
|------|-------------------|
| Phase 1 (001-tree-view) | ✅ あり |
| Phase 2 (002-file-operations) | ✅ あり |
| Phase 3 (003-external-integration) | ✅ あり |
| **Phase 3.5 (045-ui-ux-enhancements)** | ❌ **なし** |

## 方針

### 1. Target Persona セクションを追加

`## Overview` の後に `## Target Persona` セクションを挿入:

```markdown
## Target Persona

**田中さん (Phase 1-3 から継続)**
- Phase 3 でドラッグ&ドロップを活用し、GUI と TUI のハイブリッド運用が定着
- Vim キーバインドに慣れたが、外部からファイルを取り込んだ直後など
  マウスから手を離さずに操作できると便利だと感じている
- VSCode のようにマウスでもキーボードでも操作できる柔軟性が欲しい
```

### 2. US1 の User Story を修正

現在の記載:
> キーボード操作に慣れていないユーザーでも直感的に操作できる。

修正後:
> Phase 3 でドラッグ&ドロップを使った後、そのままマウスでファイルを選択・操作できる。GUI 操作の流れを切らない。

## 影響範囲

- `specs/feature/045-ui-ux-enhancements/spec.md` のみ
- コード変更なし
- 他ファイルへの影響なし

## 検証方法

- spec.md に Target Persona セクションがあることを確認
- US1 の User Story が田中さんのコンテキストと一致していることを確認
