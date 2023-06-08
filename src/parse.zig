const std = @import("std");
const fs = std.fs;
const Type = std.builtin.Type;

const tokenize = @import("tokenize.zig");

// ============================================================================
// Utils

pub inline fn parseAtomic(
    comptime T: type,
    comptime field_name: []const u8,
    input_val: []const u8,
) !T {
    switch (@typeInfo(T)) {
        .Int => {
            return std.fmt.parseInt(T, input_val, 0) catch {
                return error.BadInput;
            };
        },
        .Float => {
            return std.fmt.parseFloat(T, input_val) catch {
                return error.BadInput;
            };
        },
        else => {
            @compileError("Unsupported type " ++ @typeName(T) ++ " for field " ++ field_name);
        },
    }
}

// ============================================================================
// Parser

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

pub const CsvConfig = struct {
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

        reader: fs.File.Reader, // TODO: allow other types of readers
        tokenizer: tokenize.CsvTokenizer,
        config: CsvConfig,

        pub fn init(field_buffer: []u8, reader: fs.File.Reader, config: CsvConfig) InitUserError!Self {
            // TODO: How should this buffer work?
            // var field_buffer = try allocator.alloc(u8, 4096);
            var tokenizer = tokenize.CsvTokenizer{ .reader = reader, .field_buffer = field_buffer };

            var self = Self{
                .reader = reader,
                .config = config,
                .tokenizer = tokenizer,
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
                const token = self.tokenizer.next() catch {
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
                                        @field(draft_t, Field.name) = parseAtomic(NestedFieldType, Field.name, token.field) catch {
                                            return error.BadInput;
                                        };
                                    }
                                },
                                else => {
                                    @field(draft_t, Field.name) = parseAtomic(Field.field_type, Field.name, token.field) catch {
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
            const token = self.tokenizer.next() catch {
                return error.BadInput;
            };
            switch (token) {
                .field => {
                    if (token.field.len > 0) {
                        std.debug.print("Extra fields {s}\n", .{token.field});
                        return error.ExtraFields;
                    }
                    // we accept an extra comma at the end
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
            var token = self.tokenizer.next() catch {
                return error.BadInput;
            };
            var continue_loop = true;
            while (continue_loop) {
                switch (token) {
                    .field => {
                        token = self.tokenizer.next() catch {
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

test "parse" {
    var allocator = std.testing.allocator;
    const file_path = "test/data/simple_parse.csv";
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();
    const reader = file.reader();

    var field_buffer = try allocator.alloc(u8, 4096);
    defer allocator.free(field_buffer);

    const SimpleParse = struct {
        id: u32,
        name: []const u8,
        unit: f32,
        nilable: ?u64,

        const Self = @This();

        pub fn eql(a: Self, b: Self) bool {
            return a.id == b.id and std.mem.eql(u8, a.name, b.name) and a.unit == b.unit and a.nilable == b.nilable;
        }

        pub fn testEql(a: Self, b: Self) !void {
            try std.testing.expectEqual(a.id, b.id);
            try std.testing.expect(std.mem.eql(u8, a.name, b.name));
            try std.testing.expectEqual(a.unit, b.unit);
            try std.testing.expectEqual(a.nilable, b.nilable);
        }
    };

    var parser = try CsvParser(SimpleParse).init(field_buffer, reader, .{});

    const maybe_first_row = try parser.next();
    if (maybe_first_row) |row| {
        const expected_row: SimpleParse = SimpleParse{
            .id = 1,
            .name = "abc",
            .unit = 1.1,
            .nilable = 111,
        };
        try expected_row.testEql(row);
    } else {
        std.debug.print("Error parsing first row\n", .{});
        try std.testing.expectEqual(false, true);
    }
    const maybe_second_row = try parser.next();
    if (maybe_second_row) |row| {
        const expected_row: SimpleParse = SimpleParse{
            .id = 22,
            .name = "cdef",
            .unit = 22.2,
            .nilable = null,
        };
        try expected_row.testEql(row);
    } else {
        std.debug.print("Error parsing second row\n", .{});
        try std.testing.expectEqual(false, true);
    }

    const maybe_third_row = try parser.next();
    if (maybe_third_row) |row| {
        const expected_row: SimpleParse = SimpleParse{
            .id = 333,
            .name = "ghijk",
            .unit = 33.33,
            .nilable = 3333,
        };
        try expected_row.testEql(row);
    } else {
        std.debug.print("Error parsing third row\n", .{});
        try std.testing.expectEqual(false, true);
    }

    const maybe_fourth_row = try parser.next();
    if (maybe_fourth_row) |_| {
        std.debug.print("Error parsing fourth row, expected null\n", .{});
        try std.testing.expectEqual(false, true);
    }
}
