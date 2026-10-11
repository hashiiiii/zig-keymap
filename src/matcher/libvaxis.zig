const std = @import("std");
const keymap = @import("../key.zig");
const KeyPress = keymap.KeyPress;
const KeyEvent = keymap.KeyEvent;
const Modifiers = keymap.Modifiers;

/// Adapts a libvaxis event or Key for Bindings.receive, preserving native text and Shift matching.
/// ASCII uppercase also matches a lowercase codepoint with Shift.
/// Pass full events to track left/right modifiers and focus loss. Other events are ignored.
/// Keypad identity also uses base_layout_codepoint.
pub fn libvaxisMatcher(input: anytype) Matcher(NativeKeyType(@TypeOf(input))) {
    const Input = @TypeOf(input);
    const Result = Matcher(NativeKeyType(Input));
    if (@typeInfo(Input) == .@"union") {
        if (input == .key_press) return Result.init(input.key_press, false);
        if (@hasField(Input, "key_release")) {
            if (input == .key_release) return Result.init(input.key_release, true);
        }
        if (@hasField(Input, "focus_out")) {
            if (input == .focus_out) return .{ .event = .focus_lost };
        }
        return .{};
    }
    return Result.init(input, false);
}

fn NativeKeyType(comptime Input: type) type {
    if (@typeInfo(Input) == .@"union") {
        inline for (std.meta.fields(Input)) |field| {
            if (comptime std.mem.eql(u8, field.name, "key_press")) return field.type;
        }
        @compileError("libvaxis events must include key_press");
    }
    return Input;
}

fn Matcher(comptime NativeKey: type) type {
    return struct {
        const Self = @This();
        key: ?NativeKey = null,
        event: ?KeyEvent = null,

        fn init(native: NativeKey, release: bool) Self {
            var press: KeyPress = .{ .key = .{ .character = native.codepoint } };
            inline for (comptime std.meta.tags(keymap.NamedKey)) |named| {
                if (native.codepoint == @field(NativeKey, @tagName(named))) press.key = .{ .named = named };
            }
            inline for (std.meta.fields(Modifiers)) |field| {
                @field(press.modifiers, field.name) = if (@field(native.mods, field.name)) .any else .none;
            }
            return .{ .key = native, .event = if (release) .{ .release = press } else .{ .press = press } };
        }

        pub fn keyEvent(self: Self) ?KeyEvent {
            return self.event;
        }

        pub fn withModifiers(self: Self, modifiers: Modifiers) Self {
            var result = self;
            result.event.?.press.modifiers = modifiers;
            return result;
        }

        pub fn matches(self: Self, spec: KeyPress) bool {
            const event = self.event orelse return false;
            if (event != .press) return false;
            const press = event.press;
            if (keymap.modifierKey(press.key) != null) return press.matches(spec);
            var native = self.key.?;
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
                .shift = spec.modifiers.shift != .none,
                .ctrl = spec.modifiers.ctrl != .none,
                .alt = spec.modifiers.alt != .none,
                .super = spec.modifiers.super != .none,
                .meta = spec.modifiers.meta != .none,
                .hyper = spec.modifiers.hyper != .none,
            };
            const ascii_letter = (codepoint >= 'a' and codepoint <= 'z') or (codepoint >= 'A' and codepoint <= 'Z');
            var actual = press.modifiers;
            var required = spec.modifiers;
            if (ascii_letter) {
                // Optional text must not let a shifted ASCII event match an unshifted binding.
                if (codepoint >= 'A' and codepoint <= 'Z' and required.shift == .none) required.shift = .any;
                if (native.codepoint >= 'A' and native.codepoint <= 'Z' and actual.shift == .none) actual.shift = .any;
            } else if (required.shift == .none and native.codepoint != codepoint and spec.key == .character) {
                // Produced punctuation can consume Shift without merging unchanged keys such as Space or digits.
                actual.shift = .none;
            }
            if (!keymap.modifiersMatch(actual, required)) return false;
            if (spec.key == .named) return native.matchExact(codepoint, modifiers);
            if (native.matches(codepoint, modifiers)) return true;
            if (spec.modifiers.shift != .none and ascii_letter) {
                // Shifted-codepoint matching consumes Shift, so test the uppercase spelling too.
                modifiers.shift = false;
                const uppercase = if (codepoint >= 'a' and codepoint <= 'z') codepoint - ('a' - 'A') else codepoint;
                if (native.matches(uppercase, modifiers)) return true;
            }
            return (KeyPress{
                .key = .{ .character = native.codepoint },
                .modifiers = actual,
            }).matches(spec);
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
        .modifiers = .{ .ctrl = .any, .alt = .any, .shift = .any, .super = .any, .meta = .any, .hyper = .any },
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
