const std = @import("std");

/// Icon representation for Nerd Font display (Phase 3.5 - US4: T025)
/// FR-030, FR-031, FR-032, FR-034, FR-035
pub const Icon = struct {
    /// Nerd Font Unicode codepoint
    codepoint: u21,
    /// ANSI color index (null for default terminal color)
    color: ?u8,

    /// Convert codepoint to UTF-8 string
    pub fn toUtf8(self: Icon) [4]u8 {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(self.codepoint, &buf) catch {
            // Fallback to replacement character
            buf[0] = 0xEF;
            buf[1] = 0xBF;
            buf[2] = 0xBD;
            buf[3] = 0;
            return buf;
        };
        // Zero-pad remaining bytes
        for (len..4) |i| {
            buf[i] = 0;
        }
        return buf;
    }

    /// Get UTF-8 string slice (without trailing zeros)
    pub fn toSlice(self: Icon) []const u8 {
        const buf = self.toUtf8();
        const len = std.unicode.utf8CodepointSequenceLength(self.codepoint) catch 3;
        return buf[0..len];
    }
};

// ===== Directory Icons (T024) =====
/// Closed folder icon (FR-031)
pub const folder_closed = Icon{ .codepoint = 0xf07b, .color = 4 }; //
/// Open folder icon (FR-031)
pub const folder_open = Icon{ .codepoint = 0xf07c, .color = 4 }; //

// ===== Default File Icon (FR-034) =====
pub const file_default = Icon{ .codepoint = 0xf15b, .color = null }; //

