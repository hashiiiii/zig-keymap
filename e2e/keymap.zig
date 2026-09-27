const std = @import("std");
const testing = std.testing;
const keymap = @import("keymap");
const Key = @import("vaxis").Key;

test "partial configuration resolves native keys and keeps modal actions exclusive" {
    // Partial overrides must preserve defaults, including shortcuts reused by modal actions.
    const Context = enum { global, tree, dialog };
    const Action = enum { quit, move_down, move_up, cancel };
    const Map = keymap.Bindings(Context, Action);
    var map = (try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .global, .action = .quit, .keys = &.{"q"} },
            .{ .context = .tree, .action = .move_down, .keys = &.{ "Down", "j" } },
            .{ .context = .tree, .action = .move_up, .keys = &.{"Up"} },
            .{ .context = .dialog, .action = .cancel, .keys = &.{ "q", "Escape" } },
        },
        .context_groups = &.{ &.{ .global, .tree }, &.{.dialog} },
    },
        \\{"tree": {"move_down": ["Ctrl+n"]}}
    )).bindings;
    defer map.deinit();

    try testing.expectEqual(Action.move_down, map.resolve(&.{ .global, .tree }, keymap.vaxisMatcher(Key{ .codepoint = 'n', .mods = .{ .ctrl = true } })).?);
    try testing.expectEqual(@as(?Action, null), map.resolve(&.{.tree}, keymap.vaxisMatcher(Key{ .codepoint = 'j' })));
    try testing.expectEqual(@as(?Action, null), map.resolve(&.{.tree}, keymap.vaxisMatcher(Key{ .codepoint = Key.down })));
    try testing.expectEqual(Action.quit, map.resolve(&.{ .global, .tree }, keymap.vaxisMatcher(Key{ .codepoint = 'q' })).?);
    try testing.expectEqual(Action.move_up, map.resolve(&.{.tree}, keymap.vaxisMatcher(Key{ .codepoint = Key.up })).?);
    try testing.expectEqual(Action.cancel, map.resolve(&.{.dialog}, keymap.vaxisMatcher(Key{ .codepoint = 'q' })).?);
    try testing.expectEqual(Action.cancel, map.resolve(&.{.dialog}, keymap.vaxisMatcher(Key{ .codepoint = Key.escape })).?);
    try testing.expectEqualStrings("Ctrl+n", map.hint(.tree, .move_down));
    try testing.expectEqualStrings("Up", map.hint(.tree, .move_up));
}

test "empty overrides disable every alias and clear the hint" {
    // Disabling an action must remove all its shortcuts and its displayed hint.
    const Action = enum { move_down };
    const Map = keymap.Bindings(enum { tree }, Action);
    var map = (try Map.load(testing.allocator, .{
        .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{ "Down", "j" } }},
        .context_groups = &.{},
    },
        \\{"tree": {"move_down": []}}
    )).bindings;
    defer map.deinit();

    try testing.expectEqual(@as(?Action, null), map.resolve(&.{.tree}, keymap.vaxisMatcher(Key{ .codepoint = 'j' })));
    try testing.expectEqual(@as(?Action, null), map.resolve(&.{.tree}, keymap.vaxisMatcher(Key{ .codepoint = Key.down })));
    try testing.expectEqual(@as(usize, 0), map.keys(.tree, .move_down).len);
    try testing.expectEqualStrings("", map.hint(.tree, .move_down));
}

test "native matching overlaps resolve in active context order" {
    // A colon can also match Shift+semicolon, so the caller's context order must decide.
    const Action = enum { quit, move_down };
    const Map = keymap.Bindings(enum { global, tree }, Action);
    var map = (try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .global, .action = .quit, .keys = &.{":"} },
            .{ .context = .tree, .action = .move_down, .keys = &.{"Shift+;"} },
        },
        .context_groups = &.{&.{ .global, .tree }},
    }, null)).bindings;
    defer map.deinit();

    try testing.expectEqual(Action.quit, map.resolve(&.{ .global, .tree }, keymap.vaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } })).?);
    try testing.expectEqual(Action.move_down, map.resolve(&.{ .tree, .global }, keymap.vaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } })).?);
}

test "native matching overlaps resolve in default declaration order" {
    // Action enum order must not override the application's declared binding priority.
    const Action = enum { move_down, move_up };
    const Map = keymap.Bindings(enum { tree }, Action);
    var map = (try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .tree, .action = .move_up, .keys = &.{"Shift+;"} },
            .{ .context = .tree, .action = .move_down, .keys = &.{":"} },
        },
        .context_groups = &.{},
    }, null)).bindings;
    defer map.deinit();

    try testing.expectEqual(Action.move_up, map.resolve(&.{.tree}, keymap.vaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } })).?);
}

test "platform modifier aliases collide across overlapping contexts" {
    // A platform spelling must not let an override shadow an active default binding.
    const Map = keymap.Bindings(enum { global, tree }, enum { quit, move_down });
    const result = try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .global, .action = .quit, .keys = &.{"Alt+k"} },
            .{ .context = .tree, .action = .move_down, .keys = &.{"j"} },
        },
        .context_groups = &.{&.{ .global, .tree }},
    },
        \\{"tree": {"move_down": ["Option+k"]}}
    );
    switch (result) {
        .invalid => |diagnostic| try testing.expectEqual(keymap.Diagnostic.Kind.collision, diagnostic.kind),
        .bindings => |bindings| {
            var map = bindings;
            defer map.deinit();
            return error.TestUnexpectedResult;
        },
    }
}
