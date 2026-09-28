const Keyboard = @import("key.zig").Keyboard;

/// Matcher for one libvaxis key event.\
/// Pass it to `Bindings.resolve` or `SequenceResolver.feed`.\
/// Matching uses that event's rules.\
/// It does not infer a physical key from `base_layout_codepoint`.
pub fn vaxisMatcher(key: anytype) Matcher(@TypeOf(key)) {
    return .{ .key = key };
}

fn Matcher(comptime NativeKey: type) type {
    return struct {
        /// The libvaxis key event to match.
        key: NativeKey,

        /// Returns `true` when the event matches `spec` under the event's own rules.
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
