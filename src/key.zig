const std = @import("std");
const testing = std.testing;

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

pub const Modifiers = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
    meta: bool = false,
    hyper: bool = false,
};

pub const Key = union(enum) { character: u21, named: NamedKey };

pub const KeySpec = struct {
    key: Key,
    modifiers: Modifiers = .{},

    pub fn parse(text: []const u8) error{InvalidKey}!KeySpec {
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

    pub fn format(self: KeySpec, buffer: *[96]u8) []const u8 {
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

    pub fn equivalent(a: KeySpec, b: KeySpec) bool {
        return std.meta.eql(a.normalized(), b.normalized());
    }

    fn normalized(self: KeySpec) KeySpec {
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
    try testing.expectEqual(KeySpec{ .key = .{ .character = 'あ' }, .modifiers = .{ .ctrl = true } }, try KeySpec.parse("cTrL+あ"));
    try testing.expectEqual(KeySpec{ .key = .{ .character = 'J' } }, try KeySpec.parse("J"));
    try testing.expectEqual(KeySpec{ .key = .{ .named = .page_down } }, try KeySpec.parse("pagedown"));
    try testing.expectEqual(KeySpec{
        .key = .{ .named = .enter },
        .modifiers = .{ .ctrl = true, .alt = true, .shift = true, .super = true, .meta = true, .hyper = true },
    }, try KeySpec.parse("Hyper+Meta+Super+Shift+Alt+Ctrl+Enter"));
}

test "parse accepts a literal plus with or without modifiers" {
    // Plus is both a key and the modifier separator.
    try testing.expectEqual(KeySpec{ .key = .{ .character = '+' } }, try KeySpec.parse("+"));
    try testing.expectEqual(KeySpec{ .key = .{ .character = '+' }, .modifiers = .{ .ctrl = true } }, try KeySpec.parse("Ctrl++"));
}

test "parse rejects malformed key expressions" {
    // A binding must identify one codepoint and each modifier at most once.
    try testing.expectError(error.InvalidKey, KeySpec.parse(""));
    try testing.expectError(error.InvalidKey, KeySpec.parse("Ctrl+"));
    try testing.expectError(error.InvalidKey, KeySpec.parse("Ctrl+Ctrl+x"));
    try testing.expectError(error.InvalidKey, KeySpec.parse("Unknown+x"));
    try testing.expectError(error.InvalidKey, KeySpec.parse("word"));
    try testing.expectError(error.InvalidKey, KeySpec.parse("\xff"));
    try testing.expectError(error.InvalidKey, KeySpec.parse("a\xcc\x81"));
}

test "format produces canonical hints for named and character keys" {
    // Hints must show the effective binding in a stable, readable order.
    var buffer: [96]u8 = undefined;
    try testing.expectEqualStrings("Ctrl+Alt+Shift+Super+Meta+Hyper+Enter", (KeySpec{
        .key = .{ .named = .enter },
        .modifiers = .{ .ctrl = true, .alt = true, .shift = true, .super = true, .meta = true, .hyper = true },
    }).format(&buffer));
    try testing.expectEqualStrings("Ctrl+あ", (KeySpec{ .key = .{ .character = 'あ' }, .modifiers = .{ .ctrl = true } }).format(&buffer));
    try testing.expectEqualStrings("Ctrl++", (KeySpec{ .key = .{ .character = '+' }, .modifiers = .{ .ctrl = true } }).format(&buffer));
}

test "equivalent detects ASCII Shift aliases without merging other modifiers" {
    // Equivalent spellings must collide, but distinct shortcuts must remain available.
    try testing.expect((try KeySpec.parse("J")).equivalent(try KeySpec.parse("Shift+j")));
    try testing.expect(!(try KeySpec.parse("J")).equivalent(try KeySpec.parse("j")));
    try testing.expect(!(try KeySpec.parse("Ctrl+j")).equivalent(try KeySpec.parse("j")));
}

test "equivalent detects named keys and their control character aliases" {
    // Literal characters must not bypass collision checks for named keys.
    try testing.expect((try KeySpec.parse("Space")).equivalent(try KeySpec.parse(" ")));
    try testing.expect((try KeySpec.parse("Tab")).equivalent(try KeySpec.parse("\t")));
    try testing.expect((try KeySpec.parse("Enter")).equivalent(try KeySpec.parse("\r")));
    try testing.expect((try KeySpec.parse("Escape")).equivalent(try KeySpec.parse("\x1b")));
    try testing.expect((try KeySpec.parse("Backspace")).equivalent(try KeySpec.parse("\x7f")));
}
