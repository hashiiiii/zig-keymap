const std = @import("std");
const testing = std.testing;

/// Named keys accepted by KeyPress.parse.
pub const NamedKey = enum {
    up,
    down,
    left,
    right,
    enter,
    escape,
    tab,
    backspace,
    delete,
    home,
    end,
    page_up,
    page_down,
    insert,
    space,
    caps_lock,
    scroll_lock,
    num_lock,
    print_screen,
    pause,
    menu,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
    f25,
    f26,
    f27,
    f28,
    f29,
    f30,
    f31,
    f32,
    f33,
    f34,
    f35,
    kp_0,
    kp_1,
    kp_2,
    kp_3,
    kp_4,
    kp_5,
    kp_6,
    kp_7,
    kp_8,
    kp_9,
    kp_decimal,
    kp_divide,
    kp_multiply,
    kp_subtract,
    kp_add,
    kp_enter,
    kp_equal,
    kp_separator,
    kp_left,
    kp_right,
    kp_up,
    kp_down,
    kp_page_up,
    kp_page_down,
    kp_home,
    kp_end,
    kp_insert,
    kp_delete,
    kp_begin,

    fn label(comptime self: NamedKey) []const u8 {
        const text = comptime blk: {
            const tag = @tagName(self);
            const name = if (std.mem.startsWith(u8, tag, "kp_")) "Keypad" ++ tag[3..] else tag;
            var buffer: [name.len - std.mem.count(u8, name, "_")]u8 = undefined;
            var index = 0;
            for (name) |character| {
                if (character == '_') continue;
                buffer[index] = character;
                index += 1;
            }
            break :blk buffer;
        };
        return &text;
    }
};

/// Modifier flags matched with a `Key`.
pub const Modifiers = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
    meta: bool = false,
    hyper: bool = false,
};

/// One character or named key, without modifiers.
pub const Key = union(enum) {
    /// One Unicode scalar.
    character: u21,
    /// A named key, such as `.enter`.
    named: NamedKey,
};

/// One key and its modifiers, used for configuration and input.
pub const KeyPress = struct {
    /// Character or named key to match.
    key: Key,
    /// Modifiers that must match with `key`.
    modifiers: Modifiers = .{},

    /// Parses one character or a named key with optional modifiers.
    /// Key and modifier names ignore case; characters keep their case.
    /// Accepts Ctrl/Control, Alt/Option/Opt, Super/Command/Cmd/Win/Windows, Shift, Meta, and Hyper.
    /// Invalid strings return error.InvalidKey.
    pub fn parse(text: []const u8) error{InvalidKey}!KeyPress {
        var remaining = text;
        var modifiers: Modifiers = .{};
        while (!std.mem.eql(u8, remaining, "+")) {
            const separator = std.mem.indexOfScalar(u8, remaining, '+') orelse break;
            const name = remaining[0..separator];
            const prefix = if (std.ascii.eqlIgnoreCase(name, "Control"))
                "ctrl"
            else if (std.ascii.eqlIgnoreCase(name, "Option") or std.ascii.eqlIgnoreCase(name, "Opt"))
                "alt"
            else if (std.ascii.eqlIgnoreCase(name, "Command") or std.ascii.eqlIgnoreCase(name, "Cmd") or
                std.ascii.eqlIgnoreCase(name, "Win") or std.ascii.eqlIgnoreCase(name, "Windows"))
                "super"
            else
                name;
            var found = false;
            inline for (std.meta.fields(Modifiers)) |field| {
                if (std.ascii.eqlIgnoreCase(prefix, field.name)) {
                    if (@field(modifiers, field.name)) return error.InvalidKey;
                    @field(modifiers, field.name) = true;
                    found = true;
                }
            }
            if (!found) return error.InvalidKey;
            remaining = remaining[separator + 1 ..];
        }
        inline for (comptime std.meta.tags(NamedKey)) |named| {
            if (std.ascii.eqlIgnoreCase(remaining, named.label())) return .{ .key = .{ .named = named }, .modifiers = modifiers };
        }
        const view = std.unicode.Utf8View.init(remaining) catch return error.InvalidKey;
        var iterator = view.iterator();
        const character = iterator.nextCodepoint() orelse return error.InvalidKey;
        if (iterator.nextCodepoint() != null) return error.InvalidKey;
        return .{ .key = .{ .character = character }, .modifiers = modifiers };
    }

    /// Matches one key press. ASCII uppercase equals the lowercase letter with Shift.
    /// Space, Tab, Enter, Escape, and Backspace also match their character values.
    pub fn matches(self: KeyPress, other: KeyPress) bool {
        return std.meta.eql(self.normalized(), other.normalized());
    }

    fn normalized(self: KeyPress) KeyPress {
        var result = self;
        if (result.key == .named) {
            result.key = switch (result.key.named) {
                .space => .{ .character = ' ' },
                .tab => .{ .character = '\t' },
                .enter => .{ .character = '\r' },
                .escape => .{ .character = 0x1b },
                .backspace => .{ .character = 0x7f },
                else => result.key,
            };
        }
        if (result.key == .character and result.key.character >= 'A' and result.key.character <= 'Z') {
            result.key.character += 'a' - 'A';
            result.modifiers.shift = true;
        }
        return result;
    }
};

