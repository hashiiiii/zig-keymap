const std = @import("std");
const testing = std.testing;

/// A key identified by name, such as `Enter`, `Down`, or `F1`.
/// Used by the `named` variant of `Key`. `label()` returns the spelling accepted by `Keyboard.parse`.
pub const NamedKey = enum {
    /// Up arrow.
    up,
    /// Down arrow.
    down,
    /// Left arrow.
    left,
    /// Right arrow.
    right,
    /// Enter key.
    enter,
    /// Escape key.
    escape,
    /// Tab key.
    tab,
    /// Backspace key.
    backspace,
    /// Delete key.
    delete,
    /// Home key.
    home,
    /// End key.
    end,
    /// Page Up key, written as `PageUp` in settings.
    page_up,
    /// Page Down key, written as `PageDown` in settings.
    page_down,
    /// Insert key.
    insert,
    /// Space bar.
    space,
    /// Function key F1.
    f1,
    /// Function key F2.
    f2,
    /// Function key F3.
    f3,
    /// Function key F4.
    f4,
    /// Function key F5.
    f5,
    /// Function key F6.
    f6,
    /// Function key F7.
    f7,
    /// Function key F8.
    f8,
    /// Function key F9.
    f9,
    /// Function key F10.
    f10,
    /// Function key F11.
    f11,
    /// Function key F12.
    f12,

    /// Returns the standard key name, such as `PageDown`.
    /// The returned string is fixed; do not free it.
    pub fn label(self: NamedKey) []const u8 {
        return switch (self) {
            .up => "Up",
            .down => "Down",
            .left => "Left",
            .right => "Right",
            .enter => "Enter",
            .escape => "Escape",
            .tab => "Tab",
            .backspace => "Backspace",
            .delete => "Delete",
            .home => "Home",
            .end => "End",
            .page_up => "PageUp",
            .page_down => "PageDown",
            .insert => "Insert",
            .space => "Space",
            .f1 => "F1",
            .f2 => "F2",
            .f3 => "F3",
            .f4 => "F4",
            .f5 => "F5",
            .f6 => "F6",
            .f7 => "F7",
            .f8 => "F8",
            .f9 => "F9",
            .f10 => "F10",
            .f11 => "F11",
            .f12 => "F12",
        };
    }
};

/// Modifier flags used with a `Key` in `Keyboard`.
/// All flags default to `false`; `Ctrl+Enter` sets only `ctrl`.
pub const Modifiers = packed struct {
    /// Whether Shift is included in the key condition.
    shift: bool = false,
    /// Whether Ctrl is included in the key condition.
    ctrl: bool = false,
    /// Whether Alt is included in the key condition.
    alt: bool = false,
    /// Whether Super is included in the key condition.
    super: bool = false,
    /// Whether Meta is included in the key condition.
    meta: bool = false,
    /// Whether Hyper is included in the key condition.
    hyper: bool = false,
};

/// One character or named key, without modifiers.
/// `Keyboard` combines this value with `Modifiers` to describe inputs such as `Ctrl+Enter`.
pub const Key = union(enum) {
    /// A Unicode codepoint, such as `'j'` or `'あ'`. Must be valid for UTF-8 encoding.
    character: u21,
    /// A key identified by name, such as `.enter` or `.down`.
    named: NamedKey,
};

