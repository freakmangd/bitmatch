const std = @import("std");

pub fn bitmatch(comptime fmt_: []const u8, byte: u8) ?Bitmatch(fmt_) {
    const fmt = comptime normalizeFmt(fmt_);
    const idents = comptime bitmatchIdentifiers(fmt);

    var out: Bitmatch(fmt) = undefined;

    comptime var ident_i: usize = 0;
    comptime var shift: u3 = 7;
    inline while (true) : (shift -= 1) {
        switch (fmt[7 - shift]) {
            '1' => if ((byte >> shift) & 1 == 0) return null,
            '0' => if ((byte >> shift) & 1 == 1) return null,
            '?' => continue,
            else => if (idents.len > 0) {
                shift -= @intCast(idents[ident_i].len - 1);
                @field(out, &.{idents[ident_i].name}) = (byte >> shift) & comptime mask(idents[ident_i].len);
                ident_i += 1;
            },
        }

        if (shift == 0) break;
    }

    return out;
}

test bitmatch {
    try testBitmatches(bitmatch);
}

fn mask(bit_count: u8) u8 {
    var out: u8 = 0;
    for (0..bit_count) |_| {
        out <<= 1;
        out |= 1;
    }
    return out;
}

test mask {
    try std.testing.expectEqual(0b11, comptime mask(2));
}

pub fn bitmatchPacked(comptime fmt_: []const u8, byte: u8) ?BitmatchPacked(fmt_) {
    const fmt = comptime normalizeFmt(fmt_);

    comptime var shift: u3 = 7;
    inline while (true) : (shift -= 1) {
        switch (fmt[7 - shift]) {
            '1' => if ((byte >> shift) & 1 == 0) return null,
            '0' => if ((byte >> shift) & 1 == 1) return null,
            else => {},
        }
        if (shift == 0) break;
    }

    return @bitCast(byte);
}

test bitmatchPacked {
    try testBitmatches(bitmatchPacked);
}

fn testBitmatches(comptime bitmatch_impl: anytype) !void {
    {
        const match = bitmatch_impl("00oo_aabb", 0b0011_1001) orelse return error.ExpectedNonNull;
        try std.testing.expectEqual(0b11, match.o);
        try std.testing.expectEqual(0b10, match.a);
        try std.testing.expectEqual(0b01, match.b);
    }

    {
        const match = bitmatch_impl("01oo_ooaa", 0b0111_1001) orelse return error.ExpectedNonNull;
        try std.testing.expectEqual(0b1110, match.o);
        try std.testing.expectEqual(0b01, match.a);
    }

    {
        const match = bitmatch_impl("a0bb", 0b1001) orelse return error.ExpectedNonNull;
        try std.testing.expectEqual(0b1, match.a);
        try std.testing.expectEqual(0b01, match.b);
    }

    {
        const match = bitmatch_impl("abcd", 0b1001) orelse return error.ExpectedNonNull;
        try std.testing.expectEqual(0b1, match.a);
        try std.testing.expectEqual(0b0, match.b);
        try std.testing.expectEqual(0b0, match.c);
        try std.testing.expectEqual(0b1, match.d);
    }

    {
        const match = bitmatch_impl("1b00_11c0", 0b1100_1100) orelse return error.ExpectedNonNull;
        try std.testing.expectEqual(0b1, match.b);
        try std.testing.expectEqual(0b0, match.c);
    }

    {
        _ = bitmatch_impl("1_1_0_0____1_0_0_1", 0b11001001) orelse return error.ExpectedNonNull;
    }

    {
        if (bitmatch_impl("1", 0b0)) |_| return error.ExpectedNull;
        if (bitmatch_impl("1b00_11c0", 0b0000_0000)) |_| return error.ExpectedNull;
    }
}

const BitmatchIdentifier = struct {
    name: u8,
    pos: u8,
    len: u8,
};

// remove underscores and left pad with '0' if under 8 characters
fn normalizeFmt(comptime fmt: []const u8) []const u8 {
    var out: []const u8 = &.{};
    for (fmt) |c| {
        if (c != '_') out = out ++ [_]u8{c};
    }

    if (out.len > 8) {
        @compileError("Format has more than 8 significant characters, we can only match 8 bits");
    } else if (out.len < 8) {
        return (.{'0'} ** (8 - out.len)) ++ out;
    }
    return out;
}

