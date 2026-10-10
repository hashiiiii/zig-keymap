const KeyPress = @import("../key.zig").KeyPress;

/// Adapts a libvaxis Key for Bindings.receive, preserving native text and Shift matching.
/// Pass the key_press payload from loop.nextEvent().
/// The adapter does not match physical keys through base_layout_codepoint.
pub fn libvaxisMatcher(key: anytype) Matcher(@TypeOf(key)) {
    return .{ .key = key };
}

fn Matcher(comptime NativeKey: type) type {
    return struct {
        key: NativeKey,

        pub fn matches(self: @This(), spec: KeyPress) bool {
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

test "libvaxisMatcher forwards named keys and every modifier" {
    // Dropping a modifier could invoke an action for a different key binding.
    const testing = @import("std").testing;
    const Key = @import("vaxis").Key;
    const matcher = libvaxisMatcher(Key{
        .codepoint = Key.enter,
        .mods = .{ .ctrl = true, .alt = true, .shift = true, .super = true, .meta = true, .hyper = true },
    });
    try testing.expect(matcher.matches(.{
        .key = .{ .named = .enter },
        .modifiers = .{ .ctrl = true, .alt = true, .shift = true, .super = true, .meta = true, .hyper = true },
    }));
    try testing.expect(!matcher.matches(.{ .key = .{ .named = .enter } }));
}

test "libvaxisMatcher preserves native text and shifted codepoint matching" {
    // Terminal protocols encode shifted characters differently.
    const testing = @import("std").testing;
    const Key = @import("vaxis").Key;
    try testing.expect(libvaxisMatcher(Key{ .codepoint = 'v', .mods = .{ .shift = true } }).matches(try KeyPress.parse("Shift+v")));
    try testing.expect(libvaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } }).matches(try KeyPress.parse(":")));
    try testing.expect(libvaxisMatcher(Key{ .codepoint = 'v', .shifted_codepoint = 'V', .mods = .{ .shift = true } }).matches(try KeyPress.parse("V")));
    try testing.expect(!libvaxisMatcher(Key{ .codepoint = 'v' }).matches(try KeyPress.parse("Shift+v")));
}
