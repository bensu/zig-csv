const std = @import("std");
const fs = std.fs;
const Type = std.builtin.Type;
const ascii = std.ascii;

// Utils

fn serializeAtomic(comptime T: type, writer: fs.File.Writer, value: T) !void {
    switch (T) {
        i8, i16, i32, i64, i128, u8, u16, u32, u64, u128 => {
            var buffer: [20]u8 = undefined;
            const buffer_slice = buffer[0..];
            const bytes_written = try std.fmt.bufPrint(buffer_slice, "{}", .{value});
            _ = try writer.write(bytes_written);
        },
        f32, f64 => {
            var buffer: [20]u8 = undefined;
            const buffer_slice = buffer[0..];
            // TODO: how floating point is printed should be configurable
            const bytes_written = try std.fmt.bufPrint(buffer_slice, "{e}", .{value});
            _ = try writer.write(bytes_written);
        },
        else => @compileError("Unsupported type"),
    }
}

// 1. What is the API

// var writer = new StreamWriter("file.csv");
// var csv_serializer = CsvSerializer(DynStruct).init(csv_config, writer);
// const data: DynStruct = undefined;
// csv_serializer.appendRow(data);

pub const CsvConfig = struct {
    skip_first_row: bool = true,
};

pub fn CsvSerializer(
    comptime T: type,
) type {
    return struct {
        const Self = @This();

        const Fields: []const Type.StructField = switch (@typeInfo(T)) {
            .Struct => |S| S.fields,
            else => @compileError("T needs to be a struct"),
        };

        const NumberOfFields: usize = Fields.len;

        writer: fs.File.Writer,
        config: CsvConfig,

        pub fn init(config: CsvConfig, writer: fs.File.Writer) Self {
            return Self{
                .writer = writer,
                .config = config,
            };
        }

        pub fn writeHeader(self: *Self) !void {
            inline for (Fields) |Field| {
                try self.writer.writeAll(Field.name);
                try self.writer.writeByte(',');
            }
            try self.writer.writeByte('\n');
        }

        pub fn appendRow(self: *Self, data: T) !void {
            inline for (Fields) |Field| {
                const FieldType = Field.field_type;
                const field_val: FieldType = @field(data, Field.name);
                if (comptime FieldType == []const u8) {
                    if (field_val.len != 0) {
                        try self.writer.writeAll(field_val);
                    }
                } else {
                    const FieldInfo = @typeInfo(FieldType);
                    switch (FieldInfo) {
                        .Optional => {
                            const NestedFieldType: type = FieldInfo.Optional.child;
                            if (field_val) |v| {
                                try serializeAtomic(NestedFieldType, self.writer, v);
                            }
                        },
                        else => {
                            try serializeAtomic(FieldType, self.writer, field_val);
                        },
                    }
                }
                try self.writer.writeByte(',');
            }
            try self.writer.writeByte('\n');
        }
    };
}
