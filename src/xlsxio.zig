const std = @import("std");
const builtin = @import("builtin");

// Export build module for easier integration
pub const build_module = @import("build_module.zig");

// Runtime check for Windows 64-bit
comptime {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) {
        @compileError("This library only supports Windows 64-bit platforms");
    }
}

// Import build options if available
const options = if (@hasDecl(@import("root"), "xlsxio_options"))
    @import("root").xlsxio_options
else
    struct {};

// Auto-link C libraries when imported as a module
pub fn getIncludePath() []const u8 {
    if (@hasDecl(options, "include_path")) {
        return options.include_path;
    }
    return "vendor/xlsxio/include";
}

pub fn getLibPath() []const u8 {
    if (@hasDecl(options, "lib_path")) {
        return options.lib_path;
    }
    return "vendor/xlsxio/lib";
}

pub fn getSystemLibs() []const []const u8 {
    if (@hasDecl(options, "system_libs")) {
        return options.system_libs;
    }
    return &[_][]const u8{ "xlsxio_read", "xlsxio_write" };
}

pub fn shouldLinkLibC() bool {
    if (@hasDecl(options, "link_libc")) {
        return options.link_libc;
    }
    return true;
}

// Function to handle DLL installation
pub fn installDlls(b: *std.Build, artifact: *std.Build.Step.Compile) void {
    const dlls = [_][]const u8{
        "xlsxio_read.dll",
        "xlsxio_write.dll",
        "libexpat.dll",
        "minizip.dll",
        "zlib1.dll",
        "bz2.dll",
    };

    // Create a custom step for DLL installation
    const install_dlls_step = b.step("install-dlls", "Install DLLs");

    // Find path to binaries
    const pkg_path = comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir;
    };

    // Install each DLL
    inline for (dlls) |dll| {
        const install_file_step = b.addInstallBinFile(b.path(b.pathJoin(&.{ pkg_path, "..", "vendor", "xlsxio", "bin", dll })), dll);
        install_dlls_step.dependOn(&install_file_step.step);
    }

    // Make main installation depend on DLL installation
    b.getInstallStep().dependOn(install_dlls_step);

    // Add bin directory to PATH for run commands
    if (artifact.kind == .exe) {
        const run_cmd = b.addRunArtifact(artifact);
        run_cmd.addPathDir("bin");
    }
}

const c = @cImport({
    @cInclude("xlsxio_read.h");
    @cInclude("xlsxio_write.h");
});

// Custom timestamp type that matches the C library's time_t
pub const Timestamp = struct {
    secs: i64,
};

pub const XlsxioError = error{
    FileNotFound,
    InvalidFile,
    ReadError,
    WriteError,
    SheetNotFound,
    CellNotFound,
    OutOfMemory,
};

pub const Reader = struct {
    handle: ?*?*c.struct_xlsxio_read_struct,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, filename: [:0]const u8) !Reader {
        const handle = c.xlsxioread_open(filename.ptr) orelse return XlsxioError.FileNotFound;
        return Reader{
            .handle = @as(?*?*c.struct_xlsxio_read_struct, @ptrCast(@alignCast(handle))),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Reader) void {
        c.xlsxioread_close(@as(c.xlsxioreader, @ptrCast(@alignCast(self.handle))));
    }

    pub const Sheet = struct {
        handle: ?*?*c.struct_xlsxio_read_sheet_struct,
        allocator: std.mem.Allocator,

        pub fn init(reader: *Reader, sheet_name: ?[:0]const u8) !Sheet {
            const name_ptr = if (sheet_name) |name| name.ptr else null;
            const handle = c.xlsxioread_sheet_open(@as(c.xlsxioreader, @ptrCast(@alignCast(reader.handle))), name_ptr, c.XLSXIOREAD_SKIP_EMPTY_ROWS) orelse return XlsxioError.SheetNotFound;
            return Sheet{
                .handle = @as(?*?*c.struct_xlsxio_read_sheet_struct, @ptrCast(@alignCast(handle))),
                .allocator = reader.allocator,
            };
        }

        pub fn deinit(self: *Sheet) void {
            c.xlsxioread_sheet_close(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle))));
        }

        pub fn nextRow(self: *Sheet) bool {
            return c.xlsxioread_sheet_next_row(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle)))) != 0;
        }

        pub fn nextCell(self: *Sheet) !?[]const u8 {
            const value = c.xlsxioread_sheet_next_cell(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle)))) orelse return null;
            defer c.xlsxioread_free(value);

            const len = std.mem.len(value);
            const result = try self.allocator.alloc(u8, len);
            @memcpy(result, value[0..len]);
            return result;
        }

        pub fn nextCellInt(self: *Sheet) !?i64 {
            var value: i64 = 0;
            const success = c.xlsxioread_sheet_next_cell_int(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle))), &value);

            if (success == 0) {
                return null;
            } else if (success < 0) {
                return error.Unexpected;
            }

            return value;
        }

        pub fn nextCellFloat(self: *Sheet) !?f64 {
            var value: f64 = 0;
            const success = c.xlsxioread_sheet_next_cell_float(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle))), &value);

            if (success == 0) {
                return null;
            } else if (success < 0) {
                return error.Unexpected;
            }

            return value;
        }

        pub fn nextCellString(self: *Sheet) !?[:0]const u8 {
            var value: ?[*]u8 = null;
            const success = c.xlsxioread_sheet_next_cell_string(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle))), &value);

            if (success == 0) {
                return null;
            } else if (success < 0) {
                return error.Unexpected;
            }

            if (value == null) {
                return null;
            }

            defer c.xlsxioread_free(value.?);

            // Manually count string length
            var len: usize = 0;
            while (value.?[len] != 0) : (len += 1) {}

            // Allocate with sentinel
            const result = try self.allocator.allocSentinel(u8, len, 0);
            @memcpy(result, value.?[0..len]);
            return result;
        }

        pub fn nextCellDatetime(self: *Sheet) !?Timestamp {
            var value: i64 = 0;
            const success = c.xlsxioread_sheet_next_cell_datetime(@as(c.xlsxioreadersheet, @ptrCast(@alignCast(self.handle))), &value);

            if (success == 0) {
                return null;
            } else if (success < 0) {
                return error.Unexpected;
            }

            return Timestamp{ .secs = value };
        }
    };
};

