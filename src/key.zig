const std = @import("std");
const testing = std.testing;

/// `NamedKey` represents a key identified by name, such as `Enter`, `Down`, or `F1`.
/// The `named` variant of `Key` holds this value.
/// `label()` returns the spelling that `Keyboard.parse` accepts.
pub const NamedKey = enum {
    /// This value represents the Up arrow key.
    up,
    /// This value represents the Down arrow key.
    down,
    /// This value represents the Left arrow key.
    left,
    /// This value represents the Right arrow key.
    right,
    /// This value represents the Enter key.
    enter,
    /// This value represents the Escape key.
    escape,
    /// This value represents the Tab key.
    tab,
    /// This value represents the Backspace key.
    backspace,
    /// This value represents the Delete key.
    delete,
    /// This value represents the Home key.
    home,
    /// This value represents the End key.
    end,
    /// This value represents the Page Up key. Use `PageUp` in configuration.
    page_up,
    /// This value represents the Page Down key. Use `PageDown` in configuration.
    page_down,
    /// This value represents the Insert key.
    insert,
    /// This value represents the Space bar.
    space,
    /// This value represents the F1 function key.
    f1,
    /// This value represents the F2 function key.
    f2,
    /// This value represents the F3 function key.
    f3,
    /// This value represents the F4 function key.
    f4,
    /// This value represents the F5 function key.
    f5,
    /// This value represents the F6 function key.
    f6,
    /// This value represents the F7 function key.
    f7,
    /// This value represents the F8 function key.
    f8,
    /// This value represents the F9 function key.
    f9,
    /// This value represents the F10 function key.
    f10,
    /// This value represents the F11 function key.
    f11,
    /// This value represents the F12 function key.
    f12,

    /// `label` returns the standard key name, such as `PageDown`.
    /// The text uses static storage. Do not free it.
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

/// `Modifiers` holds the modifier flags for a `Keyboard` value.
/// All flags default to `false`. `Ctrl+Enter` sets only `ctrl`.
pub const Modifiers = packed struct {
    /// Set to `true` to include the Shift modifier.
    shift: bool = false,
    /// Set to `true` to include the Ctrl modifier.
    ctrl: bool = false,
    /// Set to `true` to include the Alt modifier.
    alt: bool = false,
    /// Set to `true` to include the Super modifier.
    super: bool = false,
    /// Set to `true` to include the Meta modifier.
    meta: bool = false,
    /// Set to `true` to include the Hyper modifier.
    hyper: bool = false,
};

/// `Key` represents one character or named key, without modifiers.
/// `Keyboard` combines this value with `Modifiers` to describe keys such as `Ctrl+Enter`.
pub const Key = union(enum) {
    /// This value holds a Unicode codepoint, such as `'j'` or `'あ'`.
    /// A codepoint is a number that identifies a character.
    /// Use a value that UTF-8 can encode.
    character: u21,
    /// This value holds a named key, such as `.enter` or `.down`.
    named: NamedKey,
};

/// `Keyboard` describes the key and modifiers to match.
/// For `Ctrl+Enter`, `key` is `.{ .named = .enter }` and `modifiers.ctrl` is `true`.
/// A matcher compares incoming events from the terminal library with this value.
pub const Keyboard = struct {
    /// This field holds the character or named key to match.
    key: Key,
    /// These flags specify the modifiers to match.
    modifiers: Modifiers = .{},

    /// `parse` reads a key string, such as `j`, `Ctrl+Enter`, or `Ctrl++`.
    /// Key names and modifier names ignore case.
    /// Character keys keep their case and must contain exactly one Unicode codepoint.
    /// `parse` returns `error.InvalidKey` for invalid UTF-8, unknown names, duplicate modifiers, or malformed strings.
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

    /// `format` writes a key label into `buffer` with standard key names and modifier names.
    /// Modifiers appear in this order: `Ctrl`, `Alt`, `Shift`, `Super`, `Meta`, `Hyper`.
    /// Character keys keep their case.
    /// The result refers to `buffer`.
    /// While you use the result, keep `buffer` alive and unchanged.
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

    /// `equivalent` returns `true` if two `Keyboard` values are equal for key conflict checks.
    /// ASCII uppercase letters equal lowercase letters with `Shift`. For example, `J` equals `Shift+j`.
    /// These named keys equal their character values:
    ///
    /// | Named key | Character |
    /// | --- | --- |
    /// | `Space` | Space (`' '`) |
    /// | `Tab` | `\t` |
    /// | `Enter` | `\r` |
    /// | `Escape` | `\x1b` |
    /// | `Backspace` | `\x7f` |
    ///
    /// Terminal matchers compare incoming events with their own rules.
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
