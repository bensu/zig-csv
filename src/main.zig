const std = @import("std");
const fs = std.fs;

const serialize = @import("serialize.zig");
const parse = @import("parse.zig");

const Simple = struct {
    id: []const u8,
    age: []const u8,
};

const IntId = struct {
    id: i64,
    age: []const u8,
};

const Indexes = struct {
    series: []const u8,
    period: []const u8,
    value: []const u8,
    status: []const u8,
    units: []const u8,
    magnitude: []const u8,
    subject: []const u8,
    group: []const u8,
    title_1: []const u8,
    title_2: []const u8,
    title_3: []const u8,
    title_4: []const u8,
    title_5: []const u8,

    pub fn format(
        v: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) std.os.WriteError!void {
        try writer.print("series: \"{s}\" ", .{v.series});
        try writer.print("period: \"{s}\" ", .{v.period});
        try writer.print("value: {?} ", .{v.value});
        try writer.print("status: \"{s}\" ", .{v.status});
        try writer.print("units: \"{s}\" ", .{v.units});
        try writer.print("magnitude: \"{s}\" ", .{v.magnitude});
        try writer.print("subject: \"{s}\" ", .{v.subject});
        try writer.print("group: \"{s}\" ", .{v.group});
        try writer.print("title_1: \"{s}\" ", .{v.title_1});
        try writer.print("title_2: \"{s}\" ", .{v.title_2});
        try writer.print("title_3: \"{s}\" ", .{v.title_3});
        try writer.print("title_4: \"{s}\" ", .{v.title_4});
        return writer.print("title_5: \"{s}\" ", .{v.title_5});
    }
};

fn benchmark() anyerror!void {
    const allocator = std.heap.page_allocator;
    var field_buffer = try allocator.alloc(u8, 4096);
    defer allocator.free(field_buffer);

    const file_path = "data/trade-indexes.csv";
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();
    const reader = file.reader();

    var csv_parser_two = try parse.CsvParser(Indexes).init(field_buffer, reader, .{});
    var rows: usize = 0;
    while (try csv_parser_two.next()) |_| {
        // std.debug.print("Row: {}\n", .{rows});
        // std.debug.print("{}\n", .{row});
        rows = rows + 1;
    }
    std.debug.print("Number of rows: {}\n", .{rows});
}

fn checkMemory() anyerror!void {
    const allocator = std.heap.page_allocator;
    var field_buffer = try allocator.alloc(u8, 4096);
    defer allocator.free(field_buffer);

    const file_path = "data/trade-indexes.csv";
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();
    const reader = file.reader();

    var csv_parser = try parse.CsvParser(Indexes).init(field_buffer, reader, .{});
    const first_row = try csv_parser.next();
    if (first_row) |row| {
        std.debug.print("First: {s}\n", .{row.series});
    }
    const second_row = try csv_parser.next();
    if (second_row) |row| {
        std.debug.print("Second: {s}\n", .{row.series});
    }
    const third_row = try csv_parser.next();
    if (third_row) |row| {
        std.debug.print("Second: {s}\n", .{row.series});
    }
    if (first_row) |row| {
        std.debug.print("First: {s}\n", .{row.series});
    }
    if (second_row) |row| {
        std.debug.print("Second: {s}\n", .{row.series});
    }
    if (third_row) |row| {
        std.debug.print("Second: {s}\n", .{row.series});
    }
}

fn testCsvSerializer() !void {
    const from_path = "data/trade-indexes.csv";
    const to_path = "tmp/trade-indexes.csv";
    const T = Indexes;

    // const from_path = "data/simple.csv";
    // const to_path = "tmp/simple.csv";
    // const T = Simple;

    const allocator = std.heap.page_allocator;
    var field_buffer = try allocator.alloc(u8, 4096);
    defer allocator.free(field_buffer);

    var from_file = try fs.cwd().openFile(from_path, .{});
    defer from_file.close();
    const reader = from_file.reader();
    var csv_parser = try parse.CsvParser(T).init(field_buffer, reader, .{});

    var to_file = try fs.cwd().createFile(to_path, .{}); // (to_path, .{});
    defer to_file.close();
    const writer = to_file.writer();
    var csv_serializer = serialize.CsvSerializer(T).init(.{}, writer);

    // const row = try csv_parser.next();

    try csv_serializer.writeHeader();
    while (try csv_parser.next()) |row| {
        // std.debug.print("Row: {}\n", .{row});
        try csv_serializer.appendRow(row);
    }
}

