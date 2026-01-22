# Build API Quick Reference

## Build Instance (`*std.Build`)

### Standard Options

```zig
// Target selection (arch, OS, ABI)
const target = b.standardTargetOptions(.{
    .default_target = .{}, // native
    .whitelist = &[_]std.Target.Query{...}, // restrict allowed targets
});

// Optimization mode
const optimize = b.standardOptimizeOption(.{
    .preferred_optimize_mode = .ReleaseFast,
});

// Custom option
const value = b.option(T, "name", "Description") orelse default_value;
// Types: bool, int, float, enum, string, []const u8, LazyPath, []const LazyPath
```

### Creating Compilation Artifacts

```zig
// Executable
const exe = b.addExecutable(.{
    .name = "app-name",
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .version = .{ .major = 1, .minor = 0, .patch = 0 },
    .linkage = null, // or .static / .dynamic
});

// Library
const lib = b.addLibrary(.{
    .name = "lib-name",
    .root_source_file = b.path("src/lib.zig"),
    .target = target,
    .optimize = optimize,
    .version = .{ .major = 1, .minor = 0, .patch = 0 },
    .linkage = .static, // or .dynamic
});

// Unit Tests
const tests = b.addTest(.{
    .name = "tests", // optional
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .filters = &[_][]const u8{"TestName"}, // optional filter
});
```

### Modules

```zig
// Create public module (exported to dependents)
const mod = b.addModule("module-name", .{
    .root_source_file = b.path("src/module.zig"),
    .imports = &.{}, // optional
});

// Create private module
const internal_mod = b.createModule(.{
    .root_source_file = b.path("src/internal.zig"),
});
```

### Build Steps

```zig
// Custom top-level step
const my_step = b.step("stepname", "Description shown in help");
my_step.dependOn(&some_other_step);

// Get install step
const install = b.getInstallStep();

// Run artifact
const run_cmd = b.addRunArtifact(exe);
run_cmd.step.dependOn(b.getInstallStep());

// System command
const cmd = b.addSystemCommand(&.{"python3", "script.py"});
const output = cmd.captureStdOut(); // Returns LazyPath
```

### File Operations

```zig
// Path relative to build.zig
const src_path = b.path("src/file.zig");

// Write multiple files
const wf = b.addWriteFiles();
const file = wf.add("filename.txt", "content");
wf.addCopyFile(source, "dest.txt");
const dir = wf.getDirectory();

// Options (compile-time config)
const options = b.addOptions();
options.addOption(T, "name", value);
exe.root_module.addOptions("config", options);
```

### Installation

```zig
// Install artifact (to bin/ for exe, lib/ for library)
b.installArtifact(exe);

// Install with custom options
const install_artifact = b.addInstallArtifact(exe, .{
    .dest_dir = .{ .override = .{ .custom = "subdir" } },
});
b.getInstallStep().dependOn(&install_artifact.step);

// Install files
b.installFile(source, "relative/path.txt");        // to prefix/
b.installBinFile(source, "tool");                  // to bin/
b.installLibFile(source, "libfoo.a");              // to lib/
const hdr = b.addInstallHeaderFile(source, "api.h"); // to include/

// Install directory
b.installDirectory(.{
    .source_dir = b.path("assets"),
    .install_dir = .prefix,
    .install_subdir = "share/myapp",
});
```

### Dependencies

```zig
// Get dependency from build.zig.zon
const dep = b.dependency("dep-name", .{
    .target = target,
    .optimize = optimize,
    // Pass any custom options the dependency accepts
});

// Import module from dependency
exe.root_module.addImport("dep", dep.module("module-name"));

// Link artifact from dependency
exe.linkLibrary(dep.artifact("lib-name"));

// Access dependency paths
const dep_path = dep.path("file.txt");
```

### Utilities

```zig
// Duplicate string
const str = b.dupe("string");

// Format string
const formatted = b.fmt("Hello {s}", .{"world"});

// Path operations
const joined = b.pathJoin(&.{"a", "b", "c"});
const resolved = b.pathResolve(&.{"/base", "relative"});
```

## Compile Artifact (`*std.Build.Step.Compile`)

### Module Configuration

```zig
// Add module import
exe.root_module.addImport("name", module);

// Add anonymous import (for generated files)
exe.root_module.addAnonymousImport("name", .{
    .root_source_file = lazy_path,
});

// Add options
exe.root_module.addOptions("config", options_step);

// Set module properties
exe.root_module.target = target;
exe.root_module.optimize = optimize;
```

### Linking

