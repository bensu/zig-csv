const std = @import("std");
const fs = std.fs;

pub fn eqlFileContents(from_file: fs.File, to_file: fs.File) !bool {
    // defer from_file.close();
    const from_reader = from_file.reader();

    var from_buffer: [1024]u8 = undefined;
    const from_bytes_read = try from_reader.read(&from_buffer);

    // defer to_file.close();
    const to_reader = to_file.reader();

    var to_buffer: [1024]u8 = undefined;
    const to_bytes_read = try to_reader.read(&to_buffer);

    if (from_bytes_read != to_bytes_read) {
        return false;
    }

    return std.mem.eql(u8, from_buffer[0..from_bytes_read], to_buffer[0..to_bytes_read]);
}
