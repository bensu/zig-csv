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
    OutOfMemory,
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

        allocator: std.mem.Allocator,
        reader: fs.File.Reader, // TODO: allow other types of readers
        tokenizer: tokenize.CsvTokenizer,
        config: CsvConfig,

        pub fn init(
            allocator: std.mem.Allocator,
            reader: fs.File.Reader,
            config: CsvConfig,
        ) InitUserError!Self {
            // TODO: give user a way to describe what the longest field might be
            var field_buffer = try allocator.alloc(u8, 4096);

            var tokenizer = tokenize.CsvTokenizer{ .reader = reader, .field_buffer = field_buffer };

            var self = Self{
                .reader = reader,
                .config = config,
                .tokenizer = tokenizer,
                .allocator = allocator,
            };

            if (config.skip_first_row) {
                try self.consume_row();
            }

            return self;
        }

        // Try to read a row and return a parsed T out of it if possible
        pub fn next(self: *Self) NextUserError!?T {
            // TODO: Who should be managing draft_t's memory?
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
                        // the user wants an immutable slice
                        // we need to grab what we read, copy it somewhere it will remain valid
                        // and then give them that slice

                        const FieldInfo = @typeInfo(Field.field_type);
                        switch (FieldInfo) {
                            .Array => |info| {
                                if (comptime info.child != u8) {
                                    @compileError("Arrays can only be u8 and '" ++ Field.name ++ "'' is " ++ @typeName(info.child));
                                }

                                // TODO: should we drop bytes or should we throw an error?
                                if (info.len < token.field.len) {
                                    return error.BadInput;
                                }

                                std.mem.copy(u8, &@field(draft_t, Field.name), token.field);
                            },
                            .Pointer => |info| {
                                switch (info.size) {
                                    .Slice => {
                                        if (info.child != u8) {
                                            @compileError("Slices can only be u8 and '" ++ Field.name ++ "' is " ++ @typeName(info.child));
                                        } else if (info.is_const) {
                                            const mutable_slice = self.allocator.alloc(u8, token.field.len) catch {
                                                return error.OutOfMemory;
                                            };
                                            std.mem.copy(u8, mutable_slice, token.field);
                                            @field(draft_t, Field.name) = mutable_slice[0..token.field.len];
                                        } else {
                                            @compileError("Mutable slices are not implemented and '" ++ Field.name ++ "' is a mutable slice");
                                        }
                                    },
                                    else => @compileError("Pointer not implemented yet and '" ++ Field.name ++ "'' is a pointer."),
                                }
                            },
                            .Optional => {
                                // Unwrap the optional
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

fn testStructEql(comptime T: type, a: T, b: T) !void {
    const TypeInfo = @typeInfo(T);
    switch (TypeInfo) {
        .Optional => {
            const NestedFieldType: type = TypeInfo.Optional.child;
            if (a) |def_a| {
                if (b) |def_b| {
                    try testStructEql(NestedFieldType, def_a, def_b);
                } else {
                    try std.testing.expect(def_a == null);
                }
            } else {
                if (b) |def_b| {
                    try std.testing.expect(def_b == null);
                } else {
                    try std.testing.expect(true);
                }
            }
        },
        .Struct => {
            const Fields = TypeInfo.Struct.fields;
            inline for (Fields) |Field| {
                if (comptime Field.field_type == []const u8) {
                    // std.debug.print("Comparing {s} and {s}\n", .{ @field(a, Field.name), @field(b, Field.name) });
                    try std.testing.expect(std.mem.eql(u8, a.name, b.name));
                } else {
                    try std.testing.expectEqual(@field(a, Field.name), @field(b, Field.name));
                }
            }
        },
        else => @compileError("Invalid type: " ++ @typeName(T) ++ ". Should be Optional or Struct"),
    }
}

// const builtin = @import("std").builtin;
//
// fn structEql(comptime T: type, a: T, b: T) bool {
//     const Fields = @typeInfo(T).Struct.fields;
//     inline for (Fields) |Field| {
//         if (comptime Field.field_type == []const u8) {
//             if (!std.mem.eql(u8, @field(a, Field.name), @field(b, Field.name))) {
//                 return false;
//             }
//         } else {
//             if (!builtin.eql(@field(a, Field.name), @field(b, Field.name))) {
//                 return false;
//             }
//         }
//     }
//     return true;
// }

test "parse" {
    var allocator = std.testing.allocator;

    const file_path = "test/data/simple_parse.csv";
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();

    const SimpleParse = struct {
        id: u32,
        name: []const u8,
        unit: f32,
        nilable: ?u64,
    };

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = try CsvParser(SimpleParse).init(arena.allocator(), file.reader(), .{});

    const maybe_first_row = try parser.next();

    // we the second struct before testing to see if the first row keeps its contents
    const maybe_second_row = try parser.next();

    if (maybe_first_row) |row| {
        const expected_row: SimpleParse = SimpleParse{
            .id = 1,
            .name = "abc",
            .unit = 1.1,
            .nilable = 111,
        };
        try testStructEql(SimpleParse, expected_row, row);
    } else {
        std.debug.print("Error parsing first row\n", .{});
        try std.testing.expectEqual(false, true);
    }

    if (maybe_second_row) |row| {
        const expected_row: SimpleParse = SimpleParse{
            .id = 22,
            .name = "cdef",
            .unit = 22.2,
            .nilable = null,
        };
        try testStructEql(SimpleParse, expected_row, row);
    } else {
        std.debug.print("Error parsing second row\n", .{});
        try std.testing.expectEqual(false, true);
    }

    const maybe_third_row = try parser.next();

    // we the fourth struct before testing to see if the third row keeps its contents
    const maybe_fourth_row = try parser.next();

    if (maybe_third_row) |row| {
        const expected_row: SimpleParse = SimpleParse{
            .id = 333,
            .name = "ghijk",
            .unit = 33.33,
            .nilable = 3333,
        };
        try testStructEql(SimpleParse, expected_row, row);
    } else {
        std.debug.print("Error parsing third row\n", .{});
        try std.testing.expectEqual(false, true);
    }

    if (maybe_fourth_row) |_| {
        std.debug.print("Error parsing fourth row, expected null\n", .{});
        try std.testing.expectEqual(false, true);
    }
}

test "parse mutable slices" {
    const SliceParse = struct {
        id: u32,
        name: []const u8,
        unit: f32,
        nilable: ?u64,
    };
    var allocator = std.testing.allocator;

    const file_path = "test/data/simple_parse.csv";
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = try CsvParser(SliceParse).init(arena.allocator(), file.reader(), .{});

    const maybe_first_row = try parser.next();
    const maybe_second_row = try parser.next();
    if (maybe_first_row) |row| {
        const expected_row = SliceParse{
            .id = 1,
            .name = "abc",
            .unit = 1.1,
            .nilable = 111,
        };
        try testStructEql(SliceParse, expected_row, row);
    } else {
        std.debug.print("Error parsing first row\n", .{});
        try std.testing.expectEqual(false, true);
    }

    if (maybe_second_row) |row| {
        const expected_row = SliceParse{
            .id = 22,
            .name = "cdef",
            .unit = 22.2,
            .nilable = null,
        };
        try testStructEql(SliceParse, expected_row, row);
    } else {
        std.debug.print("Error parsing second row\n", .{});
        try std.testing.expectEqual(false, true);
    }
}
