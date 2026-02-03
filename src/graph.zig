const std = @import("std");
const lsp = @import("lsp.zig");

/// Call hierarchy item for graph nodes.
pub const CallHierarchyItem = struct {
    name: []const u8,
    kind: lsp.SymbolKind,
    file_path: []const u8,
    line: u32,
    column: u32,
    snippet: []const u8,

    pub fn deinit(self: *CallHierarchyItem, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.file_path);
        allocator.free(self.snippet);
    }
};

/// Node in the call hierarchy graph.
pub const CallGraphNode = struct {
    allocator: std.mem.Allocator,
    item: CallHierarchyItem,
    incoming: std.ArrayList(usize),
    outgoing: std.ArrayList(usize),
    visited: bool,

    pub fn init(allocator: std.mem.Allocator, item: CallHierarchyItem) CallGraphNode {
        return .{
            .allocator = allocator,
            .item = item,
            .incoming = .empty,
            .outgoing = .empty,
            .visited = false,
        };
    }

    pub fn deinit(self: *CallGraphNode) void {
        self.item.deinit(self.allocator);
        self.incoming.deinit(self.allocator);
        self.outgoing.deinit(self.allocator);
    }

    pub fn addIncoming(self: *CallGraphNode, node_idx: usize) !void {
        try self.incoming.append(self.allocator, node_idx);
    }

    pub fn addOutgoing(self: *CallGraphNode, node_idx: usize) !void {
        try self.outgoing.append(self.allocator, node_idx);
    }
};

