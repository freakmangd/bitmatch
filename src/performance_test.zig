const std = @import("std");
const bm = @import("bitmatch");
const keep = std.mem.doNotOptimizeAway;

const runs = 500_000;

pub fn main() !void {
    var timer = try std.time.Timer.start();

    time(bm.bitmatch);
    const time_normal = timer.lap();

    time(bm.bitmatchPacked);
    const time_packed = timer.lap();

    const writer = std.io.getStdOut().writer();
    try writer.print("Bitmatch normal: {}ns\n", .{time_normal / runs});
    try writer.print("Bitmatch packed: {}ns\n", .{time_packed / runs});
}

fn time(comptime impl: anytype) void {
    for (0..runs) |_| {
        var res = impl("abc0_1def", 0b1010_1010) orelse @panic("bad");
        std.mem.doNotOptimizeAway(&res);
        res.a = res.b +% res.c +% res.d -% res.e -% res.f;
        res.b = res.c +% res.d +% res.e -% res.f -% res.a;
        res.c = res.d +% res.e +% res.f -% res.a -% res.b;
        res.d = res.e +% res.f +% res.a -% res.b -% res.c;
        res.e = res.f +% res.a +% res.b -% res.c -% res.d;
    }
}
