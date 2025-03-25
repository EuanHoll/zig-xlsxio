const std = @import("std");

const dlls = [_][]const u8{
    "vendor/xlsxio/bin/xlsxio_read.dll",
    "vendor/xlsxio/bin/xlsxio_write.dll",
    "vendor/xlsxio/bin/libexpat.dll",
    "vendor/xlsxio/bin/minizip.dll",
    "vendor/xlsxio/bin/zlib1.dll",
    "vendor/xlsxio/bin/bz2.dll",
};

/// Helper function for consumers to install necessary DLLs
pub fn installDlls(b: *std.Build, artifact: *std.Build.Step.Compile) void {
    // Install DLLs to the binary directory
    for (dlls) |dll_path| {
        const dll_basename = std.fs.path.basename(dll_path);
        b.installFile(dll_path, dll_basename);
    }

    // For executables, create a run command that adds the DLL directory to the PATH
    if (artifact.kind == .exe) {
        // Create a run command for the artifact that includes the DLL directory in PATH
        const run_cmd = b.addRunArtifact(artifact);
        run_cmd.addPathDir("bin"); // Add the bin directory to PATH
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Define the xlsxio module
    const xlsxio_mod = b.addModule("xlsxio", .{
        .root_source_file = b.path("src/xlsxio.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add the build helper module
    _ = b.addModule("xlsxio_build", .{
        .root_source_file = b.path("src/build_module.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create a shared library that consumers can link against
    const lib = b.addStaticLibrary(.{
        .name = "zig_xlsxio",
        .root_source_file = b.path("src/xlsxio.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Setup library paths and includes
    const xlsxio_include = b.path("vendor/xlsxio/include");
    const xlsxio_lib = b.path("vendor/xlsxio/lib");
    lib.addIncludePath(xlsxio_include);
    lib.addLibraryPath(xlsxio_lib);
    lib.linkSystemLibrary("xlsxio_read");
    lib.linkSystemLibrary("xlsxio_write");
    lib.linkLibC();

    // Install DLLs to the bin directory
    for (dlls) |dll_path| {
        const dll_basename = std.fs.path.basename(dll_path);
        b.installFile(dll_path, dll_basename);
    }

    // Install the library
    b.installArtifact(lib);

    // Setup dependencies for linking (removed linkage assignment as it's not available in 0.14.0)
    const options = b.addOptions();
    options.addOption([]const u8, "include_path", "vendor/xlsxio/include");
    options.addOption([]const u8, "lib_path", "vendor/xlsxio/lib");
    options.addOption([]const []const u8, "system_libs", &[_][]const u8{ "xlsxio_read", "xlsxio_write" });
    options.addOption(bool, "link_libc", true);

    // Create a test artifact
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

    // Create a demo executable to show usage
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

    // Add an option to explicitly install just the DLLs
    const install_dlls_step = b.step("install-dlls", "Install DLLs only");
    for (dlls) |dll_path| {
        const dll_basename = std.fs.path.basename(dll_path);
        const install_file_step = b.addInstallFile(b.path(dll_path), dll_basename);
        install_dlls_step.dependOn(&install_file_step.step);
    }
}
