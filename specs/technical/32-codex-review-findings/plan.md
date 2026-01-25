# Technical Plan: Codex Review Findings (PR #27)

## 概要

PR #27 の Codex レビューで発見された既存コードの問題を修正する。

## 発見経緯

Codex review (PR #27) で指摘された潜在的な問題点。

## 影響範囲

- `src/app.zig` のみ

## タスク別設計

### HIGH: Symlink handling in copyDirRecursive

**問題**: `copyDirRecursive` で symlink がスキップされ、cut 操作のクロスデバイスフォールバック時にデータロスが発生する可能性。

**現状** (app.zig:1864-1870):
```zig
fn copyDirRecursive(src_path: []const u8, dest_path: []const u8) !void {
    // Security: Check if source is a symlink
    var link_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (std.fs.cwd().readLink(src_path, &link_buf)) |_| {
        // Skip symlinks during copy
        return;
    } else |_| {}
```

**対策**: symlink を保存してコピーする。
- `std.fs.cwd().readLink()` で symlink ターゲットを取得
- `std.posix.symlink()` で新しい symlink を作成
- 既存の symlink skip をエラーではなくコピー動作に変更

### MEDIUM: Suffix limit in paste conflict resolution

**問題**: ペースト時のファイル名衝突解決で suffix > 100 になると探索停止、既存ファイルを上書きする可能性。

**現状** (app.zig:1128):
```zig
if (suffix > 100) break; // Safety limit
```

**対策**: 上限に達した場合はエラーを返す。
- `break` の代わりに `return error.TooManyConflicts` を返す
- paste 時に適切なエラーメッセージを表示

### LOW: Search mode stale counts

**問題**: 検索モード開始時に `search_matches`/`current_match` がクリアされない。

**現状** (app.zig:785-788):
```zig
fn enterSearchMode(self: *Self) void {
    self.input_buffer.clearRetainingCapacity();
    self.mode = .search;
}
```

**対策**: 検索モード開始時に検索状態をリセット。
```zig
fn enterSearchMode(self: *Self) void {
    self.input_buffer.clearRetainingCapacity();
    self.search_matches.clearRetainingCapacity();
    self.current_match = 0;
    self.mode = .search;
}
```

### LOW: ESC key behavior

**問題**: ヒントでは ESC でマーククリアと表示されるが、実際は検索のみクリア。

**現状分析**:
- ヒント (app.zig:1761): `"Space:unmark  y:yank  d:cut  D:delete  Esc:clear marks"`
- 実際 (app.zig:329-334): ESC は検索のみクリア

**対策**: ヒント表示とコードを一致させる。
- 検索アクティブ時: ESC で検索クリア
- マークあり時: ESC でマーククリア (検索はそのまま)
- 両方ある時: ESC でマークをクリア (2回押しで検索もクリア)

## テスト戦略

各修正に対してユニットテストを追加:
1. symlink のコピーが正しく動作することを確認
2. suffix > 100 時のエラー処理を確認
3. 検索モード開始時の状態リセットを確認
4. ESC キー動作の各シナリオを確認