```zig
// Link Zig library
exe.linkLibrary(lib_artifact);

// Link system library
exe.linkSystemLibrary("sqlite3");
exe.linkSystemLibrary2("openssl", .{
    .use_pkg_config = .force, // or .no or .yes
    .preferred_link_mode = .static, // or .dynamic
});

// Link libc
exe.linkLibC();

// Link libc++
exe.linkLibCpp();
```

### Include Paths and Framework

```zig
// Add include directory
exe.addIncludePath(b.path("include"));

// Add system include
exe.addSystemIncludePath(b.path("system/include"));

// macOS frameworks
exe.linkFramework("Cocoa");
```

### Compile Options

```zig
// Add C source files
exe.addCSourceFile(.{
    .file = b.path("src/code.c"),
    .flags = &.{"-Wall", "-O2"},
});

exe.addCSourceFiles(.{
    .files = &.{"a.c", "b.c"},
    .flags = &.{"-std=c11"},
});

// Preprocessor defines
exe.defineCMacro("DEBUG", "1");
exe.defineCMacro("VERSION", "\"1.0\"");

// Emit artifacts
exe.emit_bin = true; // default
exe.emit_llvm_ir = .{ .emit_to = b.path("output.ll") };
exe.emit_asm = .{ .emit_to = b.path("output.s") };
```

## Run Step (`*std.Build.Step.Run`)

```zig
const run = b.addRunArtifact(exe);

// Add arguments
run.addArg("--flag");
run.addArgs(&.{"arg1", "arg2"});

// Add artifact as argument (path to executable)
run.addArtifactArg(some_exe);

// Add file argument
run.addFileArg(lazy_path);

// Capture output
const stdout = run.captureStdOut();
const stderr = run.captureStdErr();

// Set working directory
run.setCwd(b.path("subdir"));

// Forward args from `zig build -- args...`
if (b.args) |args| {
    run.addArgs(args);
}

// Environment variables
run.setEnvironmentVariable("KEY", "value");
```

## LazyPath

```zig
// Source path (relative to build.zig)
const src = b.path("src/file.zig");

// Generated file
const generated = step.addOutputFileArg("output.zig");

// Directory
const dir = write_files_step.getDirectory();

// CWD-relative (avoid when possible)
const abs = .{ .cwd_relative = "/absolute/path" };

// From dependency
const dep_file = dependency.path("file.txt");

// Get string path (only works after build)
const path_str = lazy_path.getPath(b);
```

## Options Step (`*std.Build.Step.Options`)

```zig
const options = b.addOptions();

// Add typed options
options.addOption(bool, "debug", true);
options.addOption([]const u8, "version", "1.0.0");
options.addOption(u32, "max_size", 1024);
options.addOption(enum { a, b }, "mode", .a);

// Use in artifact
exe.root_module.addOptions("config", options);
```

In code:
```zig
const config = @import("config");
if (config.debug) { ... }
```

## WriteFile Step (`*std.Build.Step.WriteFile`)

```zig
const wf = b.addWriteFiles();

// Add file with content
const file = wf.add("filename.txt", "content");

// Copy file
wf.addCopyFile(source_path, "dest.txt");

// Get output directory
const dir = wf.getDirectory();

// Named WriteFiles (for multi-package builds)
const named_wf = b.addNamedWriteFiles("name");
```

## Module (`*std.Build.Module`)

```zig
// Add import to module
module.addImport("name", other_module);

// Add anonymous import
module.addAnonymousImport("name", .{
    .root_source_file = lazy_path,
});

// Add options
module.addOptions("config", options_step);

// Link library
module.linkLibrary(lib);
module.linkSystemLibrary("z");

// Add include paths
module.addIncludePath(path);
```

## Target and Optimization

```zig
// Resolve target query
const target = b.resolveTargetQuery(.{
    .cpu_arch = .x86_64,
    .os_tag = .linux,
    .abi = .gnu,
});

// Common optimization modes
.Debug        // No optimizations, safety checks
.ReleaseSafe  // Optimized, safety checks
.ReleaseFast  // Optimized, no safety checks
.ReleaseSmall // Size-optimized, no safety checks
```

## Common Patterns

### Conditional Code
```zig
if (target.result.os.tag == .windows) {
    exe.linkSystemLibrary("ws2_32");
}

if (optimize == .Debug) {
    exe.defineCMacro("DEBUG", "1");
}
```

### Chaining Dependencies
```zig
step_a.dependOn(&step_b.step);
step_b.dependOn(&step_c.step);
// step_a depends on step_b depends on step_c
```

### Multiple Targets
```zig
for ([_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
}) |query| {
    const t = b.resolveTargetQuery(query);
    const exe = b.addExecutable(.{ .target = t, ... });
    b.installArtifact(exe);
}
```