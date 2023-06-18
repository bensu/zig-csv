const std = @import("std");
const fs = std.fs;

const parse = @import("parse.zig");
const serialize = @import("serialize.zig");

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

const FullPopulation = struct {
    country: []const u8,
    city: []const u8,
    accent_city: []const u8,
    region: []const u8,
    population: ?u32,
    latitude: f64,
    longitude: f64,
};

const Population = struct {
    country: []const u8,
    city: void,
    accent_city: void,
    region: []const u8,
    population: ?u32,
    latitude: void,
    longitude: void,
};

const OnlyPopulation = struct {
    country: void,
    city: void,
    accent_city: void,
    region: void,
    population: ?u32,
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

    const start_ms = std.time.milliTimestamp();

    const Parser = parse.CsvParser(T, fs.File.Reader, .{});
    var parser = try Parser.init(allocator, file.reader());
    var count: u64 = 0;
    while (try parser.next()) |_| {
        count = count + 1;
        fba.reset();
    }
    const end_ms = std.time.milliTimestamp();

    const ms_duration = end_ms - start_ms;

    std.debug.print("Parsed {} rows in {}ms -- {s}\n", .{ count, ms_duration, @typeName(T) });
}

pub fn benchmarkWorldCities() anyerror!void {
    const file_path = "benchmark/data/worldcitiespop.csv";
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();

    var buffer: [4096 * 10]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const start_ms = std.time.milliTimestamp();

    const PopulationParser = parse.CsvParser(Population, fs.File.Reader, .{});
    var parser = try PopulationParser.init(allocator, file.reader());
    var population: u32 = 0;
    while (try parser.next()) |row| {
        if (std.mem.eql(u8, "us", row.country) and std.mem.eql(u8, "MA", row.region)) {
            population += (row.population orelse 0);
        }
        fba.reset();
    }
    const end_ms = std.time.milliTimestamp();

    const ms_duration = end_ms - start_ms;

    std.debug.print("Number of US-MA population: {} in {} ms\n", .{ population, ms_duration });
}

pub fn benchmarkCountAllPopulation(print: bool) anyerror!i64 {
    const file_path = "benchmark/data/worldcitiespop.csv";
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();

    var buffer: [4096 * 10]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const start_ms = std.time.milliTimestamp();

    const OnlyPopulationParser = parse.CsvParser(OnlyPopulation, fs.File.Reader, .{});

    var parser = try OnlyPopulationParser.init(allocator, file.reader());
    var population: u32 = 0;
    while (try parser.next()) |row| {
        population += (row.population orelse 0);
        fba.reset();
    }
    const end_ms = std.time.milliTimestamp();

    const ms_duration = end_ms - start_ms;

    if (print) {
        std.debug.print("Total population: {} in {} ms\n", .{ population, ms_duration });
    }
    return ms_duration;
}

const Benchmarks = enum { NFL, FullPopulation, VoidPopulation, MBTA, Trades, CountPopulation, CountAllPopulation };

pub fn benchmark() !void {
    if (false) {
        for (std.enums.values(Benchmarks)) |e| {
            switch (e) {
                .NFL => try countRows(NFL, "benchmark/data/nfl.csv"),
                .CountPopulation => try benchmarkWorldCities(),
                .CountAllPopulation => try benchmarkCountAllPopulation(true),
                .FullPopulation => try countRows(FullPopulation, "benchmark/data/worldcitiespop.csv"),
                .VoidPopulation => try countRows(Population, "benchmark/data/worldcitiespop.csv"),
                .MBTA => try countRows(MBTA, "benchmark/data/mbta.csv"),
                .Trades => try countRows(Trade, "benchmark/data/trade-indexes.csv"),
            }
        }
    } else {
        const loops = 10;
        var ms: i64 = 0;
        var i: u32 = 0;
        while (i < loops) {
            ms += try benchmarkCountAllPopulation(true);
            i += 1;
        }
        std.debug.print("Average time: {} ms\n", .{@divTrunc(ms, loops)});
    }
}
