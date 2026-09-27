const std = @import("std");
const testing = std.testing;

/// `NamedKey` represents a key identified by name, such as `Enter`, `Down`, or `F1`.\
/// The `named` variant of `Key` holds this value.\
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

    /// `label` returns the standard key name, such as `PageDown`.\
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

/// `Modifiers` holds the modifier flags for a `Keyboard` value.\
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

/// `Platform` selects which concrete modifier the portable `Mod` name uses.
/// The application chooses the platform of the client keyboard, which may differ from the build target.
pub const Platform = enum {
    /// Resolve `Mod` to `Super` for a macOS client.
    macos,
    /// Resolve `Mod` to `Ctrl` for a Windows client.
    windows,
    /// Resolve `Mod` to `Ctrl` for a Linux client.
    linux,
};

/// `DisplayStyle` selects platform-friendly modifier names for shortcut labels.
/// It changes labels only; it does not change matching or collision behavior.
pub const DisplayStyle = enum {
    /// Display `Ctrl`, `Alt`, `Shift`, and `Super` on every platform.
    common,
    /// Display `Option` for Alt and `Command` for Super.
    macos,
    /// Display `Alt` for Alt and `Win` for Super.
    windows,
    /// Display `Alt` for Alt and `Super` for Super.
    linux,
};

/// `Key` represents one character or named key, without modifiers.\
/// `Keyboard` combines this value with `Modifiers` to describe keys such as `Ctrl+Enter`.
pub const Key = union(enum) {
    /// This value holds a Unicode codepoint, such as `'j'` or `'あ'`.\
    /// A codepoint is a number that identifies a character.\
    /// Use a value that UTF-8 can encode.
    character: u21,
    /// This value holds a named key, such as `.enter` or `.down`.
    named: NamedKey,
};

