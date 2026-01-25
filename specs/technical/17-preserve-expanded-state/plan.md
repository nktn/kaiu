# Technical Plan: Preserve expanded directory state during tree reload

- **Issue**: #17
- **Branch**: `technical/17-preserve-expanded-state`
- **Created**: 2026-01-25

## 概要

ファイル操作（cut/paste, copy/paste, delete など）後のツリーリロードで、展開状態を保持する。

## 背景

- 現在の `reloadTree()` は完全にツリーを再構築するため、全ての展開状態が失われる
- 深いディレクトリ構造をナビゲート中のユーザーにとって非常に不便
- PR #16 の手動テスト中に発見

## 方針

展開状態を `StringHashMap(void)` で別管理し、ツリー構築時に参照する。

**処理フロー**:
1. `expanded_paths: StringHashMap(void)` を App に追加
2. ディレクトリ展開時にパスを追加、折りたたみ時に削除
3. `readDirectory()` 時に `expanded_paths` を参照して `expanded` フラグを設定

**メリット**:
- リロード時の「収集→復元」の2パスが不要
- 展開/折りたたみ操作が O(1) で済む

## 影響範囲

### 変更対象ファイル

| ファイル | 変更内容 |
|---------|---------|
| `src/app.zig` | `expanded_paths` フィールド追加、展開/折りたたみ時の更新 |
| `src/tree.zig` | `readDirectory()` に `expanded_paths` を渡して参照 |

### 影響を受ける操作

- `reloadTree()` を呼び出す全ての操作:
  - `R` キー（手動リロード）
  - Paste 操作後
  - Delete 操作後
  - その他ファイル変更操作

## 設計判断

### 判断1: 展開状態の管理方法

**選択肢**:
- A: リロード時にイテレートして収集→復元（2パス）
- B: `StringHashMap(void)` で常に管理（1パス）

**決定**: B（常に管理）

**理由**:
- リロード時の処理がシンプル
- 展開/折りたたみ時の更新コストは O(1)
- VS Code など他のアプリでも同様のアプローチ

### 判断2: expanded_paths の所有権

**選択肢**:
- A: App が所有し、tree.zig に参照を渡す
- B: FileTree が所有

**決定**: A（App が所有）

**理由**: FileTree はリロード時に再作成される可能性があるため、上位で管理

### 判断3: 存在しないパスの扱い

**決定**: 削除操作時に `expanded_paths` から該当パスを削除

**理由**: 不要なエントリが蓄積しない

## リスク・懸念事項

- **メモリ使用量**: 多数のディレクトリを展開した場合、HashMapのサイズが増加
  - 対策: 通常のユースケースでは問題にならない程度と想定

## 参照

- Issue: #17
- 関連 PR: #16 (テスト中に発見)
