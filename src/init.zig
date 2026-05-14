const std = @import("std");

/// Match `byte` against `fmt`. The returned struct will either be null,
/// meaning the 0s and 1s of `fmt` didnt match `byte`, or have each identifier
/// inside `fmt` as a field of type `u8`.
pub fn bitmatch(comptime fmt: []const u8, byte: u8) ?Bitmatch(fmt, .auto) {
    return bitmatchInner(fmt, byte, .auto);
}

test bitmatch {
    const match = bitmatch("aaaa_b010", 0b1000_1010) orelse return error.ExpectedNonNull;
    try std.testing.expect(@TypeOf(match.a) == u8);
    try std.testing.expect(@TypeOf(match.b) == u8);
    try std.testing.expectEqual(0b0000_1000, match.a);
    try std.testing.expectEqual(0b0000_0001, match.b);

    try testBitmatches(bitmatch);
}

/// Match `byte` against `fmt`. The returned packed struct will either be null,
/// meaning the 0s and 1s of `fmt` didnt match `byte`, or have each identifier
/// inside `fmt` as a field with the smallest int type necessary to store it.
pub fn bitmatchPacked(comptime fmt: []const u8, byte: u8) ?Bitmatch(fmt, .@"packed") {
    return bitmatchInner(fmt, byte, .@"packed");
}

test bitmatchPacked {
    const match = bitmatchPacked("aaaa_b010", 0b1000_1010) orelse return error.ExpectedNonNull;
    try std.testing.expect(@TypeOf(match.a) == u4);
    try std.testing.expect(@TypeOf(match.b) == u1);
    try std.testing.expectEqual(0b1000, match.a);
    try std.testing.expectEqual(0b1, match.b);

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
    groups: []const Group,

    const Group = struct {
        pos: u4,
        len: u4,
    };
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

    var idents_buf: [8]BitmatchIdentifier = undefined;
    var idents_len: usize = 0;

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

        const ident: *BitmatchIdentifier = for (idents_buf[0..idents_len]) |*ident| {
            if (ident.name == char) break ident;
        } else ident: {
            idents_buf[idents_len] = .{
                .name = char,
                .groups = &.{},
            };
            defer idents_len += 1;
            break :ident &idents_buf[idents_len];
        };

        ident.groups = ident.groups ++ [1]BitmatchIdentifier.Group{.{
            .pos = char_start,
            .len = i - char_start,
        }};

        i -|= 1;
    }

    return idents_buf[0..idents_len];
}

fn Bitmatch(comptime fmt: []const u8, comptime layout: std.builtin.Type.ContainerLayout) type {
    const idents = comptime bitmatchIdentifiers(fmt);

    var total_size: usize = 0;
    var field_names: [idents.len][]const u8 = undefined;
    var field_types: [idents.len]type = undefined;

    for (&field_names, &field_types, idents) |*name, *F, ident| {
        name.* = &[_:0]u8{ident.name};
        F.* = if (layout == .auto) u8 else @Int(.unsigned, size: {
            var size: u8 = 0;
            for (ident.groups) |group| size += group.len;
            total_size += size;
            break :size size;
        });
    }

    return @Struct(layout, if (layout == .auto) null else @Int(.unsigned, total_size), &field_names, &field_types, &@splat(.{ .default_value_ptr = &@as(u8, 0) }));
}

fn testBitmatches(comptime bitmatch_impl: anytype) !void {
    {
        const match = bitmatch("0001_1010", 0b0001_1010) orelse return error.ExpectedNonNull;
        try std.testing.expectEqual(0, @sizeOf(@TypeOf(match)));
    }

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
