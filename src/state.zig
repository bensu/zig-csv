// simple state machine

const std = @import("std");
const fs = std.fs;

const TokenTag = enum {
    field,
    row_end,
    eof,
};

const Token = union(TokenTag) {
    field: []u8,
    row_end: @TypeOf(null),
    eof: @TypeOf(null),
};

// Reader helper

fn readUntilDelimitersOrEof(reader: fs.File.Reader, buf: []u8, field_end_delimiter: u8, row_end_delimiter: u8) !Token {
    var index: usize = 0;
    while (true) {
        if (index >= buf.len) return error.StreamTooLong;

        const byte = reader.readByte() catch |err| switch (err) {
            error.EndOfStream => {
                if (index == 0) {
                    return Token{ .eof = null };
                } else {
                    return Token{ .row_end = buf[0..index] };
                }
            },
            else => |e| return e,
        };
        buf[index] = byte;

        if (byte == field_end_delimiter) return Token{ .field = buf[0..index] };
        if (byte == row_end_delimiter) return Token{ .row_end = buf[0..index] };

        index += 1;
    }
}

const State = enum {
    in_row,
    in_quote,
    row_end,
    eof,
};

pub const CsvTokenizer = struct {
    reader: fs.File.Reader,
    buffer: []u8,
    state: State = .in_row,

    pub fn next(self: *CsvTokenizer) !Token {
        if (self.state == .eof) {
            return Token{ .eof = null };
        }
        if (self.state == .row_end) {
            self.state = .in_row;
            return Token{ .row_end = null };
        }

        const field_end_delimiter = ',';
        const row_end_delimiter = '\n';
        const quote_delimiter = '"';

        var index: usize = 0;
        while (true) {
            if (index >= self.buffer.len) return error.StreamTooLong;

            const byte = self.reader.readByte() catch |err| switch (err) {
                error.EndOfStream => {
                    if (index == 0) {
                        self.state = .eof;
                        return Token{ .eof = null };
                    } else {
                        self.state = .eof;
                        return Token{ .field = self.buffer[0..index] };
                    }
                },
                else => |e| return e,
            };
            self.buffer[index] = byte;

            // we found a quote
            if (byte == quote_delimiter) {
                if (self.state == .in_quote) {
                    // this is the second quote, closing
                    self.state = .in_row;
                } else {
                    // this is the first quote, opening
                    self.state = .in_quote;
                }
            }

            if (self.state == .in_quote) {
                index += 1;
                continue;
            } else {
                if (byte == field_end_delimiter) {
                    return Token{ .field = self.buffer[0..index] };
                }

                // Should row_end_delimiters belong in quotes
                if (byte == row_end_delimiter) {
                    self.state = .row_end;
                    return Token{ .field = self.buffer[0..index] };
                }
                index += 1;
            }
        }
    }
};
