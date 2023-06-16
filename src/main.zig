const std = @import("std");
const fs = std.fs;

const utils = @import("utils.zig");
const serialize = @import("serialize.zig");
const parse = @import("parse.zig");

const bench = @import("bench.zig");

pub fn main() anyerror!void {
    std.debug.print("Starting benchmark\n", .{});
    try bench.benchmark();
}

test "call all tests" {
    _ = @import("tokenize.zig");
    _ = @import("fast_tokenize.zig");
    _ = @import("parse.zig");
    _ = @import("serialize.zig");
    _ = @import("end_to_end_test.zig");
}