/// Graph representing call hierarchy relationships.
pub const CallHierarchyGraph = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(CallGraphNode),
    root: ?*CallGraphNode,
    cursor: usize,

    pub fn init(allocator: std.mem.Allocator) CallHierarchyGraph {
        return .{
            .allocator = allocator,
            .nodes = .empty,
            .root = null,
            .cursor = 0,
        };
    }

    pub fn deinit(self: *CallHierarchyGraph) void {
        for (self.nodes.items) |*node| {
            node.deinit();
        }
        self.nodes.deinit(self.allocator);
    }

    /// Build graph from call hierarchy items.
    pub fn buildFromCallHierarchy(
        self: *CallHierarchyGraph,
        root_item: CallHierarchyItem,
        incoming: []const lsp.CallHierarchyItem,
        outgoing: []const lsp.CallHierarchyItem,
    ) !void {
        // Clear existing graph
        for (self.nodes.items) |*node| {
            node.deinit();
        }
        self.nodes.clearRetainingCapacity();

        // Create root node
        const root_idx = try self.createNode(root_item);
        self.root = &self.nodes.items[root_idx];

        // Add incoming calls (callers)
        for (incoming) |item| {
            const caller_item = CallHierarchyItem{
                .name = try self.allocator.dupe(u8, item.name),
                .kind = item.kind,
                .file_path = try self.allocator.dupe(u8, item.file_path),
                .line = item.line,
                .column = item.column,
                .snippet = try self.allocator.dupe(u8, item.snippet),
            };
            const caller_idx = try self.createNode(caller_item);
            try self.nodes.items[caller_idx].addOutgoing(root_idx);
            try self.nodes.items[root_idx].addIncoming(caller_idx);
        }

        // Add outgoing calls (callees)
        for (outgoing) |item| {
            const callee_item = CallHierarchyItem{
                .name = try self.allocator.dupe(u8, item.name),
                .kind = item.kind,
                .file_path = try self.allocator.dupe(u8, item.file_path),
                .line = item.line,
                .column = item.column,
                .snippet = try self.allocator.dupe(u8, item.snippet),
            };
            const callee_idx = try self.createNode(callee_item);
            try self.nodes.items[root_idx].addOutgoing(callee_idx);
            try self.nodes.items[callee_idx].addIncoming(root_idx);
        }
    }

    /// Generate Graphviz DOT format string.
    pub fn toDot(self: *CallHierarchyGraph, arena: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        const writer = buf.writer(arena);

        try writer.writeAll("digraph callgraph {\n");
        try writer.writeAll("    rankdir=LR;\n");
        try writer.writeAll("    node [shape=box, fontname=\"monospace\"];\n");
        try writer.writeAll("    edge [arrowhead=vee];\n");
        try writer.writeAll("\n");

        // Reset visited flags
        for (self.nodes.items) |*node| {
            node.visited = false;
        }

        // Write nodes
        for (self.nodes.items, 0..) |*node, i| {
            const label = try std.fmt.allocPrint(arena, "{s}\\n{s}:{d}", .{
                node.item.name,
                std.fs.path.basename(node.item.file_path),
                node.item.line,
            });
            try writer.print("    n{d} [label=\"{s}\"];\n", .{ i, label });
        }

        try writer.writeAll("\n");

        // Write edges (outgoing calls)
        for (self.nodes.items, 0..) |*node, i| {
            for (node.outgoing.items) |target_idx| {
                try writer.print("    n{d} -> n{d};\n", .{ i, target_idx });
            }
        }

        try writer.writeAll("}\n");

        return buf.toOwnedSlice(arena);
    }

    /// Generate text-based tree representation (fallback).
    pub fn toTextTree(self: *CallHierarchyGraph, arena: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        const writer = buf.writer(arena);

        const root = self.root orelse return buf.toOwnedSlice(arena);

        // Reset visited flags
        for (self.nodes.items) |*node| {
            node.visited = false;
        }

        // Write incoming calls (callers)
        if (root.incoming.items.len > 0) {
            try writer.writeAll("Callers:\n");
            for (root.incoming.items) |caller_idx| {
                const caller = &self.nodes.items[caller_idx];
                try writer.print("  ← {s} ({s}:{d})\n", .{
                    caller.item.name,
                    std.fs.path.basename(caller.item.file_path),
                    caller.item.line,
                });
            }
            try writer.writeAll("\n");
        }

        // Write root
        try writer.print("◉ {s} ({s}:{d})\n", .{
            root.item.name,
            std.fs.path.basename(root.item.file_path),
            root.item.line,
        });

        // Write outgoing calls (callees)
        if (root.outgoing.items.len > 0) {
            try writer.writeAll("\nCallees:\n");
            for (root.outgoing.items) |callee_idx| {
                const callee = &self.nodes.items[callee_idx];
                try writer.print("  → {s} ({s}:{d})\n", .{
                    callee.item.name,
                    std.fs.path.basename(callee.item.file_path),
                    callee.item.line,
                });
            }
        }

        return buf.toOwnedSlice(arena);
    }

    /// Get number of nodes in the graph.
    pub fn nodeCount(self: *const CallHierarchyGraph) usize {
        return self.nodes.items.len;
    }

    /// Move cursor to next node.
    pub fn moveDown(self: *CallHierarchyGraph) void {
        if (self.cursor + 1 < self.nodes.items.len) {
            self.cursor += 1;
        }
    }

    /// Move cursor to previous node.
    pub fn moveUp(self: *CallHierarchyGraph) void {
        if (self.cursor > 0) {
            self.cursor -= 1;
        }
    }

    /// Get currently selected node.
    pub fn getCurrent(self: *CallHierarchyGraph) ?*CallGraphNode {
        if (self.cursor < self.nodes.items.len) {
            return &self.nodes.items[self.cursor];
        }
        return null;
    }

    fn createNode(self: *CallHierarchyGraph, item: CallHierarchyItem) !usize {
        const node = CallGraphNode.init(self.allocator, item);
        try self.nodes.append(self.allocator, node);
        return self.nodes.items.len - 1;
    }
};

test "CallHierarchyGraph init and deinit" {
    const allocator = std.testing.allocator;
    var graph = CallHierarchyGraph.init(allocator);
    defer graph.deinit();

    try std.testing.expectEqual(@as(usize, 0), graph.nodeCount());
    try std.testing.expect(graph.root == null);
}

test "CallHierarchyGraph toTextTree empty" {
    const allocator = std.testing.allocator;
    var graph = CallHierarchyGraph.init(allocator);
    defer graph.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const text = try graph.toTextTree(arena.allocator());
    try std.testing.expectEqualStrings("", text);
}

test "CallHierarchyGraph toDot empty" {
    const allocator = std.testing.allocator;
    var graph = CallHierarchyGraph.init(allocator);
    defer graph.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const dot = try graph.toDot(arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, dot, "digraph callgraph") != null);
}
