const std = @import("std");

const dlls = [_][]const u8{
    "vendor/xlsxio/bin/xlsxio_read.dll",
    "vendor/xlsxio/bin/xlsxio_write.dll",
    "vendor/xlsxio/bin/libexpat.dll",
    "vendor/xlsxio/bin/minizip.dll",
    "vendor/xlsxio/bin/zlib1.dll",
    "vendor/xlsxio/bin/bz2.dll",
};

/// Helper function for consumers to install necessary DLLs.
pub fn installDlls(b: *std.Build, artifact: *std.Build.Step.Compile) void {
    for (dlls) |dll_path| {
        const dll_basename = std.fs.path.basename(dll_path);
        b.installFile(dll_path, dll_basename);
    }
    if (artifact.kind == .exe) {
        const run_cmd = b.addRunArtifact(artifact);
        run_cmd.addPathDir("bin");
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Expose an option "install_dlls" (default true)
    const install_dlls_opt = b.option(bool, "install_dlls", "Install DLLs") orelse true;

    // Define the xlsxio module.
    const xlsxio_mod = b.addModule("xlsxio", .{
        .root_source_file = b.path("src/xlsxio.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Add the include path so that @cImport finds xlsxio_read.h
    xlsxio_mod.addIncludePath(b.path("vendor/xlsxio/include"));

    // Add the build helper module.
    _ = b.addModule("xlsxio_build", .{
        .root_source_file = b.path("src/build_module.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create a shared library that consumers can link against.
    const lib = b.addStaticLibrary(.{
        .name = "zig_xlsxio",
        .root_source_file = b.path("src/xlsxio.zig"),
        .target = target,
        .optimize = optimize,
    });
    const xlsxio_include = b.path("vendor/xlsxio/include");
    const xlsxio_lib = b.path("vendor/xlsxio/lib");
    lib.addIncludePath(xlsxio_include);
    lib.addLibraryPath(xlsxio_lib);
    lib.addObjectFile(b.path("vendor/xlsxio/lib/xlsxio_read.lib"));
    lib.addObjectFile(b.path("vendor/xlsxio/lib/xlsxio_write.lib"));
    lib.linkLibC();

    // Conditionally install DLLs if the option is true.
    if (install_dlls_opt) {
        for (dlls) |dll_path| {
            const dll_basename = std.fs.path.basename(dll_path);
            b.installFile(dll_path, dll_basename);
        }
    }

    b.installArtifact(lib);

    const options = b.addOptions();
    options.addOption([]const u8, "include_path", "vendor/xlsxio/include");
    options.addOption([]const u8, "lib_path", "vendor/xlsxio/lib");
    options.addOption([]const []const u8, "system_libs", &[_][]const u8{ "xlsxio_read", "xlsxio_write" });
    options.addOption(bool, "link_libc", true);

    // Create a test artifact.
    const tests = b.addTest(.{
        .root_source_file = b.path("src/xlsxio.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.addIncludePath(xlsxio_include);
    tests.addLibraryPath(xlsxio_lib);
    tests.linkSystemLibrary("xlsxio_read");
    tests.linkSystemLibrary("xlsxio_write");
    tests.linkLibC();

    const run_tests = b.addRunArtifact(tests);
    run_tests.addPathDir("vendor/xlsxio/bin");

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    // Create a demo executable to show usage.
    const exe = b.addExecutable(.{
        .name = "xlsxio_demo",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(xlsxio_include);
    exe.addLibraryPath(xlsxio_lib);
    exe.linkSystemLibrary("xlsxio_read");
    exe.linkSystemLibrary("xlsxio_write");
    exe.linkLibC();
    exe.root_module.addImport("xlsxio", xlsxio_mod);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addPathDir("vendor/xlsxio/bin");
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the demo application");
    run_step.dependOn(&run_cmd.step);

    // Optionally add a step to install DLLs only.
    if (install_dlls_opt) {
        const install_dlls_step = b.step("install-dlls", "Install DLLs only");
        for (dlls) |dll_path| {
            const dll_basename = std.fs.path.basename(dll_path);
            const install_file_step = b.addInstallFile(b.path(dll_path), dll_basename);
            install_dlls_step.dependOn(&install_file_step.step);
        }
    }
}
