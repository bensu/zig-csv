const std = @import("std");
const fs = std.fs;
const csv_mod = @import("csv.zig");
const sm = @import("state.zig");

const parse_utils = @import("parse_utils.zig");
const serialize = @import("serialize.zig");

const Type = std.builtin.Type;

// Want to do something that feels like a JIT

// 1. Read a schema from a file
// 2. Load a CSV file containing data that matches the schema
// 3. Print that

// I can start by doing that for a known schema and then seeing how to read the schema

// const csv_config = csv_mod.CsvConfig{
//     .col_sep = ',',
//     .row_sep = '\n',
//     .quote = '"',
// };

// Writing a CSV library that knew how to read directly into Structs would be cool

// something like

// readCSV(StructType, allocator, path) -> std.ArrayList(StructType)

// bonus points if it can be called during comptime to get a compile time array

// what is the ideal API?

// 1. Streaming so that the user can control how much memory to consume
// 2. Coerces to the types you already want
// 3. Efficient so that you can do it quickly if you want
// 4. Can read files partially

// var csv_reader = csv.Reader.init(T, allocator, file_reader, csv_config);
// csv_reader.nextRow() -> ?T
// if ?T is null, we are done

pub const InitUserError = error{
    OutOfMemory,
    BadInput,
};

pub const NextUserError = error{
    BadInput,
    MissingFields,
    ExtraFields,
};

// Errors from csv.zig:

// 'error.MisplacedQuote' not a member of destination error set
// 'error.NoSeparatorAfterField' not a member of destination error set
// 'error.ShortBuffer' not a member of destination error set
// 'error.AccessDenied' not a member of destination error set
// 'error.BrokenPipe' not a member of destination error set
// 'error.ConnectionResetByPeer' not a member of destination error set
// 'error.ConnectionTimedOut' not a member of destination error set
// 'error.InputOutput' not a member of destination error set
// 'error.IsDir' not a member of destination error set
// 'error.NotOpenForReading' not a member of destination error set
// 'error.OperationAborted' not a member of destination error set
// 'error.SystemResources' not a member of destination error set
// 'error.Unexpected' not a member of destination error set
// 'error.WouldBlock' not a member of destination error set

const CsvConfig = struct {
    skip_first_row: bool = true,
};

