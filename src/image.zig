//! Image format detection and metadata extraction module.
//!
//! Used to detect image files and extract dimensions for preview display.
//! Supports PNG, JPG, GIF, and WebP formats.

const std = @import("std");

/// Supported image formats.
pub const ImageFormat = enum {
    png,
    jpg,
    gif,
    webp,
    unknown,
};

/// Image dimensions.
pub const ImageDimensions = struct {
    width: u32,
    height: u32,
};

/// Magic bytes for image format detection.
const PNG_MAGIC = [_]u8{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
const JPG_MAGIC = [_]u8{ 0xFF, 0xD8, 0xFF };
const GIF_MAGIC = "GIF8";
const WEBP_MAGIC = "RIFF";
const WEBP_FOURCC = "WEBP";

/// Detect image format from file extension and magic bytes.
/// Returns .unknown if not a recognized image format.
pub fn detectImageFormat(path: []const u8) ImageFormat {
    // Check extension first
    const ext = getExtension(path);
    const format_from_ext = formatFromExtension(ext);

    // For known extensions, verify with magic bytes if possible
    if (format_from_ext != .unknown) {
        const verified = verifyMagicBytes(path, format_from_ext);
        if (verified) return format_from_ext;
        // If magic bytes don't match, still trust the extension
        // (file might be corrupted or truncated)
        return format_from_ext;
    }

    // Unknown extension, try magic bytes
    return detectFromMagicBytes(path);
}

/// Get lowercase file extension.
fn getExtension(path: []const u8) []const u8 {
    const basename = std.fs.path.basename(path);
    const dot_index = std.mem.lastIndexOf(u8, basename, ".") orelse return "";
    return basename[dot_index + 1 ..];
}

/// Map file extension to image format.
fn formatFromExtension(ext: []const u8) ImageFormat {
    if (eqlIgnoreCase(ext, "png")) return .png;
    if (eqlIgnoreCase(ext, "jpg") or eqlIgnoreCase(ext, "jpeg")) return .jpg;
    if (eqlIgnoreCase(ext, "gif")) return .gif;
    if (eqlIgnoreCase(ext, "webp")) return .webp;
    return .unknown;
}

/// Case-insensitive string comparison.
fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }
    return true;
}

/// Verify format by reading magic bytes.
fn verifyMagicBytes(path: []const u8, expected: ImageFormat) bool {
    var file = std.fs.openFileAbsolute(path, .{}) catch return false;
    defer file.close();

    var buf: [12]u8 = undefined;
    const bytes_read = file.read(&buf) catch return false;
    if (bytes_read == 0) return false;

    return switch (expected) {
        .png => bytes_read >= 8 and std.mem.eql(u8, buf[0..8], &PNG_MAGIC),
        .jpg => bytes_read >= 3 and std.mem.eql(u8, buf[0..3], &JPG_MAGIC),
        .gif => bytes_read >= 4 and std.mem.eql(u8, buf[0..4], GIF_MAGIC),
        .webp => bytes_read >= 12 and std.mem.eql(u8, buf[0..4], WEBP_MAGIC) and std.mem.eql(u8, buf[8..12], WEBP_FOURCC),
        .unknown => false,
    };
}

/// Detect format from magic bytes only.
fn detectFromMagicBytes(path: []const u8) ImageFormat {
    var file = std.fs.openFileAbsolute(path, .{}) catch return .unknown;
    defer file.close();

    var buf: [12]u8 = undefined;
    const bytes_read = file.read(&buf) catch return .unknown;
    if (bytes_read < 4) return .unknown;

    if (bytes_read >= 8 and std.mem.eql(u8, buf[0..8], &PNG_MAGIC)) return .png;
    if (bytes_read >= 3 and std.mem.eql(u8, buf[0..3], &JPG_MAGIC)) return .jpg;
    if (std.mem.eql(u8, buf[0..4], GIF_MAGIC)) return .gif;
    if (bytes_read >= 12 and std.mem.eql(u8, buf[0..4], WEBP_MAGIC) and std.mem.eql(u8, buf[8..12], WEBP_FOURCC)) return .webp;

    return .unknown;
}

/// Get image dimensions from file.
/// Returns null if the file cannot be read or parsed.
pub fn getImageDimensions(path: []const u8) ?ImageDimensions {
    const format = detectImageFormat(path);
    return switch (format) {
        .png => getPngDimensions(path),
        .jpg => getJpgDimensions(path),
        .gif => getGifDimensions(path),
        .webp => getWebpDimensions(path),
        .unknown => null,
    };
}

