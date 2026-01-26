# Tasks: Preview Mode Fixes

**Issue References**: #56, #57
**Branch**: `technical/56-57-preview-fixes`

---

## Phase 1: Bug Fix (#56)

### T001: Fix q key behavior in preview mode

**Priority**: P1 (Bug)
**Files**: `src/app.zig`

**Current** (line 443):
```zig
'q' => self.should_quit = true,
```

**Target**:
```zig
'q', 'o', 'h' => self.closePreview(),
```

**Acceptance**:
- [ ] Preview モードで `q` を押すとプレビューが閉じる
- [ ] TreeView に戻る
- [ ] kaiu は終了しない

---

## Phase 2: Performance (#57)

### T002: Add downsampleImage function to image.zig

**Priority**: P1 (Performance)
**Files**: `src/image.zig`

**Implementation**:

```zig
/// Downsample image using nearest-neighbor sampling.
/// Returns null if resize not needed (image already fits).
pub fn downsampleImage(
    allocator: std.mem.Allocator,
    src: anytype,
    max_width: u32,
    max_height: u32,
) !?DownsampledImage {
    // Calculate scale
    // Allocate new pixel buffer
    // Nearest-neighbor sampling loop
    // Return new image or null
}
```

**Test Cases**:
- [ ] Image smaller than max → returns null (no resize)
- [ ] Image larger than max → returns resized image
- [ ] Scale calculation correct
- [ ] Memory properly allocated

### T003: Integrate downsampleImage into openImagePreview

**Priority**: P1
**Files**: `src/app.zig`
**Depends**: T002

**Implementation**:

```zig
fn openImagePreview(self: *Self, path: []const u8) void {
    // ... load image ...

    // Calculate target size from terminal dimensions
    const win = self.vx.window();
    const max_width = win.width * 10;  // ~10px per cell
    const max_height = win.height * 20; // ~20px per cell

    // Downsample if needed
    const resized = image.downsampleImage(
        self.allocator,
        &loaded_img,
        max_width,
        max_height,
    ) catch null;
    defer if (resized) |r| r.deinit(self.allocator);

    const img_to_transmit = resized orelse &loaded_img;

    // Transmit (resized or original)
    self.preview_image = self.vx.transmitImage(..., img_to_transmit, .rgba);
}
```

**Acceptance**:
- [ ] 4K 画像が即座に表示される
- [ ] 小さな画像はそのまま表示される
- [ ] メモリリークなし

---

## Phase 3: Documentation

### T004: Update architecture.md

**Files**: `.claude/rules/architecture.md`

**Updates**:
- [ ] State Transitions: Preview `q` → TreeView (not Quit)
- [ ] image.zig module description (if needed)

### T005: Manual testing & verify

**Acceptance**:
- [ ] `zig build` 成功
- [ ] `zig build test` 成功
- [ ] Preview モード `q` でプレビュー閉じる
- [ ] 大きな画像が高速表示

---

## Summary

| Task | Description | Priority | Status |
|------|-------------|----------|--------|
| T001 | Fix q key in preview mode | P1 | [ ] |
| T002 | Add downsampleImage | P1 | [ ] |
| T003 | Integrate into openImagePreview | P1 | [ ] |
| T004 | Update documentation | P2 | [ ] |
| T005 | Manual testing | P1 | [ ] |

**Closes**: #56, #57
