const std = @import("std");
const bm = @import("bitmatch");
const keep = std.mem.doNotOptimizeAway;

const runs = 500_000;

pub fn main(init: std.process.Init) !void {
    var timer: std.Io.Timestamp = .now(init.io, .real);
    time(bm.bitmatch);
    const time_normal = timer.untilNow(init.io, .real);

    timer = .now(init.io, .real);
    time(bm.bitmatchPacked);
    const time_packed = timer.untilNow(init.io, .real);

    var writer = std.Io.File.stdout().writer(init.io, &.{});
    try writer.interface.print("Bitmatch normal: {}ns\n", .{@divFloor(time_normal.toNanoseconds(), runs)});
    try writer.interface.print("Bitmatch packed: {}ns\n", .{@divFloor(time_packed.toNanoseconds(), runs)});
}

fn time(comptime impl: anytype) void {
    for (0..runs) |_| {
        var res = impl("abc0_1def", 0b1010_1010) orelse @panic("bad");
        std.mem.doNotOptimizeAway(&res);
    }
}