pub fn main() anyerror!void {
    const file_path: []const u8 = "data/simple.csv";
    const allocator = std.heap.page_allocator;

    // var file = try fs.cwd().openFile(file_path, .{});
    // defer file.close();
    // const reader = file.reader();
    // var myStruct = try readDynStruct(DynStruct, allocator, reader);
    // for (myStruct.items) |item| {
    //     std.debug.print("{}", .{item});
    // }

    // New
    if (false) {
        var second_file = try fs.cwd().openFile(file_path, .{});
        defer second_file.close();
        const second_reader = second_file.reader();

        var field_buffer = try allocator.alloc(u8, 4096);
        defer allocator.free(field_buffer);

        var csv_parser = try parse.CsvParser(Simple).init(field_buffer, second_reader, .{});
        const first_row = try csv_parser.next();
        std.debug.print("Parsed {?}\n", .{first_row});
        const second_row = try csv_parser.next();
        std.debug.print("Parsed {?}\n", .{second_row});
        const no_row = try csv_parser.next();
        std.debug.print("No field {?}\n", .{no_row});
    }

    if (false) {
        var file = try fs.cwd().openFile(file_path, .{});
        defer file.close();
        const reader = file.reader();

        var field_buffer = try allocator.alloc(u8, 4096);
        defer allocator.free(field_buffer);
        var csv_parser_two = try parse.CsvParser(IntId).init(field_buffer, reader, .{});
        var rows: usize = 0;
        var id_sum: i64 = 0;
        while (try csv_parser_two.next()) |row| {
            id_sum = id_sum + row.id;
            rows = rows + 1;
        }
        std.debug.print("Number of rows: {}\n", .{rows});
        std.debug.print("Sum of id: {}\n", .{id_sum});
    }
    if (false) {
        std.debug.print("Starting benchmark\n", .{});
        try benchmark();
    }
    if (false) {
        try checkMemory();
    }
    if (false) {
        try testCsvSerializer();
    }
}

fn copyCsv(comptime T: type, from_path: []const u8, to_path: []const u8) !usize {
    var from_file = try fs.cwd().openFile(from_path, .{});
    defer from_file.close();
    const reader = from_file.reader();

    var to_file = try fs.cwd().createFile(to_path, .{});
    defer to_file.close();
    const writer = to_file.writer();

    const allocator = std.testing.allocator;
    var field_buffer = try allocator.alloc(u8, 4096);
    defer allocator.free(field_buffer);
    var parser = try parse.CsvParser(T).init(field_buffer, reader, .{});

    var serializer = serialize.CsvSerializer(T).init(.{}, writer);

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
    const rows = try copyCsv(Simple, from_path, to_path);

    const expected_rows: usize = 17;
    try std.testing.expectEqual(expected_rows, rows);

    var from_file_check = try fs.cwd().openFile(from_path, .{});
    defer from_file_check.close();
    const from_reader = from_file_check.reader();

    var from_buffer: [1024]u8 = undefined;
    const from_bytes_read = try from_reader.read(&from_buffer);

    var to_file_check = try fs.cwd().openFile(to_path, .{});
    defer to_file_check.close();
    const to_reader = to_file_check.reader();

    var to_buffer: [1024]u8 = undefined;
    const to_bytes_read = try to_reader.read(&to_buffer);

    try std.testing.expectEqual(from_bytes_read, to_bytes_read);
    try std.testing.expect(std.mem.eql(u8, from_buffer[0..from_bytes_read], to_buffer[0..to_bytes_read]));
}
