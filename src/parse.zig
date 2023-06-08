const std = @import("std");
const fs = std.fs;

const parse_utils = @import("parse_utils.zig");

const Type = std.builtin.Type;

// ============================================================================
// Tokenizer

const TokenTag = enum { field, row_end, eof };

const Token = union(TokenTag) { field: []u8, row_end, eof };

const field_end_delimiter = ',';
const row_end_delimiter = '\n';
const quote_delimiter = '"';

const State = enum {
    // default state, reading a field
    in_row,
    // while reading row, we found the end. return the field and hold state
    // to return the row_end token on the next call
    row_end,
    // eof terminal state. if eof, always returns Token.eof
    eof,
};

const ReadingError = error{
    EndOfStream,
};

const STREAM_INDEX_LEN: usize = 256;

pub const CsvTokenizer = struct {
    reader: fs.File.Reader,
    field_buffer: []u8,
    state: State = .in_row,

    // manages underlying file reader
    stream_buffer: [STREAM_INDEX_LEN]u8 = undefined,
    stream_index: usize = 0, // should always be within stream_index
    stream_available: usize = 0, // how many bytes are available in the stream_buffer

    // asks for a char from the stream_buffer, potentially reads another chunk
    fn readChar(self: *CsvTokenizer) ReadingError!u8 {
        // if we reached the end of the stream_buffer, read another chunk
        if (self.stream_index == self.stream_available) {
            const n = self.reader.read(&self.stream_buffer) catch {
                return error.EndOfStream;
            };
            if (n == 0) {
                return error.EndOfStream;
            } else {
                // restart the stream_index because we read again
                self.stream_available = n;
                // this equivalent to self.stream_index = 0;
                // returning the first char (as the last line does) and then incrementing
                self.stream_index = 1;
                return self.stream_buffer[0];
            }
        } else {
            // we are still within the stream_buffer, just return the next char
            self.stream_index = (self.stream_index + 1);
            return self.stream_buffer[self.stream_index - 1];
        }
    }

    pub fn next(self: *CsvTokenizer) !Token {
        switch (self.state) {
            .eof => return Token.eof,
            .row_end => {
                self.state = .in_row;
                return Token.row_end;
            },
            .in_row => {
                // try to read the entire field
                var was_quote: bool = false;
                var index: usize = 0;
                var in_quote: bool = false;
                while (true) {
                    if (index >= self.field_buffer.len) return error.StreamTooLong;

                    const byte = self.readChar() catch |err| switch (err) {
                        error.EndOfStream => {
                            if (index == 0) {
                                self.state = .eof;
                                return Token.eof;
                            } else {
                                self.state = .eof;
                                if (was_quote) {
                                    return Token{ .field = self.field_buffer[1..(index - 1)] };
                                } else {
                                    return Token{ .field = self.field_buffer[0..index] };
                                }
                            }
                        },
                        else => |e| return e,
                    };
                    self.field_buffer[index] = byte;

                    // we found a quote
                    if (byte == quote_delimiter) {
                        if (in_quote) {
                            // this is the second quote, closing
                            in_quote = false;
                            // TODO: this doesn't enforce that the next char is a row_end_delimiter
                        } else {
                            // this is the first quote, opening
                            in_quote = true;
                            was_quote = true;
                        }
                    }

                    if (in_quote) {
                        // while we are in_quote, keep adding chars to the buffer
                        index += 1;
                        continue;
                    } else {
                        switch (byte) {
                            field_end_delimiter => {
                                if (was_quote) {
                                    return Token{ .field = self.field_buffer[1..(index - 1)] };
                                } else {
                                    return Token{ .field = self.field_buffer[0..index] };
                                }
                            },
                            row_end_delimiter => {
                                if (index == 0) {
                                    // we found a row end without a field, i.e. a trailing comma
                                    // 1,2,3,\n
                                    // return Token{ .field = "" };
                                    return Token.row_end;
                                } else {
                                    // we found a row end while reading a field, no trailing comma
                                    // 1,2,3\n
                                    self.state = .row_end;
                                    if (was_quote) {
                                        return Token{ .field = self.field_buffer[1..(index - 1)] };
                                    } else {
                                        return Token{ .field = self.field_buffer[0..index] };
                                    }
                                }
                            },
                            else => index += 1,
                        }
                    }
                }
            },
        }
    }
};

test "tokenize" {
    const allocator = std.testing.allocator;
    const file = try fs.cwd().openFile("test/data/simple_tokenize.csv", .{});
    defer file.close();
    const reader = file.reader();
    var field_buffer = try allocator.alloc(u8, 4096);
    defer allocator.free(field_buffer);

    var tokenizer = CsvTokenizer{ .reader = reader, .field_buffer = field_buffer };

    const first_row_tokens = [_][]const u8{ "1", "2", "3" };
    for (first_row_tokens) |expected_token| {
        const received_token = try tokenizer.next();
        try std.testing.expectEqualStrings(expected_token, received_token.field);
    }

    const row_end_token = try tokenizer.next();
    try std.testing.expect(row_end_token == Token.row_end);

    const second_row_tokens = [_][]const u8{ "4", "5", "6" };
    for (second_row_tokens) |expected_token| {
        const received_token = try tokenizer.next();
        try std.testing.expectEqualStrings(expected_token, received_token.field);
    }

    const second_row_end = try tokenizer.next();
    try std.testing.expect(second_row_end == Token.row_end);

    const third_row_tokens = [_][]const u8{ "7", "", "9" };
    for (third_row_tokens) |expected_token| {
        const received_token = try tokenizer.next();
        // std.debug.print("{}", received_token);
        try std.testing.expectEqualStrings(expected_token, received_token.field);
    }

    const third_row_end = try tokenizer.next();
    try std.testing.expect(third_row_end == Token.row_end);

    const fourth_row_tokens = [_][]const u8{ "10", " , , ", "12" };
    for (fourth_row_tokens) |expected_token| {
        const received_token = try tokenizer.next();
        // std.debug.print("{}", received_token);
        try std.testing.expectEqualStrings(expected_token, received_token.field);
    }

    const fourth_row_end = try tokenizer.next();
    try std.testing.expect(fourth_row_end == Token.row_end);

    const eof_token = try tokenizer.next();
    try std.testing.expect(eof_token == Token.eof);
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
        // tokenizer: csv_mod.CsvTokenizer(fs.File.Reader),
        tokenizer: CsvTokenizer,
        config: CsvConfig,

        pub fn init(field_buffer: []u8, reader: fs.File.Reader, config: CsvConfig) InitUserError!Self {
            // TODO: How should this buffer work?
            // var field_buffer = try allocator.alloc(u8, 4096);
            // var tokenizer = try csv_mod.CsvTokenizer(fs.File.Reader).init(reader, buffer, .{});
            var tokenizer = CsvTokenizer{ .reader = reader, .field_buffer = field_buffer };

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
