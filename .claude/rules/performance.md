# Performance Guidelines

Zig 開発におけるパフォーマンスガイドライン。

## Allocator Selection

### ArenaAllocator

一括解放が適している場合:

```zig
// GOOD: リクエスト処理など、スコープ単位で解放
pub fn handleRequest(parent_allocator: Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // この中の全割り当ては arena.deinit() で一括解放
    const data = try processData(allocator);
    const result = try transform(allocator, data);
    // 個別の free 不要
}
```

**使用場面:**
- FileTree のノード群 (全ノード同時解放)
- 一時的な文字列処理
- パース処理の中間データ

### FixedBufferAllocator

サイズが事前に分かる場合:

```zig
// GOOD: スタック上の固定バッファ
var buf: [4096]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buf);
const allocator = fba.allocator();

// ヒープ割り当てなし、高速
const path = try std.fs.path.join(allocator, &.{ dir, name });
```

### GeneralPurposeAllocator

デバッグ・開発時:

```zig
// 開発時はリーク検出に有用
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer {
    const leaked = gpa.deinit();
    if (leaked == .leak) std.debug.print("Memory leak detected!\n", .{});
}
```

## Memory Layout

### Struct of Arrays (SoA) vs Array of Structs (AoS)

```zig
// AoS - 一般的だが、キャッシュ効率が悪い場合あり
const Entry = struct {
    name: []const u8,
    size: u64,
    is_dir: bool,
};
var entries: []Entry = ...;

// SoA - 特定フィールドのみアクセスする場合に高速
const Entries = struct {
    names: [][]const u8,
    sizes: []u64,
    is_dirs: []bool,
};
```

**判断基準:**
- 全フィールド同時アクセス → AoS
- 特定フィールドのみ繰り返しアクセス → SoA

### Packed Structs

メモリ節約が重要な場合:

```zig
// パディングなし、サイズ最小化
const FileFlags = packed struct {
    is_dir: bool,
    is_hidden: bool,
    is_symlink: bool,
    is_executable: bool,
    _padding: u4 = 0,
};
// サイズ: 1 byte
```

## Avoiding Allocations

### スタック優先

```zig
// BAD: 小さなデータにヒープ割り当て
const name = try allocator.dupe(u8, short_string);
defer allocator.free(name);

// GOOD: スタックバッファ使用
var buf: [256]u8 = undefined;
const name = std.fmt.bufPrint(&buf, "{s}", .{short_string}) catch return error.NameTooLong;
```

### ArrayList の事前確保

```zig
// BAD: 何度も再割り当て
var list = std.ArrayList(Entry).init(allocator);
for (items) |item| {
    try list.append(item);  // 何度もリサイズの可能性
}

// GOOD: 事前に容量確保
var list = try std.ArrayList(Entry).initCapacity(allocator, items.len);
for (items) |item| {
    list.appendAssumeCapacity(item);  // リサイズなし
}
```

### 文字列連結

```zig
// BAD: 毎回新しい文字列を割り当て
var result = "";
for (parts) |part| {
    result = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result, part });
}

// GOOD: ArrayList で一度に構築
var buf = std.ArrayList(u8).init(allocator);
for (parts) |part| {
    try buf.appendSlice(part);
}
const result = buf.toOwnedSlice();
```

## Loop Optimization

### イテレータ vs インデックス

```zig
// GOOD: イテレータ (境界チェック最小化)
for (items) |item| {
    process(item);
}

// 必要な場合のみインデックス使用
for (items, 0..) |item, i| {
    processWithIndex(item, i);
}
```

### ループ外への移動

```zig
// BAD: ループ内で毎回計算
for (items) |item| {
    const threshold = calculateThreshold();  // 毎回同じ計算
    if (item.value > threshold) ...
}

// GOOD: ループ外で一度だけ
const threshold = calculateThreshold();
for (items) |item| {
    if (item.value > threshold) ...
}
```

## TUI Specific Performance

### 差分レンダリング

```zig
// BAD: 毎フレーム全画面再描画
fn render(vx: *vaxis.Vaxis) void {
    vx.clear();
    drawEntireScreen(vx);
}

// GOOD: 変更部分のみ更新
fn render(vx: *vaxis.Vaxis, dirty_regions: []Region) void {
    for (dirty_regions) |region| {
        drawRegion(vx, region);
    }
}
```

### イベント処理の効率化

```zig
// BAD: 全イベントで完全再計算
fn handleEvent(event: Event) void {
    recalculateEverything();
    render();
}

// GOOD: 必要な更新のみ
fn handleEvent(event: Event) void {
    switch (event) {
        .cursor_move => {
            updateCursorPosition();
            markDirty(.cursor_line);
        },
        .expand_dir => {
            updateTree();
            markDirty(.tree_view);
        },
    }
}
```

### スクロールの最適化

```zig
// 表示範囲のみ処理
fn getVisibleEntries(tree: *FileTree, scroll_offset: usize, visible_lines: usize) []Entry {
    const start = scroll_offset;
    const end = @min(scroll_offset + visible_lines, tree.entries.len);
    return tree.entries[start..end];
}
```

## File System Performance

### ディレクトリ読み込み

```zig
// 遅延読み込み (必要時のみ)
const DirNode = struct {
    children: ?[]Node,  // null = 未読み込み

    pub fn expand(self: *DirNode, allocator: Allocator) !void {
        if (self.children != null) return;  // 既に読み込み済み
        self.children = try readDirectory(allocator, self.path);
    }
};
```

### stat の最小化

```zig
// BAD: エントリごとに stat
for (dir.iterate()) |entry| {
    const stat = try dir.statFile(entry.name);
    // ...
}

// GOOD: iterate で取得できる情報を活用
for (dir.iterate()) |entry| {
    // entry.kind は stat なしで取得可能
    if (entry.kind == .directory) ...
}
```

## Profiling

### ビルトインプロファイラ

```zig
const Timer = struct {
    start: i128,

    pub fn init() Timer {
        return .{ .start = std.time.nanoTimestamp() };
    }

    pub fn elapsed(self: Timer) u64 {
        return @intCast(std.time.nanoTimestamp() - self.start);
    }
};

// 使用
var timer = Timer.init();
defer {
    const ns = timer.elapsed();
    std.debug.print("Operation took: {}ns\n", .{ns});
}
doExpensiveOperation();
```

### Release ビルドでのテスト

```bash
# パフォーマンステストは必ず Release で
zig build -Doptimize=ReleaseFast
./zig-out/bin/kaiu

# または ReleaseSafe (安全性チェック付き最適化)
zig build -Doptimize=ReleaseSafe
```

## Checklist

パフォーマンスレビュー時:

- [ ] 適切な Allocator を選択しているか
- [ ] 不要なヒープ割り当てがないか
- [ ] ループ内で毎回同じ計算をしていないか
- [ ] ArrayList は事前に容量確保しているか
- [ ] TUI は差分レンダリングしているか
- [ ] ファイル操作は遅延読み込みか
- [ ] Release ビルドでテストしたか
