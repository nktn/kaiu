# Technical Plan: Preview Mode Fixes

**Issue References**: #56, #57
**Branch**: `technical/56-57-preview-fixes`
**Type**: Bug Fix + Performance

---

## 概要

Preview モードに関する 2 つの問題を修正:

1. **#56**: `q` キーでプレビューが閉じずに kaiu 終了
2. **#57**: 大きな画像の表示が遅い

---

## Issue #56: Preview モードの q キー挙動

### 現状

```zig
// app.zig:443
fn handlePreviewKey(self: *Self, key_char: u21) void {
    switch (key_char) {
        'q' => self.should_quit = true,  // ← 問題
        'o', 'h' => self.closePreview(),
        ...
    }
}
```

### 修正方針

`'q'` を `closePreview()` に変更。

```zig
'q', 'o', 'h' => self.closePreview(),
```

### 影響範囲

- `src/app.zig` - handlePreviewKey のみ
- テストなし（キーハンドリングは手動確認）

---

## Issue #57: 画像ダウンサンプリング

### 現状

```zig
// app.zig:798-806
if (vaxis.zigimg.Image.fromFilePath(self.allocator, path, read_buffer)) |loaded_img| {
    // フルサイズで送信 → 4K 画像で ~25MB
    self.preview_image = self.vx.transmitImage(..., &loaded_img, .rgba);
}
```

### 修正方針

送信前にターミナルサイズに合わせてダウンサンプリング。

**アルゴリズム**: Nearest-neighbor (高速、画質中)

```zig
fn downsampleImage(
    allocator: std.mem.Allocator,
    src: *vaxis.zigimg.Image,
    max_width: u32,
    max_height: u32,
) !?vaxis.zigimg.Image
```

**ターゲットサイズ計算**:

```zig
const cell_pixel_width = 10;   // 概算
const cell_pixel_height = 20;
const max_width = win.width * cell_pixel_width;
const max_height = win.height * cell_pixel_height;
```

### 影響範囲

- `src/image.zig` - `downsampleImage` 関数を追加
- `src/app.zig` - `openImagePreview` で呼び出し

### 期待効果

| 画像サイズ | Before | After |
|-----------|--------|-------|
| 4K | ~25MB, 数秒 | ~1.4MB, 即座 |
| 8K | ~100MB, 10秒+ | ~1.4MB, 即座 |

---

## 設計判断

### Q: なぜ Nearest-neighbor?

- **高速**: O(n) ループのみ
- **十分な画質**: ターミナル表示には十分
- **シンプル**: Bilinear は計算コスト高

### Q: リサイズ後の画像のメモリ管理

- 呼び出し側で `errdefer` で解放
- 成功時は `preview_image` が所有

---

## テスト戦略

### 単体テスト

- `downsampleImage` - 既存サイズ以下、スケール計算、境界値

### 手動テスト

- プレビュー `q` で閉じる
- 4K 画像表示速度

---

## References

- architecture.md - State Machine (Preview mode)
- Issue #56 - Preview mode q bug
- Issue #57 - Image performance
