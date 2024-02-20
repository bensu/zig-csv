const std = @import("std");
const fs = std.fs;
const cnf = @import("config.zig");

const State = enum { in_row, row_end, eof };

const TokenTag = enum { field, row_end, eof };

const Token = union(TokenTag) { field: []const u8, row_end, eof };

fn debugToken(token: Token) void {
    switch (token) {
        .row_end => std.debug.print("Got row end\n", .{}),
        .eof => std.debug.print("Got EOF\n", .{}),
        .field => |field| {
            std.debug.print("Getting next token {s}\n", .{field});
        },
    }
}

pub const ReaderError = error{
    AccessDenied,
    BrokenPipe,
    ConnectionResetByPeer,
    ConnectionTimedOut,
    InputOutput,
    IsDir,
    NotOpenForReading,
    OperationAborted,
    SystemResources,
    Unexpected,
    WouldBlock,
    NetNameDeleted,
};

const InternalError = error{ EndOfStream, OutOfMemory };

pub const TokenizeSpecificError = error{OutOfMemory};

pub const TokenizeError = TokenizeSpecificError || ReaderError || error{EndOfStream};

pub fn CsvTokenizer(
    comptime Reader: type,
    comptime config: cnf.CsvConfig,
) type {
    return struct {
        const Self = @This();

        reader: Reader,
        state: State = .in_row,

        // we swap these everytime we read from the file system
        primary_buffer: [4096]u8 = undefined,
        backup_buffer: [4096]u8 = undefined,

        /// Up to which index in the primary buffer are there file bytes to read from
        buffer_available: usize = 0,

        /// The goes from field_start to field_start + field_len
        field_start: usize = 0,

        /// Before swaping, we have many of the field bytes (f) in the primary buffer:
        ///
        /// primary:  [ | | | | | | | | | | | | | | |f|f|f|f|f|f|f|f]
        ///                                          ^             ^
        ///                                field_start            (field_start + field_len) == buffer_available
        ///
        /// which we copy into backup:
        ///
        /// backup:   [f|f|f|f|f|f|f|f| | | | | | | | | | | | | | | ]
        ///            ^             ^
        ///  field_start             field_start + field_len
        ///
        /// and read the next chunk of new bytes (n) from the file into the backup bufer:
        ///
        ///
        /// backup:   [f|f|f|f|f|f|f|f|n|n|n|n|n|n|n|n|n|n|n|n|n|n|n]
        ///            ^             ^                             ^
        ///  field_start             (field_start + field_len)     buffer_available
        ///
        /// Finally, we swap the primary and backup buffers by switching is_blue_primary
        fn swapBuffers(self: *Self, field_len: usize) (InternalError || ReaderError)!u8 {
            var primary = &self.primary_buffer;
            var backup = &self.backup_buffer;

            if (field_len >= backup.len) {
                return error.OutOfMemory;
            }

            std.debug.assert(field_len < backup.len);

            if (field_len > 0) {
                const start = self.field_start;
                const end = start + field_len;
                std.mem.copy(u8, backup[0..field_len], primary[start..end]);
            }

            // self.buffer_available = field_len;

            // Can this be prefetched before mem.copy?
            const bytes_read = try self.reader.read(backup[field_len..]);

            self.field_start = 0;
            self.buffer_available = field_len + bytes_read;

            if (bytes_read == 0) {
                return error.EndOfStream;
            }

            var temp = self.primary_buffer;
            self.primary_buffer = self.backup_buffer;
            self.backup_buffer = temp;

            return self.primary_buffer[field_len];
        }

        /// It starts by reading part of the file into the primary buffer.
        /// Then, it iterates over byte in that buffer while incrementing the field_len index.
        /// When it finds a field_end_delimiter, it slices the buffer into a field and returns it.
        ///
        /// At some point, we reach the end of the buffer and need to read more bytes from the file.
        /// It is likely that we are mid-field and field_len != 0. At that point, we swapBuffers.
        fn readChar(self: *Self, field_len: usize) (InternalError || ReaderError)!u8 {
            var buffer = &self.primary_buffer;
            // std.debug.print("available start end {} {} {}\n", .{ self.buffer_available, self.field_start, self.field_end });

            const start = self.field_start;
            const end = start + field_len;
            const available = self.buffer_available;
            if (end < available) {
                return buffer[end];
            } else if (end == available) {
                if (start != end) {
                    return try self.swapBuffers(field_len);
                } else {
                    const bytes_read = try self.reader.read(buffer);

                    self.buffer_available = bytes_read;

                    if (bytes_read == 0) {
                        return error.EndOfStream;
                    }
                    self.field_start = 0;
                    return buffer[0];
                }
            } else {
                unreachable;
            }
        }

        /// !!!
        /// The memory that sliceIntoBuffer returns is only guaranteed to be valid until
        /// the next call of readChar which might rewrite the underlying buffers.
        /// !!!
        ///
        /// The primary buffer has the fields we read from the file, with field_start
        /// and field_end pointing to the start and end of the current field:
        ///
        /// primary:  [ | | | | | |f|f|f|f|f|f|f|f| | | | | ]
        ///                        ^             ^
        ///              field_start             field_end
        ///
        /// That is where we make the slice, which will be valid until the next call of readChar.
        ///
        /// slice:                [f|f|f|f|f|f|f|f]
        ///
        fn sliceIntoBuffer(self: *Self, was_quote: bool, field_len: usize) []const u8 {
            var buffer = &self.primary_buffer;
            const start = self.field_start;
            const end = start + field_len;
            self.field_start = end + 1;
            if (was_quote) {
                return buffer[(start + 1)..(end - 1)];
            } else {
                return buffer[start..end];
            }
        }

        /// The field slice is only valid until the next call of next
        pub fn next(self: *Self) TokenizeError!Token {
            switch (self.state) {
                .in_row => {},
                .row_end => {
                    self.state = .in_row;
                    return Token.row_end;
                },
                .eof => {
                    return Token.eof;
                },
            }
            // read a character. if we hit EOF, return Token.eof

            var field_len: usize = 0;
            var was_quote = false;
            var in_quote = false;
            while (true) {
                var byte: u8 = undefined;
                if (self.readChar(field_len)) |b| {
                    byte = b;
                } else |err| switch (err) {
                    error.EndOfStream => {
                        self.state = .eof;
                        return Token.eof;
                    },
                    else => return err, // this can't be EndOfStream
                }

                if (in_quote and byte != config.quote_delimiter) {
                    field_len += 1;
                    continue;
                }

                switch (byte) {
                    config.quote_delimiter => {
                        was_quote = true;
                        in_quote = !in_quote;
                        field_len += 1;
                    },
                    config.field_end_delimiter => {
                        // we have to grab every byte we read so far and return it
                        return Token{ .field = self.sliceIntoBuffer(was_quote, field_len) };
                    },
                    config.row_end_delimiter => {
                        const field_end = self.field_start + field_len;
                        if (self.field_start == field_end) {
                            self.field_start = self.field_start + 1;
                            return Token.row_end;
                        } else {
                            self.state = .row_end; // we owe the next call a row_end
                            return Token{ .field = self.sliceIntoBuffer(was_quote, field_len) };
                        }
                    },
                    else => field_len += 1,
                }
            }
        }
    };
}

