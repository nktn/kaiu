const std = @import("std");
const app = @import("app.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const start_path = if (args.len > 1) args[1] else ".";

    try app.run(allocator, start_path);
}

test "main imports" {
    _ = @import("app.zig");
    _ = @import("tree.zig");
    _ = @import("ui.zig");
}
