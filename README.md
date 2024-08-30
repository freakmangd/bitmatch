# bitmatch
Simple zig library based off of the rust crate [bitmatch](https://github.com/porglezomp/bitmatch).
```zig
const match = bitmatch("00oo_aabb", 0b0011_1001) orelse return error.ExpectedNonNull;
try std.testing.expectEqual(0b11, match.o);
try std.testing.expectEqual(0b10, match.a);
try std.testing.expectEqual(0b01, match.b);
```

### Installing
```
zig fetch --save git+https://github.com/freakmangd/bitmatch
```
`build.zig`:
```zig
const bitmatch = b.dependency("bitmatch", .{});
exe.root_module.addImport("bitmatch", bitmatch.module("root"));
```

### Features

The main functions of the library are `bitmatch` and `bitmatchPacked`.

Both functions take a match string and a byte to match against. 
The match string must be comptime known.

`bitmatch` returns `?struct`. Each field is of type `u8`.

`bitmatchPacked` returns `?packed struct(u8)`. Each field is the smallest int type
required to hold all bits matched by the field's identifier.

```zig
// non-packed
const match = bitmatch("aaaa_b010", 0b1000_1010) orelse return error.ExpectedNonNull;
try std.testing.expect(@TypeOf(match.a) == u8);
try std.testing.expect(@TypeOf(match.b) == u8);
try std.testing.expectEqual(0b0000_1000, match.a);
try std.testing.expectEqual(0b0000_0001, match.b);

// packed
const match = bitmatchPacked("aaaa_b010", 0b1000_1010) orelse return error.ExpectedNonNull;
try std.testing.expect(@TypeOf(match.a) == u4);
try std.testing.expect(@TypeOf(match.b) == u1);
try std.testing.expectEqual(0b1000, match.a);
try std.testing.expectEqual(0b1, match.b);

// no identifiers
const match = bitmatch("0001_1010", 0b0001_1010) orelse return error.ExpectedNonNull;
try std.testing.expectEqual(0, @sizeOf(@TypeOf(match)));
```

#### Match bits

0s and 1s in the match string are the only characters that decide whether
a byte matches the pattern defined.

```zig
// This match returns null as were expecting the last bits to be 1011
// the match fails here -----------v
if (bitmatch("aaaa_1011", 0b1010_1001)) |_| return error.ExpectedNull;
```

#### Identifiers

An "identifier" refers to an alphabetic character inside the match string, they
are allowed to be in the range a-z and A-Z. An identifier captures the bits
that share their position. All identifiers will be fields of the return value.

There is a max of 8 identifiers per match string 
as this library assumes 8 bits in a byte.

```zig
const match = bitmatch("aaaa_bbbb", 0b0101_1010) orelse return error.ExpectedNonNull;
try std.testing.expectEqual(0b0101, match.a);
try std.testing.expectEqual(0b1010, match.b);

const match = bitmatch("abcd_efgh", 0b0101_1010) orelse return error.ExpectedNonNull;
try std.testing.expectEqual(0b0, match.a);
try std.testing.expectEqual(0b1, match.b);
try std.testing.expectEqual(0b0, match.c);
// ...
try std.testing.expectEqual(0b0, match.h);

// identifiers are case-sensitive
const match = bitmatch("aaaa_AAAA", 0b0000_1111) orelse return error.ExpectedNonNull;
try std.testing.expectEqual(0b0000, match.a);
try std.testing.expectEqual(0b1111, match.A);
```

Identifiers can be split as many times as is necessary, they will capture the bits
that share their position and concat them.
```zig
const match = bitmatch("aa_bb_aa_bb", 0b10_01_00_11);
try std.testing.expectEqual(0b10_00, match.a);
try std.testing.expectEqual(0b01_11, match.b);
```

#### Underscores
Underscores in match strings are ignored, and are more lenient than zig's integer literal underscores. You can have as many as you want for the purposes of increasing readability.

These match strings function the same: `"aaaabbbb"`, `"aaaa_bbbb"` `"a_a____aa_bb__b_b_"`

#### Wildcards
The `?` character is used as a wildcard, matching either a 0 or 1 without capturing it.
```rs
const match = bitmatch("???_aa_???", 0b010_01_101) orelse return error.ExpectedNonNull;
try std.testing.expectEqual(0b01, match.a);
```

If the match string is less than 8 characters, the match string is left-padded
with wildcards, making `"aa01"` equivalent to `"????aa01"`
```zig
const match = bitmatch("aa01", 0b0000_1101) orelse return error.ExpectedNonNull;
try std.testing.expectEqual(0b11, match.a);
```

### More Examples
See the bottom of `src/init.zig` for more testable examples. You can run them
with `zig build test`.
