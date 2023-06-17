const std = @import("std");
const fs = std.fs;
const csv = @import("csv.zig");

const utils = @import("utils.zig");

const Simple = struct {
    id: []const u8,
    age: []const u8,
};

fn copyCsv(comptime T: type, from_path: []const u8, to_path: []const u8) !usize {
    var from_file = try fs.cwd().openFile(from_path, .{});
    defer from_file.close();
    const reader = from_file.reader();

    var to_file = try fs.cwd().createFile(to_path, .{});
    defer to_file.close();
    const writer = to_file.writer();

    const allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = try csv.CsvParser(T, fs.File.Reader, .{}).init(arena.allocator(), reader);

    var serializer = csv.CsvSerializer(T, fs.File.Writer, .{}).init(writer);

    var rows: usize = 0;
    try serializer.writeHeader();
    while (try parser.next()) |row| {
        rows = rows + 1;
        try serializer.appendRow(row);
    }

    return rows;
}

test "end to end" {
    const from_path = "test/data/simple_end_to_end.csv";
    const to_path = "tmp/simple_end_to_end.csv";

    var from_file = try fs.cwd().openFile(from_path, .{});
    defer from_file.close();

    var to_file = try fs.cwd().openFile(to_path, .{});
    defer to_file.close();

    const rows = try copyCsv(Simple, from_path, to_path);

    const expected_rows: usize = 17;
    try std.testing.expectEqual(expected_rows, rows);

    try std.testing.expect(try utils.eqlFileContents(from_file, to_file));
}

const Color = enum { red, blue, green, yellow };

const Pokemon = struct {
    id: u32,
    name: []const u8,
    captured: bool,
    color: Color,
    health: ?f32,
};

test "parsing pokemon" {
    var file = try fs.cwd().openFile("test/data/pokemon_example.csv", .{});
    defer file.close();
    const reader = file.reader();

    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const config: csv.CsvConfig = .{};
    const PokemonCsvParser = csv.CsvParser(Pokemon, fs.File.Reader, config);

    var parser = try PokemonCsvParser.init(arena.allocator(), reader);

    var number_captured: u32 = 0;
    while (try parser.next()) |pokemon| {
        if (pokemon.captured) {
            number_captured += 1;
        }
    }
    try std.testing.expectEqual(number_captured, 1);
    std.debug.print("You have captured {} Pokemons", .{number_captured});
}

test "serializing pokemon" {
    var file = try fs.cwd().createFile("tmp/pokemon.csv", .{});
    defer file.close();
    const writer = file.writer();

    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const config: csv.CsvConfig = .{};
    const PokemonCsvSerializer = csv.CsvSerializer(Pokemon, fs.File.Writer, config);
    var serializer = PokemonCsvSerializer.init(writer);

    const pokemons = [3]Pokemon{
        Pokemon{
            .id = 1,
            .name = "squirtle",
            .captured = false,
            .color = Color.blue,
            .health = null,
        },
        Pokemon{
            .id = 2,
            .name = "charmander",
            .captured = false,
            .color = Color.red,
            .health = null,
        },
        Pokemon{
            .id = 3,
            .name = "pikachu",
            .captured = true,
            .color = Color.yellow,
            .health = 10.0,
        },
    };

    try serializer.writeHeader();

    for (pokemons) |pokemon| {
        try serializer.appendRow(pokemon);
    }
}