/// `Keyboard` describes the key and modifiers to match.\
/// For `Ctrl+Enter`, `key` is `.{ .named = .enter }` and `modifiers.ctrl` is `true`.\
/// A matcher compares incoming events from the terminal library with this value.
pub const Keyboard = struct {
    /// This field holds the character or named key to match.
    key: Key,
    /// These flags specify the modifiers to match.
    modifiers: Modifiers = .{},

    /// `parse` reads a key string, such as `j`, `Ctrl+Enter`, or `Ctrl++`.\
    /// Key names and modifier names ignore case.\
    /// Modifiers accept `Shift`, `Ctrl` (`Control`), `Alt` (`Option`, `Opt`),\
    /// `Super` (`Command`, `Cmd`, `Win`, `Windows`), `Meta`, and `Hyper`.\
    /// Use `parseForPlatform` to parse the portable `Mod` modifier.\
    /// Aliases set the same flags as canonical names and count as duplicates when repeated.\
    /// Character keys keep their case and must contain exactly one Unicode codepoint.\
    /// `parse` returns `error.InvalidKey` for invalid UTF-8, unknown names, duplicate modifiers, or malformed strings.
    pub fn parse(text: []const u8) error{InvalidKey}!Keyboard {
        return parseText(text, null);
    }

    /// `parseForPlatform` reads a key string and resolves `Mod` for `platform`.\
    /// `Mod` resolves to `Super` on macOS and `Ctrl` on Windows and Linux.\
    /// Other modifier names retain their concrete meaning on every platform.\
    /// Choose the platform of the client keyboard; the build target may be different.
    pub fn parseForPlatform(text: []const u8, platform: Platform) error{InvalidKey}!Keyboard {
        return parseText(text, platform);
    }

    fn parseText(text: []const u8, platform: ?Platform) error{InvalidKey}!Keyboard {
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
            else if (std.ascii.eqlIgnoreCase(name, "Mod")) blk: {
                const selected_platform = platform orelse return error.InvalidKey;
                break :blk if (selected_platform == .macos) "super" else "ctrl";
            } else name;
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

    /// `format` writes a key label into `buffer` with common key and modifier names.\
    /// Modifiers appear in this order: `Ctrl`, `Alt`, `Shift`, `Super`, `Meta`, `Hyper`.\
    /// Character keys keep their case.\
    /// The result refers to `buffer`.\
    /// While you use the result, keep `buffer` alive and unchanged.
    pub fn format(self: Keyboard, buffer: *[96]u8) []const u8 {
        return self.formatWithStyle(buffer, .common);
    }

    /// `formatWithStyle` writes a key label into `buffer` using `style` modifier names.\
    /// Modifiers keep the order `Ctrl`, `Alt`, `Shift`, `Super`, `Meta`, `Hyper`.\
    /// Character keys keep their case, and a literal plus remains the final key character.\
    /// Formatting does not change the key or modifier flags.\
    /// The result refers to `buffer`; keep it alive and unchanged while using the result.
    pub fn formatWithStyle(self: Keyboard, buffer: *[96]u8, style: DisplayStyle) []const u8 {
        const labels = switch (style) {
            .common => .{ "Ctrl+", "Alt+", "Shift+", "Super+", "Meta+", "Hyper+" },
            .macos => .{ "Ctrl+", "Option+", "Shift+", "Command+", "Meta+", "Hyper+" },
            .windows => .{ "Ctrl+", "Alt+", "Shift+", "Win+", "Meta+", "Hyper+" },
            .linux => .{ "Ctrl+", "Alt+", "Shift+", "Super+", "Meta+", "Hyper+" },
        };
        var end: usize = 0;
        inline for (.{ "ctrl", "alt", "shift", "super", "meta", "hyper" }, labels) |field, label| {
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

    /// `equivalent` returns `true` if two `Keyboard` values are equal for key conflict checks.\
    /// ASCII uppercase letters equal lowercase letters with `Shift`. For example, `J` equals `Shift+j`.\
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

test "parse resolves platform modifier names with case-insensitive spelling" {
    // Platform spellings must produce the same flags as portable configuration names.
    try testing.expectEqual(try Keyboard.parse("Alt+k"), try Keyboard.parse("oPtIoN+k"));
    try testing.expectEqual(try Keyboard.parse("Alt+k"), try Keyboard.parse("OpT+k"));
    try testing.expectEqual(try Keyboard.parse("Super+k"), try Keyboard.parse("cOmMaNd+k"));
    try testing.expectEqual(try Keyboard.parse("Super+k"), try Keyboard.parse("CmD+k"));
    try testing.expectEqual(try Keyboard.parse("Super+k"), try Keyboard.parse("wIn+k"));
    try testing.expectEqual(try Keyboard.parse("Super+k"), try Keyboard.parse("WiNdOwS+k"));
    try testing.expectEqual(try Keyboard.parse("Ctrl+k"), try Keyboard.parse("cOnTrOl+k"));
    try testing.expectEqual(try Keyboard.parse("Ctrl+Alt+Super++"), try Keyboard.parse("Control+Option+Command++"));
    try testing.expect(!(try Keyboard.parse("Cmd+k")).equivalent(try Keyboard.parse("Meta+k")));
    try testing.expect(!(try Keyboard.parse("Win+k")).equivalent(try Keyboard.parse("Hyper+k")));
}

test "parseForPlatform resolves Mod and preserves concrete modifiers" {
    // Applications select the client platform explicitly because a terminal may be remote.
    try testing.expectEqual(try Keyboard.parse("Super+s"), try Keyboard.parseForPlatform("mOd+s", .macos));
    try testing.expectEqual(try Keyboard.parse("Ctrl+s"), try Keyboard.parseForPlatform("Mod+s", .windows));
    try testing.expectEqual(try Keyboard.parse("Ctrl+s"), try Keyboard.parseForPlatform("Mod+s", .linux));
    try testing.expectEqual(try Keyboard.parse("Ctrl+s"), try Keyboard.parseForPlatform("Ctrl+s", .macos));
    try testing.expectEqual(try Keyboard.parse("Ctrl+s"), try Keyboard.parseForPlatform("Ctrl+s", .windows));
    try testing.expectEqual(try Keyboard.parse("Ctrl+s"), try Keyboard.parseForPlatform("Ctrl+s", .linux));
    try testing.expectEqual(try Keyboard.parse("Super+s"), try Keyboard.parseForPlatform("Super+s", .macos));
    try testing.expectEqual(try Keyboard.parse("Super+s"), try Keyboard.parseForPlatform("Super+s", .windows));
    try testing.expectEqual(try Keyboard.parse("Super+s"), try Keyboard.parseForPlatform("Super+s", .linux));
}

test "parseForPlatform rejects duplicate effective modifiers" {
    // Mod aliases must be checked after platform expansion so duplicate flags cannot slip through.
    try testing.expectError(error.InvalidKey, Keyboard.parseForPlatform("Ctrl+Mod+s", .windows));
    try testing.expectError(error.InvalidKey, Keyboard.parseForPlatform("Control+Mod+s", .linux));
    try testing.expectError(error.InvalidKey, Keyboard.parseForPlatform("Super+Mod+s", .macos));
    try testing.expectError(error.InvalidKey, Keyboard.parseForPlatform("Command+Mod+s", .macos));
    try testing.expectError(error.InvalidKey, Keyboard.parse("Mod+s"));
}

test "parse rejects repeated modifiers written as platform aliases" {
    // Alternate names must not bypass duplicate checks and hide configuration mistakes.
    try testing.expectError(error.InvalidKey, Keyboard.parse("Alt+Option+k"));
    try testing.expectError(error.InvalidKey, Keyboard.parse("Opt+Option+k"));
    try testing.expectError(error.InvalidKey, Keyboard.parse("Command+Super+k"));
    try testing.expectError(error.InvalidKey, Keyboard.parse("Cmd+Command+k"));
    try testing.expectError(error.InvalidKey, Keyboard.parse("Win+Windows+k"));
    try testing.expectError(error.InvalidKey, Keyboard.parse("Windows+Super+k"));
    try testing.expectError(error.InvalidKey, Keyboard.parse("Control+Ctrl+k"));
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

test "formatWithStyle changes modifier names and keeps key spelling" {
    // Labels should reflect the selected keyboard without changing key matching.
    const keyboard = Keyboard{
        .key = .{ .character = 'K' },
        .modifiers = .{ .ctrl = true, .alt = true, .shift = true, .super = true },
    };
    var buffer: [96]u8 = undefined;
    try testing.expectEqualStrings("Ctrl+Alt+Shift+Super+K", keyboard.formatWithStyle(&buffer, .common));
    try testing.expectEqualStrings("Ctrl+Option+Shift+Command+K", keyboard.formatWithStyle(&buffer, .macos));
    try testing.expectEqualStrings("Ctrl+Alt+Shift+Win+K", keyboard.formatWithStyle(&buffer, .windows));
    try testing.expectEqualStrings("Ctrl+Alt+Shift+Super+K", keyboard.formatWithStyle(&buffer, .linux));
    try testing.expectEqualStrings("Option+Command++", (Keyboard{
        .key = .{ .character = '+' },
        .modifiers = .{ .alt = true, .super = true },
    }).formatWithStyle(&buffer, .macos));
    try testing.expect(keyboard.equivalent(try Keyboard.parse("Ctrl+Option+Shift+Command+K")));
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
