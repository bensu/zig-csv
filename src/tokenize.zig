const std = @import("std");
const fs = std.fs;

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

    // Tokenizer.next() returns:
    //  Token.eof => end of file
    //  Token.row_end => end of row
    //  Token.field => containing a []const u8 slice with the field contents
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

fn testFile(file: fs.File, expected_token_rows: [][]u8) !void {
    const reader = file.reader();

    const allocator = std.testing.allocator;
    var field_buffer = try allocator.alloc(u8, 4096);
    defer allocator.free(field_buffer);

    var tokenizer = CsvTokenizer{ .reader = reader, .field_buffer = field_buffer };

    for (expected_token_rows) |expected_row| {
        for (expected_row) |expected_token| {
            const received_token = try tokenizer.next();
            try std.testing.expectEqualStrings(expected_token, received_token.field);
        }
        const row_end_token = try tokenizer.next();
        try std.testing.expect(row_end_token == Token.row_end);
    }

    const eof_token = try tokenizer.next();
    try std.testing.expect(eof_token == Token.eof);
}

test "tokenize" {
    const file = try fs.cwd().openFile("test/data/simple_tokenize.csv", .{});
    defer file.close();

    const allocator = std.testing.allocator;
    var field_buffer = try allocator.alloc(u8, 4096);
    defer allocator.free(field_buffer);

    var tokenizer = CsvTokenizer{ .reader = file.reader(), .field_buffer = field_buffer };

    const expected_token_rows = [5][3][]const u8{
        [_][]const u8{ "1", "2", "3" },
        [_][]const u8{ "4", "5", "6" },
        [_][]const u8{ "7", "", "9" },
        [_][]const u8{ "10", " , , ", "12" },
        [_][]const u8{ "13", "14", "" },
    };

    for (expected_token_rows) |expected_row| {
        for (expected_row) |expected_token| {
            const received_token = try tokenizer.next();
            try std.testing.expectEqualStrings(expected_token, received_token.field);
        }
        const row_end_token = try tokenizer.next();
        try std.testing.expect(row_end_token == Token.row_end);
    }

    const eof_token = try tokenizer.next();
    try std.testing.expect(eof_token == Token.eof);
}

test "tokenize enums" {
    const file = try fs.cwd().openFile("test/data/parse_enum.csv", .{});
    defer file.close();

    const allocator = std.testing.allocator;
    var field_buffer = try allocator.alloc(u8, 4096);
    defer allocator.free(field_buffer);

    const expected_token_rows = [4][5][]const u8{
        [_][]const u8{ "id", "name", "color", "unit", "nilable" },
        [_][]const u8{ "1", "ON", "red", "1.1", "111" },
        [_][]const u8{ "22", "OFF", "blue", "22.2", "" },
        [_][]const u8{ "333", "ON", "something else", "33.33", "3333" },
    };

    var tokenizer = CsvTokenizer{ .reader = file.reader(), .field_buffer = field_buffer };

    for (expected_token_rows) |expected_row| {
        for (expected_row) |expected_token| {
            const received_token = try tokenizer.next();
            // debugToken(received_token);
            try std.testing.expectEqualStrings(expected_token, received_token.field);
        }
        const row_end_token = try tokenizer.next();
        try std.testing.expect(row_end_token == Token.row_end);
    }

    const eof_token = try tokenizer.next();
    try std.testing.expect(eof_token == Token.eof);
}
