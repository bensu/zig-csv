const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("csv", .{
        .source_file = .{ .path = "src/csv.zig" },
    });

    try b.modules.put(b.dupe("csv"), module);

    const exe = b.addExecutable(.{
        .name = "csv",
        .root_source_file = .{ .path = "src/csv/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    if (b.args) |args| {
        run_exe.addArgs(args);
    }
    run_step.dependOn(&run_exe.step);

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/csv/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