fn bitmatchIdentifiers(comptime fmt_: []const u8) []const BitmatchIdentifier {
    const fmt = normalizeFmt(fmt_);
    var idents: []const BitmatchIdentifier = &.{};

    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        while (i < fmt.len) : (i += 1) switch (fmt[i]) {
            'a'...'z', 'A'...'Z' => break,
            '0', '1' => continue,
            else => @compileError("Unexpected character in bitmatch: `" ++ [_]u8{fmt[i]} ++ "`"),
        };
        if (i >= fmt.len) break;

        const char = fmt[i];
        const char_start = i;
        for (idents) |ident| {
            if (ident.name == char) @compileError("Repeat identifier in bitmatch: `" ++ [_]u8{ident} ++ "`");
        }

        // seek to end of character group/end of line
        while (i < fmt.len) : (i += 1)
            if (char != fmt[i]) break;

        idents = idents ++ .{.{
            .name = char,
            .pos = char_start,
            .len = i - char_start,
        }};

        i -|= 1;
    }

    return idents;
}

fn Bitmatch(comptime fmt: []const u8) type {
    const idents = comptime bitmatchIdentifiers(fmt);

    var fields: [idents.len]std.builtin.Type.StructField = undefined;
    for (&fields, idents) |*f, ident| {
        f.* = .{
            .name = &[_:0]u8{ident.name},
            .type = u8,
            //.type = std.meta.Int(.unsigned, ident.len),
            .alignment = 0,
            .is_comptime = false,
            .default_value = null,
        };
    }

    return @Type(.{ .Struct = .{
        .decls = &.{},
        .layout = .auto,
        .fields = &fields,
        .is_tuple = false,
    } });
}

fn BitmatchPacked(comptime fmt_: []const u8) type {
    const fmt = normalizeFmt(fmt_);
    const idents = comptime bitmatchIdentifiers(fmt);

    var fields: []const std.builtin.Type.StructField = &.{};

    var filler_count: u8 = 0;
    var filler_len: u8 = 0;

    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        const char = fmt[i];

        switch (char) {
            '_' => continue,
            '0', '1', '?' => {
                filler_len += 1;
                continue;
            },
            else => {
                if (filler_len > 0) {
                    fields = .{.{
                        .name = std.fmt.comptimePrint("_{}", .{filler_count}),
                        .type = std.meta.Int(.unsigned, filler_len),
                        .alignment = 0,
                        .is_comptime = false,
                        .default_value = null,
                    }} ++ fields;
                    filler_len = 0;
                    filler_count += 1;
                }

                const ident = for (idents) |id| {
                    if (id.name == char) break id;
                } else unreachable;

                fields = .{.{
                    .name = &[_:0]u8{ident.name},
                    .type = std.meta.Int(.unsigned, ident.len),
                    .alignment = 0,
                    .is_comptime = false,
                    .default_value = null,
                }} ++ fields;

                i += ident.len - 1;
            },
        }
    }

    if (filler_len > 0) {
        fields = .{.{
            .name = std.fmt.comptimePrint("_{}", .{filler_count}),
            .type = std.meta.Int(.unsigned, filler_len),
            .alignment = 0,
            .is_comptime = false,
            .default_value = null,
        }} ++ fields;
    }

    return @Type(.{ .Struct = std.builtin.Type.Struct{
        .decls = &.{},
        .layout = .@"packed",
        .fields = fields,
        .backing_integer = u8,
        .is_tuple = false,
    } });
}

test BitmatchPacked {
    comptime {
        {
            const B = BitmatchPacked("01xx_xa0c");
            const ti = @typeInfo(B).Struct;

            expectEqualCt(u2, ti.fields[4].type);
            expectEqualCt(u3, ti.fields[3].type);
            expectEqualCt(u1, ti.fields[2].type);
            expectEqualCt(u1, ti.fields[1].type);
            expectEqualCt(u1, ti.fields[0].type);
        }

        {
            const B = BitmatchPacked("00oo_aabb");
            const ti = @typeInfo(B).Struct;

            expectEqualCt(u2, ti.fields[3].type);
            expectEqualCt(u2, ti.fields[2].type);
            expectEqualCt(u2, ti.fields[1].type);
            expectEqualCt(u2, ti.fields[0].type);
        }
    }
}

fn expectEqualCt(comptime expected: anytype, comptime actual: anytype) void {
    if (expected != actual) @compileError(std.fmt.comptimePrint("Expected {}, found {}", .{ expected, actual }));
}
