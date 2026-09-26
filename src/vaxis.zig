const KeySpec = @import("key.zig").KeySpec;

/// Adapts a libvaxis key event for `Keymap.resolve`, preserving native key matching.
pub fn vaxisMatcher(key: anytype) Matcher(@TypeOf(key)) {
    return .{ .key = key };
}

fn Matcher(comptime NativeKey: type) type {
    return struct {
        key: NativeKey,

        pub fn matches(self: @This(), spec: KeySpec) bool {
            const codepoint = switch (spec.key) {
                .character => |cp| cp,
                .named => |named| switch (named) {
                    inline else => |tag| @field(NativeKey, @tagName(tag)),
                },
            };
            return self.key.matches(codepoint, .{
                .shift = spec.modifiers.shift,
                .ctrl = spec.modifiers.ctrl,
                .alt = spec.modifiers.alt,
                .super = spec.modifiers.super,
                .meta = spec.modifiers.meta,
                .hyper = spec.modifiers.hyper,
            });
        }
    };
}

test "vaxisMatcher forwards named keys and every modifier" {
    // Dropping a modifier could invoke an action for a different shortcut.
    const testing = @import("std").testing;
    const Key = @import("vaxis").Key;
    const matcher = vaxisMatcher(Key{
        .codepoint = Key.enter,
        .mods = .{ .ctrl = true, .alt = true, .shift = true, .super = true, .meta = true, .hyper = true },
    });
    try testing.expect(matcher.matches(.{
        .key = .{ .named = .enter },
        .modifiers = .{ .ctrl = true, .alt = true, .shift = true, .super = true, .meta = true, .hyper = true },
    }));
    try testing.expect(!matcher.matches(.{ .key = .{ .named = .enter } }));
}

test "vaxisMatcher preserves native text and shifted codepoint matching" {
    // Terminal protocols encode shifted characters differently.
    const testing = @import("std").testing;
    const Key = @import("vaxis").Key;
    try testing.expect(vaxisMatcher(Key{ .codepoint = 'v', .mods = .{ .shift = true } }).matches(try KeySpec.parse("Shift+v")));
    try testing.expect(vaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } }).matches(try KeySpec.parse(":")));
    try testing.expect(vaxisMatcher(Key{ .codepoint = 'v', .shifted_codepoint = 'V', .mods = .{ .shift = true } }).matches(try KeySpec.parse("V")));
    try testing.expect(!vaxisMatcher(Key{ .codepoint = 'v' }).matches(try KeySpec.parse("Shift+v")));
}
