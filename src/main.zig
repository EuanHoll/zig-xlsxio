const std = @import("std");
const xlsxio = @import("xlsxio.zig");

pub fn main() !void {
    const filename = "output.xlsx";
    std.log.info("Creating Excel file: {s}", .{filename});

    // Initialize the writer with a sheet name
    var writer = xlsxio.Writer.init(filename, "Sheet1") catch |err| {
        std.log.err("Error creating writer: {}\n", .{err});
        return err;
    };

    defer writer.deinit();

    // Add header row
    writer.addCellString("ID");
    writer.addCellString("Name");
    writer.addCellString("Value");
    writer.addCellString("Date");
    writer.nextRow();

    // Add data rows
    writer.addCellInt(1);
    writer.addCellString("Item A");
    writer.addCellFloat(10.5);
    writer.addCellDatetime(xlsxio.Timestamp{ .secs = 1737094027 });
    writer.nextRow();

    writer.addCellInt(2);
    writer.addCellString("Item B");
    writer.addCellFloat(20.75);
    writer.addCellDatetime(xlsxio.Timestamp{ .secs = 1737094027 });
    writer.nextRow();

    writer.addCellInt(3);
    writer.addCellString("Item C");
    writer.addCellFloat(30.25);
    writer.addCellDatetime(xlsxio.Timestamp{ .secs = 1737094027 });
    writer.nextRow();

    std.log.info("Excel file created successfully at {s}", .{filename});
}