// ===== Extension Mapping (T026, FR-030) =====
/// Map file extensions to icons (comptime, zero runtime allocation)
/// SC-004: 20+ file types supported
pub const extension_icons = std.StaticStringMap(Icon).initComptime(.{
    // Zig
    .{ "zig", Icon{ .codepoint = 0xe6a9, .color = 3 } }, //

    // Documentation
    .{ "md", Icon{ .codepoint = 0xe609, .color = 7 } }, //  (markdown)
    .{ "txt", Icon{ .codepoint = 0xf15c, .color = null } }, //
    .{ "pdf", Icon{ .codepoint = 0xf1c1, .color = 1 } }, //

    // Data formats
    .{ "json", Icon{ .codepoint = 0xe60b, .color = 3 } }, //
    .{ "toml", Icon{ .codepoint = 0xe60b, .color = 7 } }, //
    .{ "yaml", Icon{ .codepoint = 0xe60b, .color = 1 } }, //
    .{ "yml", Icon{ .codepoint = 0xe60b, .color = 1 } }, //
    .{ "xml", Icon{ .codepoint = 0xf121, .color = 3 } }, //
    .{ "csv", Icon{ .codepoint = 0xf1c3, .color = 2 } }, //

    // Programming languages
    .{ "py", Icon{ .codepoint = 0xe606, .color = 3 } }, //  (Python)
    .{ "js", Icon{ .codepoint = 0xe74e, .color = 3 } }, //  (JavaScript)
    .{ "ts", Icon{ .codepoint = 0xe628, .color = 4 } }, //  (TypeScript)
    .{ "jsx", Icon{ .codepoint = 0xe7ba, .color = 6 } }, //  (React)
    .{ "tsx", Icon{ .codepoint = 0xe7ba, .color = 4 } }, //  (React TypeScript)
    .{ "rs", Icon{ .codepoint = 0xe7a8, .color = 1 } }, //  (Rust)
    .{ "go", Icon{ .codepoint = 0xe627, .color = 6 } }, //  (Go)
    .{ "c", Icon{ .codepoint = 0xe61e, .color = 4 } }, //  (C)
    .{ "cpp", Icon{ .codepoint = 0xe61d, .color = 4 } }, //  (C++)
    .{ "cc", Icon{ .codepoint = 0xe61d, .color = 4 } }, //  (C++)
    .{ "h", Icon{ .codepoint = 0xe61e, .color = 5 } }, //  (C header)
    .{ "hpp", Icon{ .codepoint = 0xe61d, .color = 5 } }, //  (C++ header)
    .{ "java", Icon{ .codepoint = 0xe738, .color = 1 } }, //  (Java)
    .{ "rb", Icon{ .codepoint = 0xe739, .color = 1 } }, //  (Ruby)
    .{ "php", Icon{ .codepoint = 0xe73d, .color = 5 } }, //  (PHP)
    .{ "swift", Icon{ .codepoint = 0xe755, .color = 3 } }, //  (Swift)
    .{ "kt", Icon{ .codepoint = 0xe634, .color = 5 } }, //  (Kotlin)
    .{ "lua", Icon{ .codepoint = 0xe620, .color = 4 } }, //  (Lua)
    .{ "vim", Icon{ .codepoint = 0xe62b, .color = 2 } }, //  (Vim)
    .{ "ex", Icon{ .codepoint = 0xe62d, .color = 5 } }, //  (Elixir)
    .{ "exs", Icon{ .codepoint = 0xe62d, .color = 5 } }, //  (Elixir)
    .{ "erl", Icon{ .codepoint = 0xe7b1, .color = 1 } }, //  (Erlang)
    .{ "hs", Icon{ .codepoint = 0xe61f, .color = 5 } }, //  (Haskell)
    .{ "ml", Icon{ .codepoint = 0xe67a, .color = 3 } }, //  (OCaml)
    .{ "clj", Icon{ .codepoint = 0xe768, .color = 2 } }, //  (Clojure)
    .{ "scala", Icon{ .codepoint = 0xe737, .color = 1 } }, //  (Scala)

    // Web
    .{ "html", Icon{ .codepoint = 0xe736, .color = 3 } }, //
    .{ "htm", Icon{ .codepoint = 0xe736, .color = 3 } }, //
    .{ "css", Icon{ .codepoint = 0xe749, .color = 4 } }, //
    .{ "scss", Icon{ .codepoint = 0xe603, .color = 5 } }, //
    .{ "sass", Icon{ .codepoint = 0xe603, .color = 5 } }, //
    .{ "less", Icon{ .codepoint = 0xe60b, .color = 4 } }, //
    .{ "vue", Icon{ .codepoint = 0xe6a0, .color = 2 } }, //
    .{ "svelte", Icon{ .codepoint = 0xe697, .color = 1 } }, //

    // Shell
    .{ "sh", Icon{ .codepoint = 0xf489, .color = 2 } }, //
    .{ "bash", Icon{ .codepoint = 0xf489, .color = 2 } }, //
    .{ "zsh", Icon{ .codepoint = 0xf489, .color = 2 } }, //
    .{ "fish", Icon{ .codepoint = 0xf489, .color = 2 } }, //
    .{ "ps1", Icon{ .codepoint = 0xf489, .color = 4 } }, //  (PowerShell)

    // Config
    .{ "ini", Icon{ .codepoint = 0xe615, .color = 7 } }, //
    .{ "conf", Icon{ .codepoint = 0xe615, .color = 7 } }, //
    .{ "cfg", Icon{ .codepoint = 0xe615, .color = 7 } }, //

    // Images
    .{ "png", Icon{ .codepoint = 0xf1c5, .color = 5 } }, //
    .{ "jpg", Icon{ .codepoint = 0xf1c5, .color = 5 } }, //
    .{ "jpeg", Icon{ .codepoint = 0xf1c5, .color = 5 } }, //
    .{ "gif", Icon{ .codepoint = 0xf1c5, .color = 5 } }, //
    .{ "svg", Icon{ .codepoint = 0xf1c5, .color = 3 } }, //
    .{ "ico", Icon{ .codepoint = 0xf1c5, .color = 3 } }, //
    .{ "webp", Icon{ .codepoint = 0xf1c5, .color = 5 } }, //

    // Archives
    .{ "zip", Icon{ .codepoint = 0xf410, .color = 3 } }, //
    .{ "tar", Icon{ .codepoint = 0xf410, .color = 3 } }, //
    .{ "gz", Icon{ .codepoint = 0xf410, .color = 3 } }, //
    .{ "rar", Icon{ .codepoint = 0xf410, .color = 3 } }, //
    .{ "7z", Icon{ .codepoint = 0xf410, .color = 3 } }, //

    // Build/DevOps
    .{ "dockerfile", Icon{ .codepoint = 0xf308, .color = 4 } }, //
    .{ "tf", Icon{ .codepoint = 0xe69a, .color = 5 } }, //  (Terraform)

    // Database
    .{ "sql", Icon{ .codepoint = 0xf1c0, .color = 3 } }, //
    .{ "db", Icon{ .codepoint = 0xf1c0, .color = 3 } }, //
    .{ "sqlite", Icon{ .codepoint = 0xf1c0, .color = 4 } }, //

    // Lock files
    .{ "lock", Icon{ .codepoint = 0xf023, .color = 3 } }, //
});

