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
zig fetch --save https://github.com/freakmangd/bitmatch/archive/[commit SHA].tar.gz
```
`build.zig`:
```zig
const bitmatch = b.dependency("bitmatch", .{});
exe.root_module.addImport("bitmatch", bitmatch.module("root"));
```
