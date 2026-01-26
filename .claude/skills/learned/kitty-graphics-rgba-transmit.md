---
name: kitty-graphics-rgba-transmit
description: RGBA format transmission for Kitty Graphics Protocol
---

# Kitty Graphics RGBA Transmit Pattern

**Extracted:** 2026-01-26
**Context:** Displaying images in terminal via Kitty Graphics Protocol

## Problem

PNG/JPG/GIF images need to be converted to raw RGBA format before transmission to the terminal. The Kitty Graphics Protocol requires:
- Raw pixel data in RGBA format (4 bytes per pixel)
- Base64 encoding of pixel data
- Chunked transmission with specific escape sequences

## Solution

1. **Decode image to RGBA**:
   - Use image library (stb_image, libpng, etc.) to decode
   - Convert all formats to 32-bit RGBA
   - Handle transparency: RGB images get alpha=255

2. **Transmit via escape sequences**:
   ```zig
   // Start transmission
   // Format: ESC _G <control_data> ; <base64_data> ESC \
   try writer.print("\x1b_Gf=32,t=d,a=T,i={d},w={d},h={d};", .{
       image_id,
       width,
       height,
   });

   // Send base64-encoded RGBA data in chunks
   const chunk_size = 4096;
   var offset: usize = 0;
   while (offset < rgba_data.len) {
       const end = @min(offset + chunk_size, rgba_data.len);
       const chunk = rgba_data[offset..end];

       const encoded = try base64Encode(allocator, chunk);
       defer allocator.free(encoded);

       const more = if (end < rgba_data.len) 'm=1' else 'm=0';
       try writer.print("\x1b_G{s};{s}\x1b\\", .{ more, encoded });

       offset = end;
   }
   ```

3. **Control data parameters**:
   - `f=32`: Format is RGBA (32 bits per pixel)
   - `t=d`: Direct transmission (not file path)
   - `a=T`: Transmission medium (temporary)
   - `i=<id>`: Image ID for placement
   - `w=<width>`: Width in pixels
   - `h=<height>`: Height in pixels
   - `m=1`: More chunks follow (m=0 for last chunk)

## When to Use

**Use this pattern when:**
- Implementing image preview in TUI applications
- Targeting Kitty or compatible terminals (Ghostty, WezTerm)
- Need to display images without external tools

**Do NOT use when:**
- Terminal doesn't support Kitty Graphics Protocol
- Images are very large (>10MB) - use file paths or sixel instead
- ASCII art fallback is sufficient

## Alternative Approaches

### File Path Transmission (f=100)
```zig
// Instead of base64 data, send file path
try writer.print("\x1b_Gf=100,t=f,a=T,i={d};{s}\x1b\\", .{
    image_id,
    base64EncodedPath,
});
```
**Pros:** No need to decode image, smaller transmission
**Cons:** Terminal must have access to file path, doesn't work with remote sessions

### Sixel Protocol
- Older protocol, wider terminal support
- More complex encoding
- Lower color depth (typically 256 colors vs 16M)

## Implementation Notes

### Memory Management
```zig
// RGBA data is typically large - use arena or ensure cleanup
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();

const rgba_data = try decodeImageToRGBA(arena.allocator(), path);
// arena.deinit() frees all at once
```

### Error Handling
- Terminal may not support the protocol → detect before transmitting
- Image decode may fail → have ASCII fallback
- Transmission errors are silent → no ACK from terminal

### Performance
- Base64 encoding adds ~33% overhead
- Large images (>1MB) may cause lag → resize before transmitting
- Chunking prevents output buffer overflow

## References

- [Kitty Graphics Protocol Spec](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
- Ghostty: Compatible with Kitty protocol
- WezTerm: Partial support (RGBA format supported)

## Related Patterns

- `.claude/skills/learned/ghostty-terminal-detection.md` - Detecting terminal capabilities
- Image resizing before transmission (not yet documented)
- Sixel fallback pattern (not yet documented)