/// One key and its modifiers, used as a matching condition.
/// For `Ctrl+Enter`, `key` is `.{ .named = .enter }` and `modifiers.ctrl` is `true`.
/// Incoming events remain in the terminal library's key type; a matcher compares them with this condition.
pub const Keyboard = struct {
    /// The character or named key to match.
    key: Key,
    /// Modifier flags used when matching the key.
    modifiers: Modifiers = .{},

    /// Parses a key expression, such as `j`, `Ctrl+Enter`, or `Ctrl++`.
    /// Key and modifier names ignore case. Character keys preserve case and must contain exactly one Unicode codepoint.
    /// Returns `error.InvalidKey` for invalid UTF-8, unknown names, duplicate modifiers, or malformed expressions.
    pub fn parse(text: []const u8) error{InvalidKey}!Keyboard {
        var remaining = text;
        var modifiers: Modifiers = .{};
        while (!std.mem.eql(u8, remaining, "+")) {
            const separator = std.mem.indexOfScalar(u8, remaining, '+') orelse break;
            const prefix = remaining[0..separator];
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
        inline for (std.meta.tags(NamedKey)) |named| {
            if (std.ascii.eqlIgnoreCase(remaining, named.label())) return .{ .key = .{ .named = named }, .modifiers = modifiers };
        }
        const view = std.unicode.Utf8View.init(remaining) catch return error.InvalidKey;
        var iterator = view.iterator();
        const character = iterator.nextCodepoint() orelse return error.InvalidKey;
        if (iterator.nextCodepoint() != null) return error.InvalidKey;
        return .{ .key = .{ .character = character }, .modifiers = modifiers };
    }

    /// Writes a key label into `buffer`, using standard key and modifier names.
    /// Modifier order is `Ctrl`, `Alt`, `Shift`, `Super`, `Meta`, `Hyper`; character case is preserved.
    /// The returned slice refers to `buffer` and remains valid until that buffer is changed or goes out of scope.
    pub fn format(self: Keyboard, buffer: *[96]u8) []const u8 {
        var end: usize = 0;
        inline for (.{ "ctrl", "alt", "shift", "super", "meta", "hyper" }, .{ "Ctrl+", "Alt+", "Shift+", "Super+", "Meta+", "Hyper+" }) |field, label| {
            if (@field(self.modifiers, field)) {
                @memcpy(buffer[end..][0..label.len], label);
                end += label.len;
            }
        }
        switch (self.key) {
            .named => |named| {
                const label = named.label();
                @memcpy(buffer[end..][0..label.len], label);
                end += label.len;
            },
            .character => |cp| end += std.unicode.utf8Encode(cp, buffer[end..][0..4]) catch unreachable,
        }
        return buffer[0..end];
    }

    /// Returns whether two conditions are equal for key conflict checks.
    /// ASCII uppercase letters equal lowercase letters with `Shift`; for example, `J` equals `Shift+j`.
    /// `Space`, `Tab`, `Enter`, `Escape`, and `Backspace` equal their character values: space, `\t`, `\r`, `\x1b`, and `\x7f`.
    /// Terminal adapters perform their own event matching.
    pub fn equivalent(a: Keyboard, b: Keyboard) bool {
        return std.meta.eql(a.normalized(), b.normalized());
    }

    fn normalized(self: Keyboard) Keyboard {
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
    try testing.expectEqual(Keyboard{ .key = .{ .character = 'あ' }, .modifiers = .{ .ctrl = true } }, try Keyboard.parse("cTrL+あ"));
    try testing.expectEqual(Keyboard{ .key = .{ .character = 'J' } }, try Keyboard.parse("J"));
    try testing.expectEqual(Keyboard{ .key = .{ .named = .page_down } }, try Keyboard.parse("pagedown"));
    try testing.expectEqual(Keyboard{
        .key = .{ .named = .enter },
        .modifiers = .{ .ctrl = true, .alt = true, .shift = true, .super = true, .meta = true, .hyper = true },
    }, try Keyboard.parse("Hyper+Meta+Super+Shift+Alt+Ctrl+Enter"));
}

test "parse accepts a literal plus with or without modifiers" {
    // Plus is both a key and the modifier separator.
    try testing.expectEqual(Keyboard{ .key = .{ .character = '+' } }, try Keyboard.parse("+"));
    try testing.expectEqual(Keyboard{ .key = .{ .character = '+' }, .modifiers = .{ .ctrl = true } }, try Keyboard.parse("Ctrl++"));
}

test "parse rejects malformed key expressions" {
    // A binding must identify one codepoint and each modifier at most once.
    try testing.expectError(error.InvalidKey, Keyboard.parse(""));
    try testing.expectError(error.InvalidKey, Keyboard.parse("Ctrl+"));
    try testing.expectError(error.InvalidKey, Keyboard.parse("Ctrl+Ctrl+x"));
    try testing.expectError(error.InvalidKey, Keyboard.parse("Unknown+x"));
    try testing.expectError(error.InvalidKey, Keyboard.parse("word"));
    try testing.expectError(error.InvalidKey, Keyboard.parse("\xff"));
    try testing.expectError(error.InvalidKey, Keyboard.parse("a\xcc\x81"));
}

test "format produces canonical hints for named and character keys" {
    // Hints must show the effective binding in a stable, readable order.
    var buffer: [96]u8 = undefined;
    try testing.expectEqualStrings("Ctrl+Alt+Shift+Super+Meta+Hyper+Enter", (Keyboard{
        .key = .{ .named = .enter },
        .modifiers = .{ .ctrl = true, .alt = true, .shift = true, .super = true, .meta = true, .hyper = true },
    }).format(&buffer));
    try testing.expectEqualStrings("Ctrl+あ", (Keyboard{ .key = .{ .character = 'あ' }, .modifiers = .{ .ctrl = true } }).format(&buffer));
    try testing.expectEqualStrings("Ctrl++", (Keyboard{ .key = .{ .character = '+' }, .modifiers = .{ .ctrl = true } }).format(&buffer));
}

test "equivalent detects ASCII Shift aliases without merging other modifiers" {
    // Equivalent spellings must collide, but distinct shortcuts must remain available.
    try testing.expect((try Keyboard.parse("J")).equivalent(try Keyboard.parse("Shift+j")));
    try testing.expect(!(try Keyboard.parse("J")).equivalent(try Keyboard.parse("j")));
    try testing.expect(!(try Keyboard.parse("Ctrl+j")).equivalent(try Keyboard.parse("j")));
}

test "equivalent detects named keys and their control character aliases" {
    // Literal characters must not bypass collision checks for named keys.
    try testing.expect((try Keyboard.parse("Space")).equivalent(try Keyboard.parse(" ")));
    try testing.expect((try Keyboard.parse("Tab")).equivalent(try Keyboard.parse("\t")));
    try testing.expect((try Keyboard.parse("Enter")).equivalent(try Keyboard.parse("\r")));
    try testing.expect((try Keyboard.parse("Escape")).equivalent(try Keyboard.parse("\x1b")));
    try testing.expect((try Keyboard.parse("Backspace")).equivalent(try Keyboard.parse("\x7f")));
}
