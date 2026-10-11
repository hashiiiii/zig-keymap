const KeyPress = @import("../key.zig").KeyPress;

/// Adapts a libvaxis Key for Bindings.receive, preserving native text and Shift matching.
/// ASCII uppercase also matches a lowercase codepoint with Shift.
/// Caps Lock does not imply Shift.
/// Pass the key_press payload from loop.nextEvent().
/// Uses base_layout_codepoint for shortcuts and keypad identity.
/// Modifier-only events are ignored so they cannot cancel pending sequences.
pub fn libvaxisMatcher(key: anytype) Matcher(@TypeOf(key)) {
    return .{ .key = key };
}

fn Matcher(comptime NativeKey: type) type {
    return struct {
        key: NativeKey,

        pub fn isIgnored(self: @This()) bool {
            // libvaxis omits ISO level Shift keys from isModifier().
            // Remove the extra checks once the pinned libvaxis version includes both in isModifier().
            return self.key.isModifier() or
                self.key.codepoint == NativeKey.iso_level_3_shift or
                self.key.codepoint == NativeKey.iso_level_5_shift;
        }

        pub fn matches(self: @This(), spec: KeyPress) bool {
            var native = self.key;
            // Uppercase codepoints can encode Shift, but Caps Lock must not imply it.
            if (native.codepoint >= 'A' and native.codepoint <= 'Z') {
                native.codepoint += 'a' - 'A';
                if (!native.mods.caps_lock) native.mods.shift = true;
            }
            // Character bindings must remain available when layouts differ and text is absent.
            const logical = native;
            if (native.base_layout_codepoint) |base| native.codepoint = base;
            var codepoint = switch (spec.key) {
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
            if (codepoint >= 'A' and codepoint <= 'Z') {
                codepoint += 'a' - 'A';
                modifiers.shift = true;
            }
            if (spec.key == .named) return native.matchExact(codepoint, modifiers);
            const ascii_letter = codepoint >= 'a' and codepoint <= 'z';
            if (ascii_letter) {
                // Optional text must not let Shift change which ASCII binding wins.
                if (native.mods.shift != modifiers.shift) return false;
            }
            // Native text consumes Shift; explicit bindings and unchanged non-letter keys must retain it.
            if (!ascii_letter and spec.modifiers.shift != native.mods.shift) {
                if (spec.modifiers.shift or native.codepoint == codepoint) return false;
            }
            if (native.matches(codepoint, modifiers) or logical.matchExact(codepoint, modifiers)) return true;
            if (modifiers.shift and ascii_letter) {
                // Shifted-codepoint matching consumes Shift, so test the uppercase spelling too.
                modifiers.shift = false;
                return native.matches(codepoint - ('a' - 'A'), modifiers);
            }
            return false;
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