// ===== Special Filename Mapping (T027, FR-032) =====
/// Map special filenames to icons (comptime)
pub const filename_icons = std.StaticStringMap(Icon).initComptime(.{
    // Build files
    .{ "Makefile", Icon{ .codepoint = 0xe673, .color = 7 } }, //
    .{ "makefile", Icon{ .codepoint = 0xe673, .color = 7 } }, //
    .{ "CMakeLists.txt", Icon{ .codepoint = 0xe673, .color = 4 } }, //
    .{ "build.zig", Icon{ .codepoint = 0xe6a9, .color = 3 } }, //
    .{ "build.zig.zon", Icon{ .codepoint = 0xe6a9, .color = 3 } }, //
    .{ "Cargo.toml", Icon{ .codepoint = 0xe7a8, .color = 1 } }, //
    .{ "Cargo.lock", Icon{ .codepoint = 0xe7a8, .color = 7 } }, //
    .{ "package.json", Icon{ .codepoint = 0xe74e, .color = 2 } }, //
    .{ "package-lock.json", Icon{ .codepoint = 0xe74e, .color = 7 } }, //
    .{ "pnpm-lock.yaml", Icon{ .codepoint = 0xe74e, .color = 3 } }, //
    .{ "yarn.lock", Icon{ .codepoint = 0xe74e, .color = 4 } }, //
    .{ "tsconfig.json", Icon{ .codepoint = 0xe628, .color = 4 } }, //
    .{ "Gemfile", Icon{ .codepoint = 0xe739, .color = 1 } }, //
    .{ "Gemfile.lock", Icon{ .codepoint = 0xe739, .color = 7 } }, //
    .{ "requirements.txt", Icon{ .codepoint = 0xe606, .color = 3 } }, //
    .{ "setup.py", Icon{ .codepoint = 0xe606, .color = 3 } }, //
    .{ "go.mod", Icon{ .codepoint = 0xe627, .color = 6 } }, //
    .{ "go.sum", Icon{ .codepoint = 0xe627, .color = 7 } }, //

    // Git
    .{ ".gitignore", Icon{ .codepoint = 0xf1d3, .color = 1 } }, //
    .{ ".gitattributes", Icon{ .codepoint = 0xf1d3, .color = 7 } }, //
    .{ ".gitmodules", Icon{ .codepoint = 0xf1d3, .color = 7 } }, //
    .{ ".gitconfig", Icon{ .codepoint = 0xf1d3, .color = 7 } }, //

    // Environment
    .{ ".env", Icon{ .codepoint = 0xf462, .color = 3 } }, //
    .{ ".env.local", Icon{ .codepoint = 0xf462, .color = 3 } }, //
    .{ ".env.example", Icon{ .codepoint = 0xf462, .color = 7 } }, //
    .{ ".envrc", Icon{ .codepoint = 0xf462, .color = 3 } }, //

    // Docker
    .{ "Dockerfile", Icon{ .codepoint = 0xf308, .color = 4 } }, //
    .{ "docker-compose.yml", Icon{ .codepoint = 0xf308, .color = 4 } }, //
    .{ "docker-compose.yaml", Icon{ .codepoint = 0xf308, .color = 4 } }, //
    .{ ".dockerignore", Icon{ .codepoint = 0xf308, .color = 7 } }, //

    // Documentation
    .{ "LICENSE", Icon{ .codepoint = 0xf0219, .color = 3 } }, //  (license icon)
    .{ "LICENSE.md", Icon{ .codepoint = 0xf0219, .color = 3 } }, //
    .{ "LICENSE.txt", Icon{ .codepoint = 0xf0219, .color = 3 } }, //
    .{ "README.md", Icon{ .codepoint = 0xe609, .color = 4 } }, //
    .{ "README", Icon{ .codepoint = 0xe609, .color = 4 } }, //
    .{ "CHANGELOG.md", Icon{ .codepoint = 0xe609, .color = 2 } }, //
    .{ "CONTRIBUTING.md", Icon{ .codepoint = 0xe609, .color = 5 } }, //

    // Editor config
    .{ ".editorconfig", Icon{ .codepoint = 0xe615, .color = 7 } }, //
    .{ ".prettierrc", Icon{ .codepoint = 0xe615, .color = 5 } }, //
    .{ ".eslintrc", Icon{ .codepoint = 0xe615, .color = 5 } }, //
    .{ ".eslintrc.js", Icon{ .codepoint = 0xe615, .color = 5 } }, //
    .{ ".eslintrc.json", Icon{ .codepoint = 0xe615, .color = 5 } }, //

    // Claude/AI
    .{ "CLAUDE.md", Icon{ .codepoint = 0xf02d, .color = 6 } }, //  (book icon for AI instructions)
});

