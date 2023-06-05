const std = @import("std");

fn isUnsignedIntType(comptime T: type) bool {
    comptime switch (T) {
        u8 => return true,
        u16 => return true,
        u32 => return true,
        u64 => return true,
        else => return false,
    };
}

fn isSignedIntType(comptime T: type) bool {
    comptime switch (T) {
        i8 => return true,
        i16 => return true,
        i32 => return true,
        i64 => return true,
        else => return false,
    };
}

fn isIntType(comptime T: type) bool {
    return comptime isUnsignedIntType(T) or isSignedIntType(T);
}

fn isFloatType(comptime T: type) bool {
    comptime switch (T) {
        f32 => return true,
        f64 => return true,
        else => return false,
    };
}

fn parseInt(comptime T: type, input_string: []const u8) ?T {
    if (comptime !isIntType(T)) {
        @compileError(@typeName(T) ++ " needs to be an integer type like u32 or i64");
    }

    const out = std.fmt.parseInt(T, input_string, 0) catch {
        return null;
    };
    return out;
}

fn parseFloat(comptime T: type, input_string: []const u8) ?T {
    if (comptime !isFloatType(T)) {
        @compileError(@typeName(T) ++ " needs to be a float like f32 or f64");
    }

    const out = std.fmt.parseFloat(T, input_string) catch |err| {
        std.debug.print("Error while parsing int {}\n", .{err});
        std.debug.print("DATA: {s}\n", .{input_string});
        return null;
    };
    return out;
}

pub inline fn parseAtomic(comptime T: type, comptime field_name: []const u8, input_val: []const u8) !T {
    switch (@typeInfo(T)) {
        .Int => {
            if (parseInt(T, input_val)) |p| {
                return p;
            } else {
                return error.BadInput;
            }
        },
        .Float => {
            if (parseFloat(T, input_val)) |p| {
                return p;
            } else {
                return error.BadInput;
            }
        },
        else => {
            @compileError("Unsupported type " ++ @typeName(T) ++ " for field " ++ field_name);
        },
    }
}
