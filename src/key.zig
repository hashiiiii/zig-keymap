const std = @import("std");
const testing = std.testing;

/// Names accepted by `KeyPress.parse`.\
/// `label` returns that spelling.
pub const NamedKey = enum {
    /// Written `Up`.
    up,
    /// Written `Down`.
    down,
    /// Written `Left`.
    left,
    /// Written `Right`.
    right,
    /// Written `Enter`.
    enter,
    /// Written `Escape`.
    escape,
    /// Written `Tab`.
    tab,
    /// Written `Backspace`.
    backspace,
    /// Written `Delete`.
    delete,
    /// Written `Home`.
    home,
    /// Written `End`.
    end,
    /// Written `PageUp`.
    page_up,
    /// Written `PageDown`.
    page_down,
    /// Written `Insert`.
    insert,
    /// Written `Space`.
    space,
    /// Written `F1`.
    f1,
    /// Written `F2`.
    f2,
    /// Written `F3`.
    f3,
    /// Written `F4`.
    f4,
    /// Written `F5`.
    f5,
    /// Written `F6`.
    f6,
    /// Written `F7`.
    f7,
    /// Written `F8`.
    f8,
    /// Written `F9`.
    f9,
    /// Written `F10`.
    f10,
    /// Written `F11`.
    f11,
    /// Written `F12`.
    f12,

    /// Returns the spelling `KeyPress.parse` accepts.\
    /// The text is static.
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

/// Modifier flags matched with a `Key`.
pub const Modifiers = packed struct {
    /// Include Shift.
    shift: bool = false,
    /// Include Ctrl.
    ctrl: bool = false,
    /// Include Alt.
    alt: bool = false,
    /// Include Super.
    super: bool = false,
    /// Include Meta.
    meta: bool = false,
    /// Include Hyper.
    hyper: bool = false,
};

/// Chooses the concrete modifier for `Mod`.\
/// Use the client keyboard's platform, which can differ from the build target.
pub const Platform = enum {
    /// `Mod` resolves to `Super`.
    macos,
    /// `Mod` resolves to `Ctrl`.
    windows,
    /// `Mod` resolves to `Ctrl`.
    linux,
};

/// Selects modifier names for key binding labels.\
/// Matching and collision checks stay the same.
pub const ModifierName = enum {
    /// `Ctrl`, `Alt`, `Shift`, and `Super`.
    common,
    /// `Option` for Alt and `Command` for Super.
    macos,
    /// `Alt` for Alt and `Win` for Super.
    windows,
    /// `Alt` for Alt and `Super` for Super.
    linux,
};

/// One character or named key, without modifiers.
pub const Key = union(enum) {
    /// One Unicode scalar, such as `'j'` or `'あ'`.\
    /// The value must be encodable as UTF-8.
    character: u21,
    /// A named key, such as `.enter`.
    named: NamedKey,
};

/// One key and its modifiers in a binding.\
/// A receiver compares it with one input event.\
/// For `Ctrl+Enter`, `key` is `.{ .named = .enter }` and `modifiers.ctrl` is `true`.
pub const KeyPress = struct {
    /// Character or named key to match.
    key: Key,
    /// Modifiers that must match with `key`.
    modifiers: Modifiers = .{},

    /// Parses `j`, `Ctrl+Enter`, or `Ctrl++`.\
    /// Key names and modifier names ignore case.\
    /// Character keys keep their case and contain one Unicode scalar.\
    /// Modifiers accept `Shift`, `Ctrl` (`Control`), `Alt` (`Option`, `Opt`), `Super` (`Command`, `Cmd`, `Win`, `Windows`), `Meta`, and `Hyper`.\
    /// Aliases set the same flags and count as duplicates when repeated.\
    /// `Mod` requires `parseForPlatform`.\
    /// Returns `error.InvalidKey` for invalid UTF-8, unknown names, duplicate modifiers, or malformed strings.
    pub fn parse(text: []const u8) error{InvalidKey}!KeyPress {
        return parseText(text, null);
    }

    /// Parses a key string and resolves `Mod` for `platform`.\
    /// `Mod` becomes `Super` on macOS and `Ctrl` on Windows and Linux.\
    /// `Ctrl`, `Alt`, and `Super` keep their meaning on every platform.\
    /// `platform` is the client keyboard described by `Platform`.
    pub fn parseForPlatform(text: []const u8, platform: Platform) error{InvalidKey}!KeyPress {
        return parseText(text, platform);
    }

    fn parseText(text: []const u8, platform: ?Platform) error{InvalidKey}!KeyPress {
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

    /// Writes a label using common modifier names.\
    /// Modifiers appear in `ctrl`, `alt`, `shift`, `super`, `meta`, `hyper` order.\
    /// Character keys keep their case.\
    /// The result refers to `buffer`.\
    /// Keep `buffer` alive and unchanged while using the result.
    pub fn format(self: KeyPress, buffer: *[96]u8) []const u8 {
        return self.formatWithModifierName(buffer, .common);
    }

    /// Writes a label using `modifier_name` for modifiers.\
    /// Modifiers appear in `ctrl`, `alt`, `shift`, `super`, `meta`, `hyper` order.\
    /// Character keys keep their case.\
    /// A literal plus stays the final character.\
    /// The result refers to `buffer`.\
    /// Keep `buffer` alive and unchanged while using the result.
    pub fn formatWithModifierName(self: KeyPress, buffer: *[96]u8, modifier_name: ModifierName) []const u8 {
        const labels = switch (modifier_name) {
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

    /// Reports whether two values collide as the same key press.\
    /// ASCII uppercase equals the lowercase letter with `Shift`.\
    /// `J` equals `Shift+j`.\
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
    /// Terminal matchers use their own comparison rules.
    pub fn equivalent(a: KeyPress, b: KeyPress) bool {
        return std.meta.eql(a.normalized(), b.normalized());
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

test "parse resolves platform modifier names with case-insensitive spelling" {
    // Platform spellings must produce the same flags as portable configuration names.
    try testing.expectEqual(try KeyPress.parse("Alt+k"), try KeyPress.parse("oPtIoN+k"));
    try testing.expectEqual(try KeyPress.parse("Alt+k"), try KeyPress.parse("OpT+k"));
    try testing.expectEqual(try KeyPress.parse("Super+k"), try KeyPress.parse("cOmMaNd+k"));
    try testing.expectEqual(try KeyPress.parse("Super+k"), try KeyPress.parse("CmD+k"));
    try testing.expectEqual(try KeyPress.parse("Super+k"), try KeyPress.parse("wIn+k"));
    try testing.expectEqual(try KeyPress.parse("Super+k"), try KeyPress.parse("WiNdOwS+k"));
    try testing.expectEqual(try KeyPress.parse("Ctrl+k"), try KeyPress.parse("cOnTrOl+k"));
    try testing.expectEqual(try KeyPress.parse("Ctrl+Alt+Super++"), try KeyPress.parse("Control+Option+Command++"));
    try testing.expect(!(try KeyPress.parse("Cmd+k")).equivalent(try KeyPress.parse("Meta+k")));
    try testing.expect(!(try KeyPress.parse("Win+k")).equivalent(try KeyPress.parse("Hyper+k")));
}

test "parseForPlatform resolves Mod and preserves concrete modifiers" {
    // Applications select the client platform explicitly because a terminal may be remote.
    try testing.expectEqual(try KeyPress.parse("Super+s"), try KeyPress.parseForPlatform("mOd+s", .macos));
    try testing.expectEqual(try KeyPress.parse("Ctrl+s"), try KeyPress.parseForPlatform("Mod+s", .windows));
    try testing.expectEqual(try KeyPress.parse("Ctrl+s"), try KeyPress.parseForPlatform("Mod+s", .linux));
    try testing.expectEqual(try KeyPress.parse("Ctrl+s"), try KeyPress.parseForPlatform("Ctrl+s", .macos));
    try testing.expectEqual(try KeyPress.parse("Ctrl+s"), try KeyPress.parseForPlatform("Ctrl+s", .windows));
    try testing.expectEqual(try KeyPress.parse("Ctrl+s"), try KeyPress.parseForPlatform("Ctrl+s", .linux));
    try testing.expectEqual(try KeyPress.parse("Super+s"), try KeyPress.parseForPlatform("Super+s", .macos));
    try testing.expectEqual(try KeyPress.parse("Super+s"), try KeyPress.parseForPlatform("Super+s", .windows));
    try testing.expectEqual(try KeyPress.parse("Super+s"), try KeyPress.parseForPlatform("Super+s", .linux));
}

test "parseForPlatform rejects duplicate effective modifiers" {
    // Mod aliases must be checked after platform expansion so duplicate flags cannot slip through.
    try testing.expectError(error.InvalidKey, KeyPress.parseForPlatform("Ctrl+Mod+s", .windows));
    try testing.expectError(error.InvalidKey, KeyPress.parseForPlatform("Control+Mod+s", .linux));
    try testing.expectError(error.InvalidKey, KeyPress.parseForPlatform("Super+Mod+s", .macos));
    try testing.expectError(error.InvalidKey, KeyPress.parseForPlatform("Command+Mod+s", .macos));
    try testing.expectError(error.InvalidKey, KeyPress.parse("Mod+s"));
}

test "parse rejects repeated modifiers written as platform aliases" {
    // Alternate names must not bypass duplicate checks and hide configuration mistakes.
    try testing.expectError(error.InvalidKey, KeyPress.parse("Alt+Option+k"));
    try testing.expectError(error.InvalidKey, KeyPress.parse("Opt+Option+k"));
    try testing.expectError(error.InvalidKey, KeyPress.parse("Command+Super+k"));
    try testing.expectError(error.InvalidKey, KeyPress.parse("Cmd+Command+k"));
    try testing.expectError(error.InvalidKey, KeyPress.parse("Win+Windows+k"));
    try testing.expectError(error.InvalidKey, KeyPress.parse("Windows+Super+k"));
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

test "format produces canonical hints for named and character keys" {
    // Hints must show the effective binding in a stable, readable order.
    var buffer: [96]u8 = undefined;
    try testing.expectEqualStrings("Ctrl+Alt+Shift+Super+Meta+Hyper+Enter", (KeyPress{
        .key = .{ .named = .enter },
        .modifiers = .{ .ctrl = true, .alt = true, .shift = true, .super = true, .meta = true, .hyper = true },
    }).format(&buffer));
    try testing.expectEqualStrings("Ctrl+あ", (KeyPress{ .key = .{ .character = 'あ' }, .modifiers = .{ .ctrl = true } }).format(&buffer));
    try testing.expectEqualStrings("Ctrl++", (KeyPress{ .key = .{ .character = '+' }, .modifiers = .{ .ctrl = true } }).format(&buffer));
}

test "formatWithModifierName changes modifier names and keeps key spelling" {
    // Key labels must keep the bound character recognizable across naming conventions.
    const key_press = KeyPress{
        .key = .{ .character = 'K' },
        .modifiers = .{ .ctrl = true, .alt = true, .shift = true, .super = true },
    };
    var buffer: [96]u8 = undefined;
    try testing.expectEqualStrings("Ctrl+Alt+Shift+Super+K", key_press.formatWithModifierName(&buffer, .common));
    try testing.expectEqualStrings("Ctrl+Option+Shift+Command+K", key_press.formatWithModifierName(&buffer, .macos));
    try testing.expectEqualStrings("Ctrl+Alt+Shift+Win+K", key_press.formatWithModifierName(&buffer, .windows));
    try testing.expectEqualStrings("Ctrl+Alt+Shift+Super+K", key_press.formatWithModifierName(&buffer, .linux));
    try testing.expectEqualStrings("Option+Command++", (KeyPress{
        .key = .{ .character = '+' },
        .modifiers = .{ .alt = true, .super = true },
    }).formatWithModifierName(&buffer, .macos));
}

test "equivalent detects ASCII Shift aliases without merging other modifiers" {
    // Equivalent spellings must collide, but distinct key presses must remain available.
    try testing.expect((try KeyPress.parse("J")).equivalent(try KeyPress.parse("Shift+j")));
    try testing.expect(!(try KeyPress.parse("J")).equivalent(try KeyPress.parse("j")));
    try testing.expect(!(try KeyPress.parse("Ctrl+j")).equivalent(try KeyPress.parse("j")));
}

test "equivalent detects named keys and their control character aliases" {
    // Literal characters must not bypass collision checks for named keys.
    try testing.expect((try KeyPress.parse("Space")).equivalent(try KeyPress.parse(" ")));
    try testing.expect((try KeyPress.parse("Tab")).equivalent(try KeyPress.parse("\t")));
    try testing.expect((try KeyPress.parse("Enter")).equivalent(try KeyPress.parse("\r")));
    try testing.expect((try KeyPress.parse("Escape")).equivalent(try KeyPress.parse("\x1b")));
    try testing.expect((try KeyPress.parse("Backspace")).equivalent(try KeyPress.parse("\x7f")));
}
