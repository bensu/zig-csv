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

## Examples

### Parse from one file and serialize into another one

```zig
// Find the running example in src/end_to_end.zig

const T = struct { id: i64, age: u32 };

const from_path = "data/from_file.csv";
var from_file = try fs.cwd().openFile(from_path, .{});
defer from_file.close();
const reader = from_file.reader();

const to_path = "tmp/to_file.csv";
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

std.debug.print("Wrote {} rows", .{rows});
```

### Parse into a pre-allocated Array

```zig
const T = struct { id: i64, age: u32 };

const file_path = "test/data/simple_end_to_end.csv";
var file = try fs.cwd().openFile(file_path, .{});
defer file.close();
const reader = file.reader();

var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const arena_allocator = arena.allocator();

// if you know how many to rows to expect you can use an Array directly
const expected_rows = 17;
const array: []T = try arena_allocator.alloc(T, expected_rows);

var parser = try csv.CsvParser(T, fs.File.Reader, .{}).init(arena_allocator, reader);

var i: usize = 0;
while (i < expected_rows) {
    _ = try parser.nextInto(&array[i]);
    i += 1;
}
```

### Parse into a pre-allocated ArrayList

```zig
const T = struct { id: i64, age: u32 };

const file_path = "test/data/simple_end_to_end.csv";
var file = try fs.cwd().openFile(file_path, .{});
defer file.close();
const reader = file.reader();

var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const arena_allocator = arena.allocator();

// if you don't know how many rows to expect, you can use ArrayList
var list = std.ArrayList(T).init(allocator);
defer list.deinit();

var parser = try csv.CsvParser(T, fs.File.Reader, .{}).init(arena_allocator, reader);

while (try parser.next()) |row| {
    try list.append(row);
}
```

### Performance: skip fields and re-use strings

To improve performance, you can:

1. Assign `void` to the fields that you don't need and the parser will skip them.
2. Re-use the same memory for the strings of every row, provided you don't need to keep those strings after you processed them.

```zig
// 1. We mark void every field we don't need, maintaining their order

const NamelessPokemon = struct {
    id: void,
    name: []const u8,
    captured: bool,
    color: void,
    health: void,
};

var file = try fs.cwd().openFile("test/data/pokemon_example.csv", .{});
defer file.close();
const reader = file.reader();

// 2. We will keep the strings of one row at a time in this buffer
var buffer: [4096]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);

const PokemonCsvParser = csv.CsvParser(NamelessPokemon, fs.File.Reader, .{});

var parser = try PokemonCsvParser.init(fba.allocator(), reader);

var pikachus_captured: u32 = 0;
while (try parser.next()) |pokemon| {

    // 1. We only use pokemon.captured and pokemon.name, everything else is void
    if (pokemon.captured and std.mem.eql(u8, "pikachu", pokemon.name)) {
        pikachus_captured += 1;
    }

    // 2. We already used the allocated strings (pokemon.name) so we can reset 
    //    the memory. If we didn't, we would get an OutOfMemory error when the 
    //    FixedBufferAllocator runs out of memory
    fba.reset();
}

std.debug.print("You captured {} Pikachus", .{pikachus_captured});
```

### Parse and serialize directly from buffers

From `src/end_to_end_test.zig`:

```zig
test "buffer end to end" {
    const T = struct { id: u32, name: []const u8 };

    // parse
    const source = "id,name,\n1,none,";
    const n = source.len;

    var parsed_rows: [1]T = undefined;

    var buffer_stream = std.io.fixedBufferStream(source[0..n]);
    const reader = buffer_stream.reader();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var parser = try csv.CsvParser(T, @TypeOf(reader), .{}).init(arena_allocator, reader);

    var i: usize = 0;
    while (try parser.next()) |row| {
        parsed_rows[i] = row;
        i += 1;
    }

    // serialize
    var buffer: [n + 1]u8 = undefined;
    var fixed_buffer_stream = std.io.fixedBufferStream(buffer[0..]);
    const writer = fixed_buffer_stream.writer();

    var serializer = csv.CsvSerializer(T, @TypeOf(writer), .{}).init(writer);

    try serializer.writeHeader();
    for (parsed_rows) |row| {
        try serializer.appendRow(row);
    }

    try std.testing.expect(std.mem.eql(u8, source, buffer[0..n]));
}
```

# Informal benchmarks

In my M1, this library can run the following code over a 150Mb CSV file in 0.33 seconds:

```zig
// from src/bench.zig

const Population = struct {
    country: []const u8,
    city: void,
    accent_city: void,
    region: []const u8,
    population: ?u64,
    latitude: void,
    longitude: void,
};

const file_path = "benchmark/data/worldcitiespop.csv";
var file = try fs.cwd().openFile(file_path, .{});
defer file.close();

var buffer: [4096 * 10]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
const allocator = fba.allocator();

var parser = try csv.CsvParser(Population, fs.File.Reader, .{}).init(allocator, file.reader());
var population: u64 = 0;
while (try parser.next()) |row| {
    if (std.mem.eql(u8, "us", row.country) and std.mem.eql(u8, "MA", row.region)) {
        population += (row.population orelse 0);
    }
    fba.reset();
}
std.debug.print("Number of US-MA population: {}\n", .{population});
```

Notice that it is only reading two strings and an int from each row.

You can replicate in your computer with:

```sh
$ zig build -Drelease-fast=true
$ time zig-out/bin/csv

Starting benchmark
Number of US-MA population: 5988064

real 0.33
user 0.30
sys 0.03
```

To parse the entire file, we change the type being parsed:

```diff
+ const FullPopulation = struct {
+     country: []const u8,
+     city: []const u8,
+     accent_city: []const u8,
+     region: []const u8,
+     population: ?u32,
+     latitude: f64,
+     longitude: f64,
+ };

-    var parser = try csv.CsvParser(Population, fs.File.Reader, .{}).init(allocator, file.reader());
+    var parser = try csv.CsvParser(FullPopulation, fs.File.Reader, .{}).init(allocator, file.reader());
```

```sh
$ zig build -Drelease-fast=true
$ time zig-out/bin/csv

Starting benchmark
Number of US-MA population: 5988064

real 0.54
user 0.40
sys 0.03
```