const KeyPress = @import("../key.zig").KeyPress;

/// Adapts a libvaxis Key for Bindings.receive, preserving native text and Shift matching.
/// ASCII uppercase also matches a lowercase codepoint with Shift.
/// Pass the key_press payload from loop.nextEvent().
/// Keypad identity also uses base_layout_codepoint.
pub fn libvaxisMatcher(key: anytype) Matcher(@TypeOf(key)) {
    return .{ .key = key };
}

fn Matcher(comptime NativeKey: type) type {
    return struct {
        key: NativeKey,

        pub fn matches(self: @This(), spec: KeyPress) bool {
            var native = self.key;
            // Windows preserves keypad identity in the base codepoint while reporting text as a character.
            if (native.base_layout_codepoint) |base| {
                if (base >= NativeKey.kp_0 and base <= NativeKey.kp_begin) native.codepoint = base;
            }
            const codepoint = switch (spec.key) {
                .character => |cp| cp,
                .named => |named| switch (named) {
                    inline else => |tag| @field(NativeKey, @tagName(tag)),
                },
            };
            // Keypad text must not hide its dedicated identity from earlier main-key bindings.
            if (native.codepoint >= NativeKey.kp_0 and native.codepoint <= NativeKey.kp_begin and native.codepoint != codepoint)
                return false;
            var modifiers: @TypeOf(native.mods) = .{
                .shift = spec.modifiers.shift,
                .ctrl = spec.modifiers.ctrl,
                .alt = spec.modifiers.alt,
                .super = spec.modifiers.super,
                .meta = spec.modifiers.meta,
                .hyper = spec.modifiers.hyper,
            };
            const ascii_letter = (codepoint >= 'a' and codepoint <= 'z') or (codepoint >= 'A' and codepoint <= 'Z');
            if (ascii_letter) {
                // Optional text must not let Shift change which ASCII binding wins.
                const actual_shift = native.mods.shift or (native.codepoint >= 'A' and native.codepoint <= 'Z');
                const required_shift = spec.modifiers.shift or (codepoint >= 'A' and codepoint <= 'Z');
                if (actual_shift != required_shift) return false;
            }
            // Native text consumes Shift; explicit bindings and unchanged non-letter keys must retain it.
            if (!ascii_letter and spec.modifiers.shift != native.mods.shift) {
                if (spec.modifiers.shift or native.codepoint == codepoint) return false;
            }
            if (spec.key == .named) return native.matchExact(codepoint, modifiers);
            if (native.matches(codepoint, modifiers)) return true;
            if (spec.modifiers.shift and ascii_letter) {
                // Shifted-codepoint matching consumes Shift, so test the uppercase spelling too.
                modifiers.shift = false;
                const uppercase = if (codepoint >= 'a' and codepoint <= 'z') codepoint - ('a' - 'A') else codepoint;
                if (native.matches(uppercase, modifiers)) return true;
            }
            return spec.matches(.{
                .key = .{ .character = native.codepoint },
                .modifiers = .{
                    .shift = native.mods.shift,
                    .ctrl = native.mods.ctrl,
                    .alt = native.mods.alt,
                    .super = native.mods.super,
                    .meta = native.mods.meta,
                    .hyper = native.mods.hyper,
                },
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
    // Some layouts produce the same non-letter text with Shift, which must remain distinct.
    const digit = libvaxisMatcher(Key{ .codepoint = '1', .text = "1", .mods = .{ .shift = true } });
    try testing.expect(!digit.matches(try KeyPress.parse("1")));
    try testing.expect(digit.matches(try KeyPress.parse("Shift+1")));
}

test "libvaxisMatcher matches ASCII Shift aliases without text" {
    // Protocols without text fields must select the same bindings as typed KeyPress input.
    const testing = @import("std").testing;
    const Key = @import("vaxis").Key;
    const lower = libvaxisMatcher(Key{ .codepoint = 'j', .mods = .{ .ctrl = true, .shift = true, .caps_lock = true, .num_lock = true } });
    try testing.expect(lower.matches(try KeyPress.parse("Ctrl+J")));
    try testing.expect(!lower.matches(try KeyPress.parse("Ctrl+j")));
    try testing.expect(libvaxisMatcher(Key{ .codepoint = 'J', .mods = .{ .ctrl = true } }).matches(try KeyPress.parse("Ctrl+Shift+j")));
    try testing.expect(!libvaxisMatcher(Key{ .codepoint = 'j', .mods = .{ .ctrl = true } }).matches(try KeyPress.parse("Ctrl+J")));
    try testing.expect(!libvaxisMatcher(Key{ .codepoint = 'j', .mods = .{ .shift = true } }).matches(try KeyPress.parse("Ctrl+J")));

    // Alternate layouts may produce an ASCII uppercase letter from a non-ASCII base key.
    const shifted = libvaxisMatcher(Key{ .codepoint = 'ı', .shifted_codepoint = 'I', .mods = .{ .ctrl = true, .shift = true } });
    try testing.expect(shifted.matches(try KeyPress.parse("Ctrl+I")));
    try testing.expect(shifted.matches(try KeyPress.parse("Ctrl+Shift+i")));
    try testing.expect(shifted.matches(try KeyPress.parse("Ctrl+Shift+I")));
    try testing.expect(!shifted.matches(try KeyPress.parse("Ctrl+i")));
    try testing.expect(!shifted.matches(try KeyPress.parse("Shift+i")));
}