/// Read PNG dimensions from IHDR chunk.
fn getPngDimensions(path: []const u8) ?ImageDimensions {
    var file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    // Skip PNG signature (8 bytes)
    file.seekTo(8) catch return null;

    // Read IHDR chunk: length (4) + type (4) + data (width 4 + height 4 + ...)
    var buf: [24]u8 = undefined;
    const bytes_read = file.read(&buf) catch return null;
    if (bytes_read < 16) return null;

    // Verify IHDR chunk type
    if (!std.mem.eql(u8, buf[4..8], "IHDR")) return null;

    // Width and height are big-endian u32
    const width = std.mem.readInt(u32, buf[8..12], .big);
    const height = std.mem.readInt(u32, buf[12..16], .big);

    return .{ .width = width, .height = height };
}

/// Read JPG dimensions from SOF marker.
/// Handles 0xFF padding bytes that may appear between markers.
fn getJpgDimensions(path: []const u8) ?ImageDimensions {
    var file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    // Skip SOI marker (0xFF 0xD8)
    file.seekTo(2) catch return null;

    var buf: [9]u8 = undefined;
    var iterations: usize = 0;
    const max_iterations: usize = 1000; // Prevent infinite loops on malformed files

    // Scan for SOF0 or SOF2 marker
    while (iterations < max_iterations) : (iterations += 1) {
        // Read marker byte
        if ((file.read(buf[0..1]) catch return null) != 1) return null;

        // Skip padding 0xFF bytes (valid per JPEG spec)
        while (buf[0] == 0xFF) {
            if ((file.read(buf[0..1]) catch return null) != 1) return null;
            // If we hit 0x00, it's an escaped 0xFF in data - shouldn't happen in marker area
            if (buf[0] == 0x00) return null;
        }

        const marker = buf[0];

        // EOI (End of Image) - no SOF found
        if (marker == 0xD9) return null;

        // SOF markers: SOF0 (0xC0), SOF1 (0xC1), SOF2 (0xC2), SOF3 (0xC3)
        // SOF5-7 (0xC5-0xC7), SOF9-11 (0xC9-0xCB), SOF13-15 (0xCD-0xCF)
        // All contain image dimensions in the same format
        if ((marker >= 0xC0 and marker <= 0xC3) or
            (marker >= 0xC5 and marker <= 0xC7) or
            (marker >= 0xC9 and marker <= 0xCB) or
            (marker >= 0xCD and marker <= 0xCF))
        {
            // Read length + precision + height + width
            if ((file.read(buf[0..7]) catch return null) != 7) return null;

            const height = std.mem.readInt(u16, buf[3..5], .big);
            const width = std.mem.readInt(u16, buf[5..7], .big);

            return .{ .width = width, .height = height };
        }

        // Standalone markers (no length field): RST0-7, SOI, EOI, TEM
        if ((marker >= 0xD0 and marker <= 0xD7) or marker == 0xD8 or marker == 0x01) {
            continue; // No segment to skip
        }

        // Read segment length and skip
        if ((file.read(buf[0..2]) catch return null) != 2) return null;
        const length = std.mem.readInt(u16, buf[0..2], .big);
        if (length < 2) return null;
        file.seekBy(@as(i64, length) - 2) catch return null;
    }

    return null; // Max iterations reached
}

/// Read GIF dimensions from Logical Screen Descriptor.
fn getGifDimensions(path: []const u8) ?ImageDimensions {
    var file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    // Skip signature and version (6 bytes: GIF87a or GIF89a)
    file.seekTo(6) catch return null;

    // Read width and height (little-endian u16)
    var buf: [4]u8 = undefined;
    if ((file.read(&buf) catch return null) != 4) return null;

    const width = std.mem.readInt(u16, buf[0..2], .little);
    const height = std.mem.readInt(u16, buf[2..4], .little);

    return .{ .width = width, .height = height };
}

