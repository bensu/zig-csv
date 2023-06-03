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

const field_end_delimiter = ',';
const row_end_delimiter = '\n';
const quote_delimiter = '"';

const State = enum {
    in_row,
    in_quote,
    row_end,
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
                self.stream_index = 1;
                return self.stream_buffer[0];
            }
        } else {
            // we are still within the stream_buffer, just return the next char
            self.stream_index = (self.stream_index + 1);
            // std.debug.print("stream_index: {}\n", .{self.stream_index});
            return self.stream_buffer[self.stream_index - 1];
        }
    }

    pub fn next(self: *CsvTokenizer) !Token {
        switch (self.state) {
            .eof => return Token{ .eof = null },
            .row_end => {
                self.state = .in_row;
                return Token{ .row_end = null };
            },
            else => {},
        }

        var index: usize = 0;
        while (true) {
            if (index >= self.field_buffer.len) return error.StreamTooLong;

            const byte = self.readChar() catch |err| switch (err) {
                error.EndOfStream => {
                    if (index == 0) {
                        self.state = .eof;
                        return Token{ .eof = null };
                    } else {
                        self.state = .eof;
                        return Token{ .field = self.field_buffer[0..index] };
                    }
                },
                else => |e| return e,
            };
            self.field_buffer[index] = byte;

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
                switch (byte) {
                    field_end_delimiter => {
                        return Token{ .field = self.field_buffer[0..index] };
                    },
                    row_end_delimiter => {
                        self.state = .row_end;
                        return Token{ .field = self.field_buffer[0..index] };
                    },
                    else => {
                        index += 1;
                    },
                }
            }
        }
    }
};
