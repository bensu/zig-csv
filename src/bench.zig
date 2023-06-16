const std = @import("std");
const fs = std.fs;

const parse = @import("parse.zig");

const NFL = struct {
    gameid: []const u8,
    qtr: i32,
    min: ?i32,
    sec: ?i32,
    off: []const u8,
    def: []const u8,
    down: ?i32,
    togo: ?i32,
    ydline: ?i32,
    description: []const u8,
    offscore: i32,
    defscore: i32,
    season: i32,
};

const Population = struct {
    country: []const u8,
    city: void,
    accent_city: void,
    region: []const u8,
    population: ?u64,
    latitude: void,
    longitude: void,
};

const MBTA = struct {
    trip_id: []const u8,
    arrival_time: []const u8,
    departure_time: []const u8,
    stop_id: []const u8,
    stop_sequence: i32,
    stop_headsign: []const u8,
    pickup_type: i32,
    drop_off_type: i32,
    timepoint: i32,
};

const Trade = struct {
    series: []const u8,
    period: []const u8,
    value: []const u8,
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
};

const IntId = struct {
    id: i64,
    age: []const u8,
};

pub fn countRows(comptime T: type, file_path: []const u8) anyerror!void {
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();

    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    var buffer: [4096 * 10]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    var parser = try parse.CsvParser(fs.File.Reader, T).init(allocator, file.reader(), .{});
    // var population: u64 = 0;
    var count: u64 = 0;
    while (try parser.next()) |_| {
        count = count + 1;
        fba.reset();
    }
    std.debug.print("Number rows: {}\n", .{count});
}

pub fn benchmarkWorldCities() anyerror!void {
    const file_path = "benchmark/data/worldcitiespop.csv";
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();

    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    var buffer: [4096 * 10]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    var parser = try parse.CsvParser(fs.File.Reader, Population).init(allocator, file.reader(), .{});
    var population: u64 = 0;
    while (try parser.next()) |row| {
        if (std.mem.eql(u8, "us", row.country) and std.mem.eql(u8, "MA", row.region)) {
            population += (row.population orelse 0);
        }
        fba.reset();
    }
    std.debug.print("Number of US-MA population: {}\n", .{population});
}

const Benchmarks = enum { NFL, Population, MBTA, Trades };

pub fn benchmark() !void {
    switch (Benchmarks.Population) {
        .NFL => try countRows(NFL, "benchmark/data/nfl.csv"),
        .Population => try benchmarkWorldCities(),
        .MBTA => try countRows(MBTA, "benchmark/data/mbta.csv"),
        .Trades => try countRows(Trade, "benchmark/data/trade-indexes.csv"),
    }
}
