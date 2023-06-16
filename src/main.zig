const std = @import("std");
const fs = std.fs;

const utils = @import("utils.zig");
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

const WorldCityPopulation = struct {
    country: []const u8,
    city: []const u8,
    accent_city: []const u8,
    region: []const u8,
    population: ?u64,
    latitude: f64,
    longitude: f64,
};

fn benchmark() anyerror!void {
    const file_path = "benchmark/data/worldcitiespop.csv";
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();

    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    var buffer: [4096 * 10]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    var parser = try parse.CsvParser(WorldCityPopulation).init(allocator, file.reader(), .{});
    var population: u64 = 0;
    while (try parser.next()) |row| {
        if (std.mem.eql(u8, "us", row.country) and std.mem.eql(u8, "MA", row.region)) {
            population += (row.population orelse 0);
        }
        fba.reset();
    }
    std.debug.print("Number of US-MA population: {}\n", .{population});
}

fn checkMemory() anyerror!void {
    const allocator = std.heap.page_allocator;

    const file_path = "data/trade-indexes.csv";
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();
    const reader = file.reader();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var csv_parser = try parse.CsvParser(Indexes).init(arena.allocator(), reader, .{});
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

    var from_file = try fs.cwd().openFile(from_path, .{});
    defer from_file.close();
    const reader = from_file.reader();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var csv_parser = try parse.CsvParser(T).init(arena.allocator(), reader, .{});

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

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var csv_parser = try parse.CsvParser(Simple).init(arena.allocator(), second_reader, .{});
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

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var csv_parser_two = try parse.CsvParser(IntId).init(arena.allocator(), reader, .{});
        var rows: usize = 0;
        var id_sum: i64 = 0;
        while (try csv_parser_two.next()) |row| {
            id_sum = id_sum + row.id;
            rows = rows + 1;
        }
        std.debug.print("Number of rows: {}\n", .{rows});
        std.debug.print("Sum of id: {}\n", .{id_sum});
    }
    if (true) {
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

test "call all tests" {
    _ = @import("tokenize.zig");
    _ = @import("fast_tokenize.zig");
    _ = @import("parse.zig");
    _ = @import("serialize.zig");
    _ = @import("end_to_end_test.zig");
}
