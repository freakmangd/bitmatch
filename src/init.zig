const std = @import("std");

pub fn bitmatch(comptime fmt_: []const u8, byte: u8) ?Bitmatch(fmt_, .auto) {
    return bitmatchInner(fmt_, byte, .auto);
}

test bitmatch {
    try testBitmatches(bitmatch);
}

pub fn bitmatchPacked(comptime fmt_: []const u8, byte: u8) ?Bitmatch(fmt_, .@"packed") {
    return bitmatchInner(fmt_, byte, .@"packed");
}

test bitmatchPacked {
    try std.testing.expectEqual(8, @bitSizeOf(Bitmatch("abcd_efgh", .@"packed")));
    try testBitmatches(bitmatchPacked);
}

fn bitmatchInner(comptime fmt_: []const u8, byte: u8, comptime layout: std.builtin.Type.ContainerLayout) ?Bitmatch(fmt_, layout) {
    const fmt = comptime normalizeFmt(fmt_);

    comptime var shift: comptime_int = 7;
    inline while (shift >= 0) : (shift -= 1) {
        switch (fmt[7 - shift]) {
            '1' => if ((byte >> shift) & 1 == 0) return null,
            '0' => if ((byte >> shift) & 1 == 1) return null,
            else => {},
        }
    }

    var out: Bitmatch(fmt_, layout) = .{};
    const idents = comptime bitmatchIdentifiers(fmt);

    inline for (idents) |ident| inline for (ident.groups, 0..) |group, i| {
        if (i > 0) @field(out, &.{ident.name}) <<= group.len;
        @field(out, &.{ident.name}) |= @truncate((byte >> (8 - group.len - group.pos)) & comptime mask(group.len));
    };

    return out;
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

const BitmatchIdentifier = struct {
    name: u8,
    groups: []const struct {
        pos: u4,
        len: u4,
    },
};

// remove underscores and left pad with '?' (wildcard) if under 8 characters
fn normalizeFmt(comptime fmt: []const u8) []const u8 {
    var out: []const u8 = &.{};
    for (fmt) |c| {
        if (c != '_') out = out ++ [_]u8{c};
    }

    if (out.len > 8) {
        @compileError("Format has more than 8 significant characters, we can only match 8 bits");
    } else if (out.len < 8) {
        return (.{'?'} ** (8 - out.len)) ++ out;
    }

    return out;
}

fn bitmatchIdentifiers(comptime fmt_: []const u8) []const BitmatchIdentifier {
    const fmt = normalizeFmt(fmt_);
    var idents: std.BoundedArray(BitmatchIdentifier, 8) = .{};

    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        while (i < fmt.len) : (i += 1) switch (fmt[i]) {
            'a'...'z', 'A'...'Z' => break,
            '0', '1', '?' => continue,
            else => @compileError("Unexpected character in bitmatch: `" ++ [_]u8{fmt[i]} ++ "` identifiers must be within a-z or A-Z"),
        };
        if (i >= fmt.len) break;

        const char = fmt[i];
        const char_start = i;

        // seek to end of character group/end of line
        while (i < fmt.len) : (i += 1)
            if (char != fmt[i]) break;

        const ident: *BitmatchIdentifier = for (idents.slice()) |*ident| {
            if (ident.name == char) break ident;
        } else ident: {
            idents.append(.{
                .name = char,
                .groups = &.{},
            }) catch unreachable;
            break :ident &idents.buffer[idents.len - 1];
        };

        ident.groups = ident.groups ++ .{.{
            .pos = char_start,
            .len = i - char_start,
        }};

        i -|= 1;
    }

    return idents.constSlice();
}

fn Bitmatch(comptime fmt: []const u8, comptime layout: std.builtin.Type.ContainerLayout) type {
    const idents = comptime bitmatchIdentifiers(fmt);

    var fields: [idents.len]std.builtin.Type.StructField = undefined;
    for (&fields, idents) |*f, ident| {
        f.* = .{
            .name = &[_:0]u8{ident.name},
            .type = if (layout == .auto) u8 else std.meta.Int(.unsigned, size: {
                var size: u8 = 0;
                for (ident.groups) |group| size += group.len;
                break :size size;
            }),
            .alignment = 0,
            .is_comptime = false,
            .default_value = &@as(u8, 0),
        };
    }

    return @Type(.{ .Struct = std.builtin.Type.Struct{
        .decls = &.{},
        .layout = layout,
        .fields = if (layout == .auto) &fields else fields: {
            break :fields &(fields ++ .{.{
                .name = "_",
                .type = std.meta.Int(.unsigned, size: {
                    var size: u8 = 0;
                    for (idents) |ident| {
                        for (ident.groups) |group| size += group.len;
                    }
                    break :size 8 - size;
                }),
                .alignment = 0,
                .is_comptime = false,
                .default_value = &@as(u8, 0),
            }});
        },
        .is_tuple = false,
        .backing_integer = if (layout == .auto) null else u8,
    } });
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
        const match = bitmatch_impl("aba_cada", 0b101_0010) orelse return error.ExpectedNonNull;
        try std.testing.expectEqual(0b1100, match.a);
        try std.testing.expectEqual(0b0, match.b);
        try std.testing.expectEqual(0b0, match.c);
        try std.testing.expectEqual(0b1, match.d);
    }

    {
        const match = bitmatch_impl("cb00_110c", 0b1100_1100) orelse return error.ExpectedNonNull;
        try std.testing.expectEqual(0b1, match.b);
        try std.testing.expectEqual(0b10, match.c);
    }

    {
        const match = bitmatch_impl("aaaa_aaaa", 0b1100_1100) orelse return error.ExpectedNonNull;
        try std.testing.expectEqual(0b1100_1100, match.a);
    }

    {
        const match = bitmatch_impl("aaab_baab", 0b1001_1100) orelse return error.ExpectedNonNull;
        try std.testing.expectEqual(0b100_10, match.a);
        try std.testing.expectEqual(0b110, match.b);
    }

    {
        const match = bitmatch_impl("a?aa_?aaa", 0b1001_1100) orelse return error.ExpectedNonNull;
        try std.testing.expectEqual(0b101_100, match.a);
    }

    {
        _ = bitmatch_impl("1_1_0_0____1_0_0_1", 0b11001001) orelse return error.ExpectedNonNull;
        _ = bitmatch_impl("????_0000", 0b1010_0000) orelse return error.ExpectedNonNull;
        _ = bitmatch_impl("????_????", 0b0101_1010) orelse return error.ExpectedNonNull;
    }

    {
        if (bitmatch_impl("1", 0b0)) |_| return error.ExpectedNull;
        if (bitmatch_impl("1b00_11c0", 0b0000_0000)) |_| return error.ExpectedNull;
    }
}