pub const Writer = struct {
    handle: ?*?*c.struct_xlsxio_write_struct,

    pub fn init(filename: [:0]const u8, sheet_name: [:0]const u8) !Writer {
        const handle = c.xlsxiowrite_open(filename.ptr, sheet_name.ptr) orelse return XlsxioError.WriteError;
        return Writer{
            .handle = @as(?*?*c.struct_xlsxio_write_struct, @ptrCast(@alignCast(handle))),
        };
    }

    pub fn deinit(self: *Writer) void {
        _ = c.xlsxiowrite_close(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))));
    }

    pub fn addSheet(self: *Writer, name: [:0]const u8) void {
        c.xlsxiowrite_add_sheet(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))), name.ptr);
    }

    pub fn addCellString(self: *Writer, value: [:0]const u8) void {
        c.xlsxiowrite_add_cell_string(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))), value.ptr);
    }

    pub fn addCellInt(self: *Writer, value: i64) void {
        c.xlsxiowrite_add_cell_int(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))), value);
    }

    pub fn addCellFloat(self: *Writer, value: f64) void {
        c.xlsxiowrite_add_cell_float(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))), value);
    }

    pub fn addCellDatetime(self: *Writer, value: Timestamp) void {
        c.xlsxiowrite_add_cell_datetime(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))), value.secs);
    }

    pub fn nextRow(self: *Writer) void {
        c.xlsxiowrite_next_row(@as(c.xlsxiowriter, @ptrCast(@alignCast(self.handle))));
    }
};

test "basic xlsx read/write" {
    std.log.info("Starting test\n", .{});

    const allocator = std.testing.allocator;
    const test_file = "test.xlsx";
    const test_sheet = "Sheet1";

    std.log.info("Creating test file\n", .{});

    // Write test
    {
        var writer = try Writer.init(test_file, test_sheet);
        defer writer.deinit();

        writer.addCellString("Hello");
        writer.addCellInt(42);
        writer.addCellFloat(3.14);
        writer.addCellDatetime(Timestamp{ .secs = 1737094027 });
        writer.nextRow();
    }

    std.log.info("Test file created\n", .{});

    // Check if file exists
    {
        std.fs.cwd().access(test_file, .{}) catch |err| {
            std.log.err("Error accessing file: {}\n", .{err});
            return err;
        };
    }

    std.log.info("Reading test file\n", .{});

    // Read test
    {
        var reader = try Reader.init(allocator, test_file);
        defer reader.deinit();

        var sheet = try Reader.Sheet.init(&reader, test_sheet);
        defer sheet.deinit();

        try std.testing.expect(sheet.nextRow());

        const cell1 = try sheet.nextCellString();
        try std.testing.expectEqualStrings("Hello", cell1.?);
        allocator.free(cell1.?);

        const cell2 = try sheet.nextCellInt();
        try std.testing.expectEqual(42, cell2.?);

        const cell3 = try sheet.nextCellFloat();
        try std.testing.expectEqual(3.14, cell3.?);

        const cell4 = try sheet.nextCellDatetime();
        try std.testing.expectEqual(@as(i64, 1737094027), cell4.?.secs);
    }

    std.log.info("Test file read\n", .{});

    // Clean up test file
    std.fs.cwd().deleteFile(test_file) catch {};
}
