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

## API Reference

TODO: document errors

```zig
// Type declarations:

pub const CsvConfig = struct {
    field_end_delimiter: u8 = ',',
    row_end_delimiter: u8 = '\n',
    quote_delimiter: u8 = '"',
    skip_first_row: bool = true,
};

pub fn CsvSerializer(
    comptime T: type,
    comptime Writer: type,
    comptime config: cnf.CsvConfig,
) type {
    return struct {
        fn init(writer: Writer) CsvSerializer {}

        fn writeHeader() !void {}

        fn appendRow(data: T) !void {}
    }
}

pub fn CsvParser(
    comptime T: type,
    comptime Reader: type,
    comptime config: cnf.CsvConfig,
) type {
    return struct {
        fn init(
            allocator: std.mem.Allocator,
            reader: Reader,
        ) CsvSerializer {}


        // Returns the next row T or null if the iterator is done
        fn next() NextUserError!?T {}

        // Like new() but writes the struct into the provider pointer
        fn nextInto(struct_pointer: *T) NextUserError!?*T {}
    }
}

pub fn CsvSerializer(
    comptime T: type,
    comptime Writer: type,
    comptime config: cnf.CsvConfig,
) type {
    return struct {
        fn init(writer: Writer) CsvSerializer {}

        fn writeHeader() !void {}

        fn appendRow(data: T) !void {}
    }
}

// Usage:

const config: csv.CsvConfig = {
    .field_end_delimiter = ',',
    .row_end_delimiter = '\n',
    .quote_delimiter = '"',
    .skip_first_row = true,
};

const StructType = struct {
    int_field:   u32,
    float_field: f64,
    str_field:   []const u8,
    enum_field:  enum { red, blue, yellow },
    union_field: union { int_case: i32, float_case: f32 },
    bool_field:  bool,
    maybe_field: ?f64,
    void_field:  void,  // Use to skip parsing certain columns
}

var parser = csv.CsvParser(StructType, fs.File.Reader, config).init(reader);

var total: u32 = 0;
while (try parser.next()) |row| {
    // do something with the row
    if (std.mem.eql(u8, "important", row.str_field)) {
        total += row.int_field;
    }
}
 
var serializer = csv.CsvSerializer(StructType, config).init(writer);

try serializer.writeHeader();
try serializer.appendRow(StructType{ ... });
try serializer.appendRow(StructType{ ... });
// ...

```