const CsvFileTokenizer = CsvTokenizer(fs.File.Reader, .{});

fn testFile(file: fs.File, expected_token_rows: [][]u8) !void {
    const reader = file.reader();

    var tokenizer = CsvFileTokenizer{ .reader = reader };

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

test "tokenize from buffer" {
    const file = try fs.cwd().openFile("test/data/simple_tokenize.csv", .{});
    defer file.close();

    var buffer: [42]u8 = undefined;
    const bytes_read: usize = try file.readAll(&buffer);

    try std.testing.expect(bytes_read == 42);

    const BufferStream = std.io.FixedBufferStream([]u8);
    const CsvBufferTokenizer = CsvTokenizer(BufferStream.Reader, .{});

    var fixed_in_stream: BufferStream = std.io.fixedBufferStream(&buffer);
    const reader: BufferStream.Reader = fixed_in_stream.reader();

    const expected_token_rows = [5][3][]const u8{
        [_][]const u8{ "1", "2", "3" },
        [_][]const u8{ "4", "5", "6" },
        [_][]const u8{ "7", "", "9" },
        [_][]const u8{ "10", " , , ", "12" },
        [_][]const u8{ "13", "14", "" },
    };

    var tokenizer = CsvBufferTokenizer{ .reader = reader };

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

test "tokenize from file" {
    const file = try fs.cwd().openFile("test/data/simple_tokenize.csv", .{});
    defer file.close();

    const expected_token_rows = [5][3][]const u8{
        [_][]const u8{ "1", "2", "3" },
        [_][]const u8{ "4", "5", "6" },
        [_][]const u8{ "7", "", "9" },
        [_][]const u8{ "10", " , , ", "12" },
        [_][]const u8{ "13", "14", "" },
    };

    var tokenizer = CsvFileTokenizer{ .reader = file.reader() };

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

    const expected_token_rows = [4][5][]const u8{
        [_][]const u8{ "id", "name", "color", "unit", "nilable" },
        [_][]const u8{ "1", "ON", "red", "1.1", "111" },
        [_][]const u8{ "22", "OFF", "blue", "22.2", "" },
        [_][]const u8{ "333", "ON", "something else", "33.33", "3333" },
    };

    var tokenizer = CsvFileTokenizer{ .reader = file.reader() };

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
