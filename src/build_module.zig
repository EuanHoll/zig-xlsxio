// In vendor/xlsxio/src/build_module.zig
const std = @import("std");

pub fn linkXlsxioModule(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    dep: *std.Build.Dependency,
) void {
    // Add the module
    exe.root_module.addImport("xlsxio", dep.module("xlsxio"));

    // Auto-link against the C libraries
    exe.linkLibC();

    // Add C include paths and libraries
    const pkg_path = dep.builder.pathFromRoot(".");
    const include_path = b.pathJoin(&.{ pkg_path, "vendor", "xlsxio", "include" });
    const lib_path = b.pathJoin(&.{ pkg_path, "vendor", "xlsxio", "lib" });

    exe.addIncludePath(b.path(include_path));
    exe.addLibraryPath(b.path(lib_path));
    exe.linkSystemLibrary("xlsxio_read");
    exe.linkSystemLibrary("xlsxio_write");

    // Install DLLs if this is an executable
    if (exe.kind == .exe) {
        // Custom DLL installation step
        const bin_dir = b.pathJoin(&.{ pkg_path, "vendor", "xlsxio", "bin" });
        const dlls = [_][]const u8{
            "xlsxio_read.dll",
            "xlsxio_write.dll",
            "libexpat.dll",
            "minizip.dll",
            "zlib1.dll",
            "bz2.dll",
        };

        for (dlls) |dll| {
            const src_path = b.pathJoin(&.{ bin_dir, dll });
            b.installBinFile(b.path(src_path), dll);
        }

        // Create a run command that adds the bin directory to PATH
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.addPathDir("bin");
    }
}