pub fn CsvParser(
    comptime T: type,
) type {
    return struct {
        const Self = @This();

        const Fields: []const Type.StructField = switch (@typeInfo(T)) {
            .Struct => |S| S.fields,
            else => @compileError("T needs to be a struct"),
        };

        const number_of_fields: usize = Fields.len;

        allocator: std.mem.Allocator,
        reader: fs.File.Reader, // TODO: allow other types of readers
        // csv_tokenizer: csv_mod.CsvTokenizer(fs.File.Reader),
        sm: sm.CsvTokenizer,
        config: CsvConfig,

        pub fn init(allocator: std.mem.Allocator, reader: fs.File.Reader, config: CsvConfig) InitUserError!Self {
            // TODO: How should this buffer work?
            var field_buffer = try allocator.alloc(u8, 4096);
            // var csv_tokenizer = try csv_mod.CsvTokenizer(fs.File.Reader).init(reader, buffer, .{});
            var state_machine = sm.CsvTokenizer{ .reader = reader, .field_buffer = field_buffer };

            var self = Self{
                .allocator = allocator,
                .reader = reader,
                .config = config,
                .sm = state_machine,
            };

            if (config.skip_first_row) {
                try self.consume_row();
            }

            return self;
        }

        // Try to read a row and return a parsed T out of it if possible
        pub fn next(self: *Self) NextUserError!?T {
            var draft_t: T = undefined;
            var fields_added: u32 = 0;
            inline for (Fields) |Field| {
                const token = self.sm.next() catch {
                    return error.BadInput;
                };
                // std.debug.print("Getting next token {s}\n", .{token.field});
                switch (token) {
                    .row_end => return error.MissingFields,
                    .eof => return null,
                    .field => {
                        if (comptime Field.field_type == []const u8) {
                            var new_buffer: [4096]u8 = undefined;
                            std.mem.copy(u8, &new_buffer, token.field);
                            @field(draft_t, Field.name) = new_buffer[0..token.field.len];
                        } else {
                            const FieldInfo = @typeInfo(Field.field_type);
                            switch (FieldInfo) {
                                .Optional => {
                                    const NestedFieldType: type = FieldInfo.Optional.child;
                                    if (token.field.len == 0) {
                                        @field(draft_t, Field.name) = null;
                                    } else {
                                        @field(draft_t, Field.name) = parse_utils.parseAtomic(NestedFieldType, Field.name, token.field) catch {
                                            return error.BadInput;
                                        };
                                    }
                                },
                                else => {
                                    @field(draft_t, Field.name) = parse_utils.parseAtomic(Field.field_type, Field.name, token.field) catch {
                                        return error.BadInput;
                                    };
                                },
                            }
                        }
                        // std.debug.print("Adding field\n", .{});
                        fields_added = fields_added + 1;
                    },
                }
            }

            // consume the row_end
            const token = self.sm.next() catch {
                return error.BadInput;
            };
            switch (token) {
                .field => {
                    std.debug.print("Extra fields {s}\n", .{token.field});
                    return error.ExtraFields;
                },
                .row_end => {},
                .eof => {},
            }

            // were all the fields added?
            if (fields_added == number_of_fields) {
                return draft_t;
            } else {
                // ERROR
                return null;
            }
        }

        fn consume_row(self: *Self) !void {
            var token = self.sm.next() catch {
                return error.BadInput;
            };
            var continue_loop = true;
            while (continue_loop) {
                switch (token) {
                    .field => {
                        token = self.sm.next() catch {
                            return error.BadInput;
                        };
                        continue;
                    },
                    .row_end, .eof => {
                        continue_loop = false;
                        break;
                    },
                }
            }
        }
    };
}

const DynStruct = struct {
    id: i64,
    age: []const u8,
};

const Indexes = struct {
    series: []const u8,
    period: []const u8,
    value: ?f32,
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
    const file_path = "data/trade-indexes.csv";
    const allocator = std.heap.page_allocator;
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();
    const reader = file.reader();

    var csv_parser_two = try CsvParser(Indexes).init(allocator, reader, .{});
    var rows: usize = 0;
    while (try csv_parser_two.next()) |_| {
        // std.debug.print("Row: {}\n", .{rows});
        // std.debug.print("{}\n", .{row});
        rows = rows + 1;
    }
    std.debug.print("Number of rows: {}\n", .{rows});
}

fn checkMemory() anyerror!void {
    const file_path = "data/trade-indexes.csv";
    const allocator = std.heap.page_allocator;
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();
    const reader = file.reader();

    var csv_parser = try CsvParser(Indexes).init(allocator, reader, .{});
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
    const csv_config = serialize.CsvConfig{ .skip_first_row = true };
    var writer = std.io.getStdOut().writer();
    var csv_serializer = serialize.CsvSerializer(Indexes).init(csv_config, writer);

    const file_path = "data/trade-indexes.csv";
    const allocator = std.heap.page_allocator;
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();
    const reader = file.reader();

    var csv_parser = try CsvParser(Indexes).init(allocator, reader, .{});

    while (try csv_parser.next()) |row| {
        try csv_serializer.appendRow(row);
    }
}

pub fn main() anyerror!void {
    const file_path: []const u8 = "data.csv";
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

        var csv_parser = try CsvParser(DynStruct).init(allocator, second_reader, .{});
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

        var csv_parser_two = try CsvParser(DynStruct).init(allocator, reader, .{});
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
    if (true) {
        try testCsvSerializer();
    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
