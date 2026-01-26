---
name: libvaxis-bracketed-paste-utf8-limitation
description: libvaxis bracketed paste events may corrupt UTF-8 multibyte characters
---

# libvaxis Bracketed Paste UTF-8 Limitation

**Extracted:** 2026-01-26
**Context:** When implementing drag & drop file paths via bracketed paste events in TUI applications using libvaxis

## Problem

When receiving pasted content via libvaxis bracketed paste events, UTF-8 multibyte characters (e.g., Japanese, Chinese, emoji) may be corrupted or replaced with U+FFFD (replacement character).

**Symptoms:**
- ASCII filenames paste correctly
- Non-ASCII filenames (Japanese: `テスト.txt`, emoji: `📁 folder`) become garbled or unreadable
- UTF-8 encoding appears correct in terminal but libvaxis delivers corrupted codepoints

**Example:**
```zig
// Finder drops: /Users/test/日本語ファイル.txt
// libvaxis paste event delivers: /Users/test/���.txt
// (U+FFFD replacement characters)
```

## Root Cause

libvaxis's bracketed paste implementation processes key events character-by-character:
- Each key press event contains a single codepoint
- Multi-byte UTF-8 sequences may be split across multiple key events
- Some codepoints are incorrectly interpreted as U+FFFD during reassembly

**Related Issues:**
- [bemenu #410](https://github.com/Cloudef/bemenu/issues/410) - Similar UTF-8 paste corruption in other TUI frameworks

## Workaround

### 1. Document Limitation

Clearly state ASCII-only support for paste/drop operations:

```markdown
## Known Limitations
- Drag & drop only supports ASCII filenames
- Use internal yank/paste (y/p) for non-ASCII files
```

### 2. Add UTF-8 Encoding Attempt

Even though libvaxis may deliver corrupted codepoints, always encode them as UTF-8 to preserve whatever can be salvaged:

```zig
// During bracketed paste
if (self.is_pasting) {
    // Encode codepoint as UTF-8 to support non-ASCII characters
    // Note: May still fail for non-ASCII due to libvaxis limitation
    if (key.codepoint > 0 and key.codepoint <= 0x10FFFF) {
        var utf8_buf: [4]u8 = undefined;
        const codepoint: u21 = @intCast(key.codepoint);
        const len = std.unicode.utf8Encode(codepoint, &utf8_buf) catch 0;
        if (len > 0) {
            try self.paste_buffer.appendSlice(self.allocator, utf8_buf[0..len]);
        }
    }
}
```

### 3. Provide Alternative Path

Offer a working alternative for non-ASCII filenames:

```zig
// Internal file operations with proper UTF-8 handling
- y (yank): Copy file paths using internal clipboard
- p (paste): Paste using internal clipboard
```

## When to Use This Workaround

**Use when:**
- Implementing drag & drop or paste operations in libvaxis TUI apps
- Users need to work with files that may have non-ASCII names
- You cannot modify libvaxis itself

**Alternative:**
- Contribute a fix to libvaxis to properly handle UTF-8 sequences during bracketed paste
- Use a different TUI library with proper UTF-8 paste support
- Avoid bracketed paste entirely and use alternative drop mechanisms (if available)

## Testing Strategy

```bash
# Test ASCII filenames (should work)
touch "test file.txt"
# Drag to TUI app → ✓ Works

# Test UTF-8 filenames (will fail)
touch "日本語.txt"
# Drag to TUI app → ✗ Corrupted

# Verify workaround
# Inside TUI: mark file, press y (yank), navigate, press p (paste)
# → ✓ Should work for all filenames
```

## Trade-offs

| Aspect | Impact |
|--------|--------|
| **User Experience** | Degraded for non-ASCII filenames |
| **Code Complexity** | Minimal - just documentation + encoding attempt |
| **Maintenance** | Low - workaround is stable until libvaxis fix |
| **Compatibility** | Good - doesn't break ASCII use cases |

## Future Improvements

1. **Monitor libvaxis issues** - Check for upstream fixes
2. **Contribute fix** - If feasible, submit PR to libvaxis
3. **Alternative protocols** - Consider non-paste-based drop mechanisms
4. **Validation layer** - Detect corruption and warn user

## References

- [bemenu #410](https://github.com/Cloudef/bemenu/issues/410) - Similar UTF-8 paste issue
- kaiu Issue #61 - Finder drag & drop fix
- libvaxis bracketed paste implementation: `Tty.nextEvent()` key processing
