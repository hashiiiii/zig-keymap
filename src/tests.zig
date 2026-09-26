const std = @import("std");
const keymap = @import("keymap");
const vaxis = @import("vaxis");

const Context = enum { global, tree, dialog };
const Action = enum { quit, move_down, move_up, cancel };
const Map = keymap.Keymap(Context, Action);
const spec: Map.Specification = .{
    .defaults = &.{
        .{ .context = .global, .action = .quit, .keys = &.{"q"} },
        .{ .context = .tree, .action = .move_down, .keys = &.{ "Down", "j" } },
        .{ .context = .tree, .action = .move_up, .keys = &.{ "Up", "k" } },
        .{ .context = .dialog, .action = .cancel, .keys = &.{"Escape"} },
    },
    .active_contexts = &.{ &.{ .global, .tree }, &.{.dialog} },
};

test "override changes one action and retains the other defaults" {
    // Partial files must retain navigation commands they do not mention.
    const loaded = try Map.load(std.testing.allocator, spec, "[tree]\nmove_down = [\"n\"]\n");
    var map = loaded.bindings;
    defer map.deinit();
    try std.testing.expectEqual(Action.move_down, map.resolve(&.{ .global, .tree }, keymap.vaxisMatcher(vaxis.Key{ .codepoint = 'n' })).?);
    try std.testing.expectEqual(@as(?Action, null), map.resolve(&.{.tree}, keymap.vaxisMatcher(vaxis.Key{ .codepoint = 'j' })));
    try std.testing.expectEqual(Action.move_up, map.resolve(&.{.tree}, keymap.vaxisMatcher(vaxis.Key{ .codepoint = vaxis.Key.up })).?);
    try std.testing.expectEqualStrings("n", map.hint(.tree, .move_down));
}

test "empty override disables every default alias and leaves dialogs exclusive" {
    // Disabling quit must remove q, and a modal must not inherit global commands.
    var map = (try Map.load(std.testing.allocator, spec, "[global]\nquit = []\n")).bindings;
    defer map.deinit();
    try std.testing.expectEqual(@as(?Action, null), map.resolve(&.{ .global, .tree }, keymap.vaxisMatcher(vaxis.Key{ .codepoint = 'q' })));
    try std.testing.expectEqualStrings("", map.hint(.global, .quit));
    try std.testing.expectEqual(@as(usize, 0), map.keys(.global, .quit).len);
    var defaults = (try Map.load(std.testing.allocator, spec, null)).bindings;
    defer defaults.deinit();
    try std.testing.expectEqual(@as(?Action, null), defaults.resolve(&.{.dialog}, keymap.vaxisMatcher(vaxis.Key{ .codepoint = 'q' })));
    try std.testing.expectEqual(Action.cancel, defaults.resolve(&.{.dialog}, keymap.vaxisMatcher(vaxis.Key{ .codepoint = vaxis.Key.escape })).?);
}

test "invalid overrides return owned diagnostics" {
    // Silent acceptance of misspelled actions or collisions can strand users in the TUI.
    const cases = [_]struct { text: []const u8, kind: keymap.Diagnostic.Kind }{
        .{ .text = "[unknown]\nx=[]", .kind = .unknown_context },
        .{ .text = "[tree]\nunknown_action=[]", .kind = .unknown_action },
        .{ .text = "[tree]\nmove_up=1", .kind = .invalid_type },
        .{ .text = "[tree]\nmove_up=[1]", .kind = .invalid_type },
        .{ .text = "[tree]\nmove_up=[\"Ctrl+Ctrl+x\"]", .kind = .invalid_key },
        .{ .text = "[tree]\nmove_up=[]\nmove_up=[]", .kind = .syntax },
        .{ .text = "[tree]\nmove_up=[\"j\"]", .kind = .collision },
        .{ .text = "[global]\nquit=[\"j\"]", .kind = .collision },
        .{ .text = "[global]\nquit=[\"Shift+j\"]\n[tree]\nmove_up=[\"J\"]", .kind = .collision },
    };
    for (cases) |case| {
        const diagnostic = (try Map.load(std.testing.allocator, spec, case.text)).invalid;
        try std.testing.expectEqual(case.kind, diagnostic.kind);
        try std.testing.expect(diagnostic.message().len != 0);
    }
    const syntax = (try Map.load(std.testing.allocator, spec, "[tree]\nmove_up = [\n")).invalid;
    try std.testing.expect(syntax.line.? >= 2);
    try std.testing.expect(syntax.column.? >= 1);
    try std.testing.expect(syntax.message().len != 0);
}

test "key expressions preserve Unicode and reject malformed names" {
    // A character's case is meaningful; modifier and named-key spelling is not.
    try std.testing.expectEqual(keymap.KeySpec{ .key = .{ .character = 'あ' }, .modifiers = .{ .ctrl = true } }, try keymap.KeySpec.parse("cTrL+あ"));
    try std.testing.expectEqual(keymap.KeySpec{ .key = .{ .named = .page_down } }, try keymap.KeySpec.parse("pagedown"));
    try std.testing.expectEqual(keymap.KeySpec{ .key = .{ .character = '+' } }, try keymap.KeySpec.parse("+"));
    try std.testing.expectEqual(keymap.KeySpec{ .key = .{ .character = '+' }, .modifiers = .{ .ctrl = true } }, try keymap.KeySpec.parse("Ctrl++"));
    for ([_][]const u8{ "", "Ctrl+", "Ctrl+Ctrl+x", "Unknown+x", "word", "\xff", "a\xcc\x81" }) |text| {
        try std.testing.expectError(error.InvalidKey, keymap.KeySpec.parse(text));
    }
}

test "real terminal encodings retain matching and deterministic declaration order" {
    // Kitty and legacy terminals report Shift differently; textual key matching must remain native.
    var map = (try Map.load(std.testing.allocator, spec, "[tree]\nmove_down=[\"Shift+v\",\"V\",\":\"]\nmove_up=[\"Shift+;\"]\n")).bindings;
    defer map.deinit();
    for ([_]vaxis.Key{
        .{ .codepoint = 'v', .mods = .{ .shift = true } },
        .{ .codepoint = 'V' },
        .{ .codepoint = 'v', .shifted_codepoint = 'V', .mods = .{ .shift = true } },
        .{ .codepoint = ':', .text = ":" },
    }) |key| try std.testing.expectEqual(Action.move_down, map.resolve(&.{.tree}, keymap.vaxisMatcher(key)).?);
    try std.testing.expectEqualStrings("Shift+v", map.hint(.tree, .move_down));
    try std.testing.expectEqual(@as(?Action, null), map.resolve(&.{.tree}, keymap.vaxisMatcher(vaxis.Key{ .codepoint = 'v' })));
}
