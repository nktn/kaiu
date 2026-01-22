# Common Build.zig Patterns

## Minimal Executable

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
```

## Library (Static and Dynamic)

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Static library (default)
    const lib = b.addLibrary(.{
        .name = "mylib",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Or dynamic library
    const lib_dynamic = b.addLibrary(.{
        .name = "mylib",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .linkage = .dynamic,
    });

    b.installArtifact(lib);
}
```

## Executable + Tests

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
```

## Multi-Module Project

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create reusable modules
    const utils = b.addModule("utils", .{
        .root_source_file = b.path("src/utils.zig"),
    });

    const networking = b.addModule("networking", .{
        .root_source_file = b.path("src/networking.zig"),
    });
    networking.addImport("utils", utils);

    // Executable using modules
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("utils", utils);
    exe.root_module.addImport("networking", networking);

    b.installArtifact(exe);
}
```

## With Dependencies (build.zig.zon)

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get dependency
    const dep = b.dependency("mylib", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Import module from dependency
    exe.root_module.addImport("mylib", dep.module("mylib"));

    // Or link library artifact
    exe.linkLibrary(dep.artifact("mylib"));

    b.installArtifact(exe);
}
```

Corresponding `build.zig.zon`:
```zig
.{
    .name = "my-app",
    .version = "0.1.0",
    .dependencies = .{
        .mylib = .{
            .url = "https://github.com/user/mylib/archive/v1.0.0.tar.gz",
            .hash = "1220abcdef...",
        },
    },
}
```

## Linking C Libraries

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link libc
    exe.linkLibC();

    // Link system libraries
    exe.linkSystemLibrary("sqlite3");
    exe.linkSystemLibrary("curl");

    // Add include paths
    exe.addIncludePath(b.path("include"));

    b.installArtifact(exe);
}
```

## Custom Build Options

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Custom options
    const enable_logging = b.option(bool, "logging", "Enable logging") orelse false;
    const max_connections = b.option(u32, "max-conn", "Max connections") orelse 100;
    const backend = b.option(enum { sqlite, postgres }, "backend", "DB backend") orelse .sqlite;

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Pass options to code
    const options = b.addOptions();
    options.addOption(bool, "enable_logging", enable_logging);
    options.addOption(u32, "max_connections", max_connections);
    options.addOption(@TypeOf(backend), "backend", backend);

    exe.root_module.addOptions("config", options);

    b.installArtifact(exe);
}
```

In code:
```zig
const config = @import("config");
if (config.enable_logging) {
    std.debug.print("Max connections: {}\n", .{config.max_connections});
}
```

## Code Generation

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build code generator
    const generator = b.addExecutable(.{
        .name = "codegen",
        .root_source_file = b.path("tools/codegen.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });

    // Run generator
    const run_codegen = b.addRunArtifact(generator);
    run_codegen.addArg("--output");
    const generated_file = run_codegen.addOutputFileArg("generated.zig");

    // Use generated code
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addAnonymousImport("generated", .{
        .root_source_file = generated_file,
    });

    b.installArtifact(exe);
}
```

## Cross-Compilation Targets

```zig
pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const targets = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
    };

    for (targets) |t| {
        const resolved_target = b.resolveTargetQuery(t);

        const exe = b.addExecutable(.{
            .name = "my-app",
            .root_source_file = b.path("src/main.zig"),
            .target = resolved_target,
            .optimize = optimize,
        });

        const target_output = b.addInstallArtifact(exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try t.zigTriple(b.allocator),
                },
            },
        });

        b.getInstallStep().dependOn(&target_output.step);
    }
}
```

## Install Additional Files

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    // Install header files
    const install_header = b.addInstallHeaderFile(
        b.path("include/api.h"),
        "myapp/api.h",
    );
    b.getInstallStep().dependOn(&install_header.step);

    // Install config files
    b.installFile(b.path("config/default.conf"), "share/myapp/default.conf");

    // Install directory
    b.installDirectory(.{
        .source_dir = b.path("assets"),
        .install_dir = .prefix,
        .install_subdir = "share/myapp/assets",
    });
}
```

## WriteFiles for Multiple Outputs

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wf = b.addWriteFiles();
    wf.add("version.txt", "1.0.0");
    wf.add("config.json", "{\"debug\": true}");

    const config_file = wf.add("generated.zig",
        \\pub const version = "1.0.0";
        \\pub const debug = true;
    );

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addAnonymousImport("build_config", .{
        .root_source_file = config_file,
    });

    b.installArtifact(exe);
}
```

## Conditional Compilation

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const options = b.addOptions();

    // Conditional based on target
    const is_windows = target.result.os.tag == .windows;
    options.addOption(bool, "is_windows", is_windows);

    // Conditional based on optimize mode
    const is_debug = optimize == .Debug;
    options.addOption(bool, "debug_build", is_debug);

    exe.root_module.addOptions("build_options", options);

    if (is_windows) {
        exe.linkSystemLibrary("ws2_32");
    } else {
        exe.linkSystemLibrary("pthread");
    }

    b.installArtifact(exe);
}
```

## Multiple Executables and Libraries

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Shared library
    const lib = b.addLibrary(.{
        .name = "core",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Main executable
    const exe = b.addExecutable(.{
        .name = "app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(lib);
    b.installArtifact(exe);

    // CLI tool
    const cli = b.addExecutable(.{
        .name = "app-cli",
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli.linkLibrary(lib);
    b.installArtifact(cli);

    // Tests for library
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
```