/// Read WebP dimensions from VP8/VP8L/VP8X chunk.
fn getWebpDimensions(path: []const u8) ?ImageDimensions {
    var file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    // Skip RIFF header (12 bytes: RIFF + size + WEBP)
    file.seekTo(12) catch return null;

    var buf: [10]u8 = undefined;

    // Read chunk header
    if ((file.read(buf[0..8]) catch return null) != 8) return null;

    // VP8X (extended format)
    if (std.mem.eql(u8, buf[0..4], "VP8X")) {
        // Skip flags (4 bytes), read canvas width/height
        if ((file.read(buf[0..10]) catch return null) != 10) return null;

        // Width and height are 24-bit little-endian, stored as (value - 1)
        const width: u32 = @as(u32, buf[4]) | (@as(u32, buf[5]) << 8) | (@as(u32, buf[6]) << 16);
        const height: u32 = @as(u32, buf[7]) | (@as(u32, buf[8]) << 8) | (@as(u32, buf[9]) << 16);

        return .{ .width = width + 1, .height = height + 1 };
    }

    // VP8L (lossless)
    if (std.mem.eql(u8, buf[0..4], "VP8L")) {
        // Skip chunk size (already read), read signature and dimensions
        if ((file.read(buf[0..5]) catch return null) != 5) return null;

        // Signature should be 0x2F
        if (buf[0] != 0x2F) return null;

        // Dimensions are packed: 14 bits width-1, 14 bits height-1
        const bits: u32 = @as(u32, buf[1]) | (@as(u32, buf[2]) << 8) | (@as(u32, buf[3]) << 16) | (@as(u32, buf[4]) << 24);
        const width = (bits & 0x3FFF) + 1;
        const height = ((bits >> 14) & 0x3FFF) + 1;

        return .{ .width = width, .height = height };
    }

    // VP8 (lossy)
    if (std.mem.eql(u8, buf[0..4], "VP8 ")) {
        // Skip chunk size (4 bytes) and frame tag (3 bytes)
        file.seekBy(7) catch return null;

        // Read start code and dimensions
        if ((file.read(buf[0..7]) catch return null) != 7) return null;

        // Start code should be 0x9D 0x01 0x2A
        if (buf[0] != 0x9D or buf[1] != 0x01 or buf[2] != 0x2A) return null;

        const width = std.mem.readInt(u16, buf[3..5], .little) & 0x3FFF;
        const height = std.mem.readInt(u16, buf[5..7], .little) & 0x3FFF;

        return .{ .width = width, .height = height };
    }

    return null;
}

/// Check if a path is an image file based on extension.
pub fn isImageFile(path: []const u8) bool {
    const ext = getExtension(path);
    return formatFromExtension(ext) != .unknown;
}

/// Maximum file size for image preview (10MB per spec).
pub const MAX_IMAGE_SIZE: u64 = 10 * 1024 * 1024;

/// Check if image file is too large for preview.
pub fn isImageTooLarge(path: []const u8) bool {
    const file = std.fs.openFileAbsolute(path, .{}) catch return false;
    defer file.close();

    const stat = file.stat() catch return false;
    return stat.size > MAX_IMAGE_SIZE;
}

test "formatFromExtension recognizes common extensions" {
    try std.testing.expectEqual(ImageFormat.png, formatFromExtension("png"));
    try std.testing.expectEqual(ImageFormat.png, formatFromExtension("PNG"));
    try std.testing.expectEqual(ImageFormat.jpg, formatFromExtension("jpg"));
    try std.testing.expectEqual(ImageFormat.jpg, formatFromExtension("jpeg"));
    try std.testing.expectEqual(ImageFormat.gif, formatFromExtension("gif"));
    try std.testing.expectEqual(ImageFormat.webp, formatFromExtension("webp"));
    try std.testing.expectEqual(ImageFormat.unknown, formatFromExtension("txt"));
}

test "getExtension extracts extension correctly" {
    try std.testing.expectEqualStrings("png", getExtension("/path/to/image.png"));
    try std.testing.expectEqualStrings("jpg", getExtension("photo.jpg"));
    try std.testing.expectEqualStrings("", getExtension("no_extension"));
    try std.testing.expectEqualStrings("gif", getExtension(".hidden.gif"));
}

test "isImageFile detects image files" {
    try std.testing.expect(isImageFile("test.png"));
    try std.testing.expect(isImageFile("test.JPG"));
    try std.testing.expect(isImageFile("test.gif"));
    try std.testing.expect(isImageFile("test.webp"));
    try std.testing.expect(!isImageFile("test.txt"));
    try std.testing.expect(!isImageFile("test.md"));
}
