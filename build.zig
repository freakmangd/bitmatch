const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root = b.addModule("root", .{
        .root_source_file = b.path("src/init.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/init.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const perf_test = b.addExecutable(.{
        .name = "Performance test",
        .root_source_file = b.path("src/performance_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    perf_test.root_module.addImport("bitmatch", root);

    const run_perf_test = b.addRunArtifact(perf_test);

    const perf_step = b.step("perf", "Run performance tests");
    perf_step.dependOn(&run_perf_test.step);
}
