# Zig Build System Core Concepts

## Architecture

The Zig build system models projects as a **Directed Acyclic Graph (DAG)** of steps that execute independently and concurrently. This enables:

- Caching of intermediate results
- Parallel execution of unrelated tasks
- Composability across projects
- Reproducible builds

## The Install Step

By default, the main step is the **Install** step, which copies build artifacts to their final location. Most build configurations add dependencies to this step.

```zig
b.getInstallStep().dependOn(&some_step.step);
```

## Key Step Types

| Step Type | Purpose | Created With |
|-----------|---------|--------------|
| Compile (executable) | Build programs with main() | `b.addExecutable()` |
| Compile (library) | Create static/dynamic libraries | `b.addLibrary()` |
| Compile (test) | Build unit tests | `b.addTest()` |
| Run | Execute binaries as build steps | `b.addRunArtifact()` |
| System Command | Invoke external tools | `b.addSystemCommand()` |
| Options | Compile-time configuration | `b.addOptions()` |
| WriteFile | Generate files | `b.addWriteFiles()` |

## Module System

**Modules** are Zig's unit of code organization in the build system.

### Creating Modules

```zig
// Public module (available to dependents)
const my_module = b.addModule("my-module", .{
    .root_source_file = b.path("src/module.zig"),
});

// Private module (project-only)
const internal = b.createModule(.{
    .root_source_file = b.path("src/internal.zig"),
});
```

### Adding Modules to Artifacts

```zig
exe.root_module.addImport("config", options_module);
exe.root_module.addImport("utils", utils_module);
```

### Anonymous Imports for Generated Files

```zig
exe.root_module.addAnonymousImport("generated", .{
    .root_source_file = generated_file,
});
```

## Standard Build Options

### Target Selection

```zig
const target = b.standardTargetOptions(.{
    .default_target = .{}, // native
});
```

Users can override with: `-Dtarget=x86_64-windows-gnu`

### Optimization Mode

```zig
const optimize = b.standardOptimizeOption(.{
    .preferred_optimize_mode = .ReleaseFast,
});
```

Options: `Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall`

Users can override with: `-Doptimize=ReleaseFast`

### Custom Options

```zig
const enable_feature = b.option(bool, "feature", "Enable special feature") orelse false;
const version = b.option([]const u8, "version", "Version string") orelse "dev";
```

Users set with: `-Dfeature -Dversion=1.0.0`

## Options Step (Compile-Time Config)

Generate Zig source files with compile-time constants:

```zig
const options = b.addOptions();
options.addOption([]const u8, "version", "1.0.0");
options.addOption(bool, "debug_mode", true);

exe.root_module.addOptions("config", options);
```

In code:
```zig
const config = @import("config");
const version = config.version; // "1.0.0"
```

## File Generation Patterns

### 1. System Commands (external tools)

```zig
const gen_step = b.addSystemCommand(&.{ "python3", "generate.py" });
const output = gen_step.captureStdOut();
exe.root_module.addAnonymousImport("data", .{
    .root_source_file = output,
});
```

### 2. Project Tools (Zig programs)

```zig
const generator = b.addExecutable(.{
    .name = "generator",
    .root_source_file = b.path("tools/gen.zig"),
    .target = target,
    .optimize = optimize,
});

const run_gen = b.addRunArtifact(generator);
const output = run_gen.captureStdOut();
```

### 3. WriteFiles (multiple files)

```zig
const wf = b.addWriteFiles();
wf.add("config.json", "{}");
wf.add("data.txt", "content");

const dir = wf.getDirectory();
exe.root_module.addImport("files", dir);
```

## Testing

Unit tests compile separately from running:

```zig
// Create test executable
const unit_tests = b.addTest(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
});

// Create run step
const run_tests = b.addRunArtifact(unit_tests);

// Add to test top-level step
const test_step = b.step("test", "Run unit tests");
test_step.dependOn(&run_tests.step);
```

## Dependency Management

### Library Linking

```zig
// Link Zig library (from dependency)
exe.linkLibrary(zig_lib);

// Link system library
exe.linkSystemLibrary("z");

// Link C standard library
exe.linkLibC();
```

### Package Dependencies

In `build.zig.zon`:
```zig
.dependencies = .{
    .mylib = .{
        .url = "https://github.com/user/mylib/archive/ref.tar.gz",
        .hash = "...",
    },
},
```

In `build.zig`:
```zig
const mylib = b.dependency("mylib", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("mylib", mylib.module("mylib"));
```

## LazyPath

Represents paths that may not exist yet (generated files):

```zig
// Source path (relative to build.zig)
const src = b.path("src/main.zig");

// Generated path
const generated = some_step.addOutputFile("output.zig");

// CWD-relative (avoid when possible)
const abs = .{ .cwd_relative = "/absolute/path" };
```

## Build Artifacts and Installation

### Installing Artifacts

```zig
const install = b.addInstallArtifact(exe, .{});
b.getInstallStep().dependOn(&install.step);

// Shorthand
b.installArtifact(exe);
```

### Installing Files

```zig
// To prefix/
b.installFile(src_path, "dest/file.txt");

// To bin/
b.installBinFile(src_path, "my-tool");

// To lib/
b.installLibFile(src_path, "libmy.a");

// To include/
const install_header = b.addInstallHeaderFile(
    b.path("include/api.h"),
    "mylib/api.h",
);
```

## Best Practices

1. **Avoid hardcoded paths** - Use LazyPath and build system methods
2. **Use standard option names** - Enables IDE/tool compatibility
3. **Structure tests with run steps** - Separates compilation from execution
4. **Leverage caching** - Let the build system manage intermediate artifacts
5. **Keep generated files ephemeral** - Don't commit build outputs to source control
6. **Use the Options step** for compile-time config instead of environment variables

## Directory Structure

```
.zig-cache/     # Temporary build artifacts (gitignore)
zig-out/        # Default installation prefix (gitignore)
  ├── bin/      # Executables
  ├── lib/      # Libraries
  └── include/  # Headers
```