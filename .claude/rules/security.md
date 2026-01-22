# Security Guidelines

Zig 開発におけるセキュリティガイドライン。

## Mandatory Security Checks

コミット前に必ず確認:

- [ ] ハードコードされた秘密情報がない (API キー、パスワード、トークン)
- [ ] ユーザー入力が検証されている
- [ ] ファイルパスが適切にサニタイズされている
- [ ] メモリが適切に管理されている (defer/errdefer)
- [ ] エラーメッセージに機密情報が含まれていない

## Secret Management

```zig
// NEVER: ハードコードされた秘密情報
const api_key = "sk-proj-xxxxx";

// ALWAYS: 環境変数から取得
const api_key = std.posix.getenv("API_KEY") orelse return error.MissingApiKey;
```

### 設定ファイル

```zig
// 設定ファイルのパス
// NEVER: ホームディレクトリ直下に平文で保存
const config_path = "~/.myapp_secrets";

// ALWAYS: XDG 準拠 + 適切なパーミッション
const config_dir = std.posix.getenv("XDG_CONFIG_HOME") orelse {
    const home = std.posix.getenv("HOME") orelse return error.NoHome;
    break :blk try std.fs.path.join(allocator, &.{ home, ".config" });
};
```

## Input Validation

### ファイルパス検証

```zig
// NEVER: ユーザー入力をそのまま使用
fn openFile(path: []const u8) !std.fs.File {
    return std.fs.cwd().openFile(path, .{});
}

// ALWAYS: パストラバーサル攻撃を防ぐ
fn openFileSafe(path: []const u8) !std.fs.File {
    // 絶対パスに正規化
    const real_path = try std.fs.cwd().realpathAlloc(allocator, path);
    defer allocator.free(real_path);

    // 許可されたディレクトリ内かチェック
    if (!std.mem.startsWith(u8, real_path, allowed_base_path)) {
        return error.AccessDenied;
    }

    return std.fs.openFileAbsolute(real_path, .{});
}
```

### シンボリックリンク

```zig
// シンボリックリンクの扱いに注意
const stat = try dir.statFile(entry.name);
if (stat.kind == .sym_link) {
    // シンボリックリンクは慎重に扱う
    // 外部ディレクトリへのリンクの可能性
}
```

## Memory Safety

### Allocator の適切な使用

```zig
// ALWAYS: errdefer で失敗時のクリーンアップ
pub fn init(allocator: Allocator) !*Self {
    const self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.data = try allocator.alloc(u8, size);
    errdefer allocator.free(self.data);

    return self;
}

// ALWAYS: defer で成功時のクリーンアップパス確保
pub fn deinit(self: *Self, allocator: Allocator) void {
    allocator.free(self.data);
    allocator.destroy(self);
}
```

### バッファオーバーフロー防止

```zig
// NEVER: 固定サイズバッファに無検証でコピー
var buf: [256]u8 = undefined;
@memcpy(&buf, user_input);

// ALWAYS: サイズチェック
var buf: [256]u8 = undefined;
if (user_input.len > buf.len) {
    return error.InputTooLong;
}
@memcpy(buf[0..user_input.len], user_input);
```

### Use-After-Free 防止

```zig
// NEVER: 解放後のポインタ使用
allocator.free(data);
process(data);  // 危険！

// ALWAYS: 解放後は即座に無効化
allocator.free(data);
data = undefined;  // または null に設定
```

## Error Handling Security

### 情報漏洩防止

```zig
// NEVER: 詳細なシステム情報をユーザーに表示
fn handleError(err: anyerror) void {
    std.debug.print("Error: {s} at {s}:{d}\n", .{
        @errorName(err),
        @src().file,
        @src().line,
    });
}

// ALWAYS: ユーザー向けには一般的なメッセージ
fn handleError(err: anyerror) []const u8 {
    // ログには詳細を記録
    log.err("Internal error: {}", .{err});

    // ユーザーには一般的なメッセージ
    return switch (err) {
        error.AccessDenied => "Permission denied",
        error.FileNotFound => "File not found",
        else => "An error occurred",
    };
}
```

## File System Security

### 権限チェック

```zig
// ファイル操作前に権限確認
const stat = try file.stat();
const mode = stat.mode;

// 書き込み可能かチェック
const is_writable = (mode & std.posix.S.IWUSR) != 0;
```

### 一時ファイル

```zig
// NEVER: 予測可能な一時ファイル名
const tmp_path = "/tmp/myapp_temp";

// ALWAYS: 安全な一時ファイル作成
const tmp_dir = std.fs.openDirAbsolute("/tmp", .{}) catch |err| {
    return error.TmpDirUnavailable;
};
defer tmp_dir.close();

// ランダムな名前で作成
var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
const random = prng.random();
```

## TUI Specific Security

### ターミナルエスケープシーケンス

```zig
// ユーザー入力をそのまま表示しない
// ANSI エスケープシーケンスインジェクション防止

fn sanitizeForDisplay(input: []const u8) []const u8 {
    // ESC (0x1B) を含む入力は危険
    for (input) |c| {
        if (c == 0x1B or c < 0x20) {
            return "[invalid input]";
        }
    }
    return input;
}
```

### シェルコマンド実行

```zig
// NEVER: ユーザー入力をシェルコマンドに渡す
const cmd = try std.fmt.allocPrint(allocator, "ls {s}", .{user_path});
_ = try std.process.Child.run(.{ .argv = &.{ "sh", "-c", cmd } });

// ALWAYS: 引数として渡す（シェル解釈を避ける）
_ = try std.process.Child.run(.{ .argv = &.{ "ls", "--", user_path } });
```

## Security Response Protocol

セキュリティ問題発見時:

1. **即座に停止** - 問題のあるコードをコミットしない
2. **影響範囲を特定** - どのデータ/機能が影響を受けるか
3. **修正を優先** - 他の機能より先にセキュリティ修正
4. **レビュー依頼** - セキュリティ関連の変更は必ずレビュー

## Checklist for Code Review

セキュリティ観点でのレビューチェック:

- [ ] 全ての allocator.alloc に対応する free がある
- [ ] errdefer が適切に配置されている
- [ ] ユーザー入力は検証後に使用されている
- [ ] ファイルパスはサニタイズされている
- [ ] エラーメッセージに内部情報が含まれていない
- [ ] シェルコマンド実行時にインジェクション対策がある
- [ ] 一時ファイルは安全に作成されている
