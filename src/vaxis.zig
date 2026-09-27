const Keyboard = @import("key.zig").Keyboard;

/// `vaxisMatcher` creates a matcher for a libvaxis key event.\
/// Pass the matcher to `Bindings.resolve`.\
/// It uses `Key.matches` to match logical characters and modifiers.\
/// It does not infer a physical key from `base_layout_codepoint`.
pub fn vaxisMatcher(key: anytype) Matcher(@TypeOf(key)) {
    return .{ .key = key };
}

/// `Matcher` creates a type that holds the terminal library's key event.
fn Matcher(comptime NativeKey: type) type {
    return struct {
        /// This field holds the incoming key event.
        key: NativeKey,

        /// `matches` returns `true` if the incoming event matches `spec` under libvaxis rules.
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

test "vaxisMatcher treats Option and Alt aliases as the same modifier" {
    // When Option is delivered as Alt, both accepted spellings must match the same event value.
    const testing = @import("std").testing;
    const Key = @import("vaxis").Key;
    const option = try Keyboard.parse("Option+k");
    const alt = try Keyboard.parse("Alt+k");
    const matcher = vaxisMatcher(Key{ .codepoint = 'k', .mods = .{ .alt = true } });
    try testing.expect(option.equivalent(alt));
    try testing.expect(matcher.matches(option));
    try testing.expect(matcher.matches(alt));
}

test "vaxisMatcher accepts a Caps Lock key value with uppercase text" {
    // Lock state and event text can match different configured characters.
    const testing = @import("std").testing;
    const Key = @import("vaxis").Key;
    const matcher = vaxisMatcher(Key{
        .codepoint = 'a',
        .text = "A",
        .mods = .{ .caps_lock = true },
    });
    const lowercase = try Keyboard.parse("a");
    try testing.expect(!lowercase.equivalent(try Keyboard.parse("A")));
    try testing.expect(matcher.matches(lowercase));
    try testing.expect(matcher.matches(try Keyboard.parse("A")));
}

test "vaxisMatcher preserves a Unicode codepoint and explicit AltGr modifiers" {
    // AltGr has no library-level meaning; matching follows the modifiers the terminal reports.
    const testing = @import("std").testing;
    const Key = @import("vaxis").Key;
    const unicode = vaxisMatcher(Key{ .codepoint = 'あ', .text = "あ" });
    const altgr = vaxisMatcher(Key{
        .codepoint = '@',
        .text = "@",
        .mods = .{ .ctrl = true, .alt = true },
    });
    try testing.expect(unicode.matches(try Keyboard.parse("あ")));
    try testing.expect(altgr.matches(try Keyboard.parse("Ctrl+Alt+@")));
    try testing.expect(!altgr.matches(try Keyboard.parse("@")));
}

test "vaxisMatcher does not infer a key from base layout data" {
    // The adapter uses Key.matches, which compares the reported logical key rather than its base-layout hint.
    const testing = @import("std").testing;
    const Key = @import("vaxis").Key;
    const matcher = vaxisMatcher(Key{
        .codepoint = 'y',
        .text = "y",
        .base_layout_codepoint = 'z',
        .mods = .{ .ctrl = true },
    });
    try testing.expect(matcher.matches(try Keyboard.parse("Ctrl+y")));
    try testing.expect(!matcher.matches(try Keyboard.parse("Ctrl+z")));
}

test "vaxisMatcher can overlap for non-equivalent shifted bindings" {
    // Native text and shifted-codepoint matching can overlap beyond static configuration equivalence.
    const testing = @import("std").testing;
    const Key = @import("vaxis").Key;
    const shifted_semicolon = try Keyboard.parse("Shift+;");
    const colon = try Keyboard.parse(":");
    const matcher = vaxisMatcher(Key{
        .codepoint = ';',
        .text = ":",
        .shifted_codepoint = ':',
        .mods = .{ .shift = true },
    });
    try testing.expect(!shifted_semicolon.equivalent(colon));
    try testing.expect(matcher.matches(shifted_semicolon));
    try testing.expect(matcher.matches(colon));
}
