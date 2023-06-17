# zig-csv

Parses CSV into zig structs, trying to balance speed with ergonomics.

## Quickstart

### Parse

Consider the following CSV file:

```csv
id,name,captured,color,health,
1,squirtle,false,blue,,
2,charmander,false,red,,
3,pikachu,true,yellow,10.0,
```

You can define a struct that describes the expected contents of the file and parses it:

```zig
const std = @import("std");
const fs = std.fs;

// Import csv
const csv = @import("csv.zig");

const Color = enum { red, blue, green, yellow };

// Define the type of CSV rows as a struct
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

    const config: csv.CsvConfig = .{};  // default config:

    const PokemonCsvParser = csv.CsvParser(fs.File.Reader, Pokemon, config);

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
```

### Serialize

Now, instead of parsing the file above, we are going to serialize it:

```zig
test "serializing pokemon" {
    var file = try fs.cwd().createFile("tmp/pokemon.csv", .{});
    defer file.close();
    const writer = file.writer();

    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const config: csv.CsvConfig = .{};
    const PokemonCsvSerializer = csv.CsvSerializer(Pokemon, config);
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
            .id = 1,
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
```

`tmp/pokemon.csv` should now have the same contents as the CSV above, header included.