/// Get icon for a file entry (T028)
/// FR-030: Extension-based icon
/// FR-031: Directory state-based icon
/// FR-032: Special filename icon
/// FR-034: Default fallback
pub fn getIcon(name: []const u8, is_dir: bool, is_expanded: bool) Icon {
    // FR-031: Directory icons based on expanded state
    if (is_dir) {
        return if (is_expanded) folder_open else folder_closed;
    }

    // FR-032: Check special filenames first (highest priority)
    if (filename_icons.get(name)) |icon| {
        return icon;
    }

    // FR-030: Check extension
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot_idx| {
        if (dot_idx + 1 < name.len) {
            const ext = name[dot_idx + 1 ..];
            // Convert to lowercase for matching
            var lower_ext_buf: [16]u8 = undefined;
            if (ext.len <= lower_ext_buf.len) {
                for (ext, 0..) |c, i| {
                    lower_ext_buf[i] = std.ascii.toLower(c);
                }
                const lower_ext = lower_ext_buf[0..ext.len];
                if (extension_icons.get(lower_ext)) |icon| {
                    return icon;
                }
            }
        }
    }

    // FR-034: Default fallback
    return file_default;
}

// ===== Tests (T021, T022, T023, T024) =====

test "US4-T021: getIcon with known extensions" {
    // Zig file
    const zig_icon = getIcon("main.zig", false, false);
    try std.testing.expectEqual(@as(u21, 0xe6a9), zig_icon.codepoint);
    try std.testing.expectEqual(@as(?u8, 3), zig_icon.color);

    // Markdown
    const md_icon = getIcon("README.md", false, false);
    // README.md is a special filename, not just extension
    try std.testing.expectEqual(@as(u21, 0xe609), md_icon.codepoint);

    // Python
    const py_icon = getIcon("script.py", false, false);
    try std.testing.expectEqual(@as(u21, 0xe606), py_icon.codepoint);

    // JavaScript
    const js_icon = getIcon("app.js", false, false);
    try std.testing.expectEqual(@as(u21, 0xe74e), js_icon.codepoint);
}

test "US4-T022: getIcon with special filenames" {
    // Makefile
    const makefile_icon = getIcon("Makefile", false, false);
    try std.testing.expectEqual(@as(u21, 0xe673), makefile_icon.codepoint);

    // .gitignore
    const gitignore_icon = getIcon(".gitignore", false, false);
    try std.testing.expectEqual(@as(u21, 0xf1d3), gitignore_icon.codepoint);

    // Dockerfile
    const dockerfile_icon = getIcon("Dockerfile", false, false);
    try std.testing.expectEqual(@as(u21, 0xf308), dockerfile_icon.codepoint);

    // build.zig
    const build_zig_icon = getIcon("build.zig", false, false);
    try std.testing.expectEqual(@as(u21, 0xe6a9), build_zig_icon.codepoint);
}

test "US4-T023: getIcon fallback to default" {
    // Unknown extension
    const unknown = getIcon("file.xyz123", false, false);
    try std.testing.expectEqual(file_default.codepoint, unknown.codepoint);

    // No extension
    const no_ext = getIcon("noextension", false, false);
    try std.testing.expectEqual(file_default.codepoint, no_ext.codepoint);
}

test "US4-T024: directory icons (open/closed)" {
    // Closed directory
    const closed = getIcon("src", true, false);
    try std.testing.expectEqual(folder_closed.codepoint, closed.codepoint);
    try std.testing.expectEqual(@as(?u8, 4), closed.color);

    // Open directory
    const open = getIcon("src", true, true);
    try std.testing.expectEqual(folder_open.codepoint, open.codepoint);
    try std.testing.expectEqual(@as(?u8, 4), open.color);
}

test "Icon.toUtf8 produces valid UTF-8" {
    const icon = Icon{ .codepoint = 0xe6a9, .color = 3 }; // Zig icon
    const utf8 = icon.toUtf8();

    // Verify it's valid UTF-8 (3-byte sequence for codepoint in BMP supplementary)
    const len = std.unicode.utf8CodepointSequenceLength(icon.codepoint) catch unreachable;
    try std.testing.expectEqual(@as(u3, 3), len);

    // Decode back and verify
    const decoded = std.unicode.utf8Decode(utf8[0..len]) catch unreachable;
    try std.testing.expectEqual(icon.codepoint, decoded);
}

test "extension_icons covers 20+ file types (SC-004)" {
    // Count unique extensions
    var count: usize = 0;
    const keys = extension_icons.keys();
    for (keys) |_| {
        count += 1;
    }
    try std.testing.expect(count >= 20);
}
