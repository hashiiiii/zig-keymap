const Keyboard = @import("key.zig").Keyboard;

/// Adapts a libvaxis key event for `Keymap.resolve`.
/// Uses libvaxis matching for characters, named keys, and modifiers.
pub fn vaxisMatcher(key: anytype) Matcher(@TypeOf(key)) {
    return .{ .key = key };
}

/// A matcher that uses the terminal library's key type.
fn Matcher(comptime NativeKey: type) type {
    return struct {
        /// The incoming key event to compare with configured conditions.
        key: NativeKey,

        /// Returns whether the incoming event matches `spec`, using libvaxis key matching.
        pub fn matches(self: @This(), spec: Keyboard) bool {
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
    try testing.expect(vaxisMatcher(Key{ .codepoint = 'v', .mods = .{ .shift = true } }).matches(try Keyboard.parse("Shift+v")));
    try testing.expect(vaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } }).matches(try Keyboard.parse(":")));
    try testing.expect(vaxisMatcher(Key{ .codepoint = 'v', .shifted_codepoint = 'V', .mods = .{ .shift = true } }).matches(try Keyboard.parse("V")));
    try testing.expect(!vaxisMatcher(Key{ .codepoint = 'v' }).matches(try Keyboard.parse("Shift+v")));
}
