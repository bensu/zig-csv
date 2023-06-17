const std = @import("std");
const fs = std.fs;

const utils = @import("utils.zig");
const serialize = @import("serialize.zig");
const parse = @import("parse.zig");

const Simple = struct {
    id: []const u8,
    age: []const u8,
};

fn copyCsv(comptime T: type, from_path: []const u8, to_path: []const u8) !usize {
    var from_file = try fs.cwd().openFile(from_path, .{});
    defer from_file.close();
    const reader = from_file.reader();

    var to_file = try fs.cwd().createFile(to_path, .{});
    defer to_file.close();
    const writer = to_file.writer();

    const allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = try parse.CsvParser(fs.File.Reader, T, .{}).init(arena.allocator(), reader);

    var serializer = serialize.CsvSerializer(T, .{}).init(writer);

    var rows: usize = 0;
    try serializer.writeHeader();
    while (try parser.next()) |row| {
        rows = rows + 1;
        try serializer.appendRow(row);
    }

    return rows;
}

test "end to end" {
    const from_path = "test/data/simple_end_to_end.csv";
    const to_path = "tmp/simple_end_to_end.csv";

    var from_file = try fs.cwd().openFile(from_path, .{});
    defer from_file.close();

    var to_file = try fs.cwd().openFile(to_path, .{});
    defer to_file.close();

    const rows = try copyCsv(Simple, from_path, to_path);

    const expected_rows: usize = 17;
    try std.testing.expectEqual(expected_rows, rows);

    try std.testing.expect(try utils.eqlFileContents(from_file, to_file));
}