test "parse preserves character case and accepts case-insensitive names" {
    // Character case changes bindings, while modifier and named-key spelling does not.
    try testing.expectEqual(KeyPress{ .key = .{ .character = 'あ' }, .modifiers = .{ .ctrl = true } }, try KeyPress.parse("cTrL+あ"));
    try testing.expectEqual(KeyPress{ .key = .{ .character = 'J' } }, try KeyPress.parse("J"));
    try testing.expectEqual(KeyPress{ .key = .{ .named = .page_down } }, try KeyPress.parse("pagedown"));
    try testing.expectEqual(KeyPress{
        .key = .{ .named = .enter },
        .modifiers = .{ .ctrl = true, .alt = true, .shift = true, .super = true, .meta = true, .hyper = true },
    }, try KeyPress.parse("Hyper+Meta+Super+Shift+Alt+Ctrl+Enter"));
}

test "parse accepts modifier aliases without OS selection" {
    // OS-specific spellings must set the same modifier flags on every target.
    const alt: KeyPress = .{ .key = .{ .character = 'k' }, .modifiers = .{ .alt = true } };
    const super: KeyPress = .{ .key = .{ .character = 'k' }, .modifiers = .{ .super = true } };
    const ctrl: KeyPress = .{ .key = .{ .character = 'k' }, .modifiers = .{ .ctrl = true } };
    try testing.expectEqual(alt, try KeyPress.parse("oPtIoN+k"));
    try testing.expectEqual(alt, try KeyPress.parse("OpT+k"));
    try testing.expectEqual(super, try KeyPress.parse("cOmMaNd+k"));
    try testing.expectEqual(super, try KeyPress.parse("CmD+k"));
    try testing.expectEqual(super, try KeyPress.parse("wIn+k"));
    try testing.expectEqual(super, try KeyPress.parse("WiNdOwS+k"));
    try testing.expectEqual(ctrl, try KeyPress.parse("cOnTrOl+k"));
}

test "parse accepts extended function system and keypad names" {
    // Extended keys must be configurable, including names with multiple words.
    try testing.expectEqualStrings("f13", @tagName((try KeyPress.parse("F13")).key.named));
    try testing.expectEqualStrings("f35", @tagName((try KeyPress.parse("f35")).key.named));
    try testing.expectEqualStrings("print_screen", @tagName((try KeyPress.parse("PrintScreen")).key.named));
    try testing.expectEqualStrings("caps_lock", @tagName((try KeyPress.parse("CapsLock")).key.named));
    try testing.expectEqualStrings("kp_0", @tagName((try KeyPress.parse("Keypad0")).key.named));
    try testing.expectEqualStrings("kp_9", @tagName((try KeyPress.parse("Keypad9")).key.named));
    try testing.expectEqualStrings("kp_page_down", @tagName((try KeyPress.parse("kEyPaDpAgEdOwN")).key.named));
    try testing.expectError(error.InvalidKey, KeyPress.parse("F36"));
    try testing.expectError(error.InvalidKey, KeyPress.parse("Keypad10"));
}

test "parse rejects repeated modifiers written as platform aliases" {
    // Alternate names must not bypass duplicate checks and hide configuration mistakes.
    try testing.expectError(error.InvalidKey, KeyPress.parse("Alt+Option+k"));
    try testing.expectError(error.InvalidKey, KeyPress.parse("Command+Super+k"));
    try testing.expectError(error.InvalidKey, KeyPress.parse("Control+Ctrl+k"));
}

test "parse accepts a literal plus with or without modifiers" {
    // Plus is both a key and the modifier separator.
    try testing.expectEqual(KeyPress{ .key = .{ .character = '+' } }, try KeyPress.parse("+"));
    try testing.expectEqual(KeyPress{ .key = .{ .character = '+' }, .modifiers = .{ .ctrl = true } }, try KeyPress.parse("Ctrl++"));
}

test "parse rejects malformed key expressions" {
    // A binding must identify one codepoint and each modifier at most once.
    try testing.expectError(error.InvalidKey, KeyPress.parse(""));
    try testing.expectError(error.InvalidKey, KeyPress.parse("Ctrl+"));
    try testing.expectError(error.InvalidKey, KeyPress.parse("Ctrl+Ctrl+x"));
    try testing.expectError(error.InvalidKey, KeyPress.parse("Unknown+x"));
    try testing.expectError(error.InvalidKey, KeyPress.parse("word"));
    try testing.expectError(error.InvalidKey, KeyPress.parse("\xff"));
    try testing.expectError(error.InvalidKey, KeyPress.parse("a\xcc\x81"));
}

test "matches detects ASCII Shift aliases without merging other modifiers" {
    // Equivalent spellings must collide, but distinct key presses must remain available.
    try testing.expect((try KeyPress.parse("J")).matches(try KeyPress.parse("Shift+j")));
    try testing.expect(!(try KeyPress.parse("J")).matches(try KeyPress.parse("j")));
    try testing.expect(!(try KeyPress.parse("Ctrl+j")).matches(try KeyPress.parse("j")));
    const super = try KeyPress.parse("Cmd+k");
    try testing.expect(!super.matches(.{ .key = .{ .character = 'k' }, .modifiers = .{ .meta = true } }));
    try testing.expect(!super.matches(.{ .key = .{ .character = 'k' }, .modifiers = .{ .hyper = true } }));
}

test "matches detects named keys and their control character aliases" {
    // Literal characters must not bypass collision checks for named keys.
    try testing.expect((try KeyPress.parse("Space")).matches(try KeyPress.parse(" ")));
    try testing.expect((try KeyPress.parse("Tab")).matches(try KeyPress.parse("\t")));
    try testing.expect((try KeyPress.parse("Enter")).matches(try KeyPress.parse("\r")));
    try testing.expect((try KeyPress.parse("Escape")).matches(try KeyPress.parse("\x1b")));
    try testing.expect((try KeyPress.parse("Backspace")).matches(try KeyPress.parse("\x7f")));
}
