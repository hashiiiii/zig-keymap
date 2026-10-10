const std = @import("std");
const testing = std.testing;
const keymap = @import("keymap");
const Key = @import("vaxis").Key;

test "JSON overrides select actions in active contexts" {
    // Overrides must replace aliases without changing other actions or modal bindings.
    const Context = enum { global, list, dialog };
    const Action = enum { quit, down, up, cancel };
    const Map = keymap.Bindings(Context, Action);
    var bindings = try Map.load(testing.allocator, &.{
        .{ .context = .global, .action = .quit, .keys = &.{"q"} },
        .{ .context = .list, .action = .down, .keys = &.{ "Down", "j" } },
        .{ .context = .list, .action = .up, .keys = &.{"Up"} },
        .{ .context = .dialog, .action = .cancel, .keys = &.{ "q", "Escape" } },
    },
        \\{"list": {"down": ["Ctrl+n"]}}
    );
    defer bindings.deinit();

    try testing.expectEqual(Action.down, bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'n', .mods = .{ .ctrl = true } })).action);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'j' })) == .none);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = Key.down })) == .none);
    try testing.expectEqual(Action.quit, bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'q' })).action);
    try testing.expectEqual(Action.up, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = Key.up })).action);
    try testing.expectEqual(Action.cancel, bindings.receive(&.{.dialog}, keymap.libvaxisMatcher(Key{ .codepoint = 'q' })).action);
    try testing.expectEqual(Action.cancel, bindings.receive(&.{.dialog}, keymap.libvaxisMatcher(Key{ .codepoint = Key.escape })).action);
}

test "input streams keep pending keys separate" {
    // A prefix typed in one window must not complete a sequence in another.
    const Action = enum { top };
    const Map = keymap.Bindings(enum { list }, Action);
    const defaults: []const Map.Default = &.{
        .{ .context = .list, .action = .top, .keys = &.{"g g"} },
    };
    var first = try Map.load(testing.allocator, defaults, null);
    defer first.deinit();
    var second = try Map.load(testing.allocator, defaults, null);
    defer second.deinit();
    const g = keymap.libvaxisMatcher(Key{ .codepoint = 'g' });

    try testing.expect(first.receive(&.{.list}, g) == .pending);
    try testing.expect(second.receive(&.{.list}, g) == .pending);
    try testing.expectEqual(Action.top, first.receive(&.{.list}, g).action);
    try testing.expectEqual(Action.top, second.receive(&.{.list}, g).action);
}

test "bindings receive single keys and sequences" {
    // One input method must handle both binding lengths.
    const Action = enum { top, end, quit };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .top, .keys = &.{"g g"} },
        .{ .context = .list, .action = .end, .keys = &.{"g e"} },
        .{ .context = .list, .action = .quit, .keys = &.{"q"} },
    }, null);
    defer bindings.deinit();

    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'g' })) == .pending);
    try testing.expectEqual(Action.end, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'e' })).action);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'g' })) == .pending);
    try testing.expectEqual(Action.top, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'g' })).action);
    try testing.expectEqual(Action.quit, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'q' })).action);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })) == .none);
}

test "cancellation inactive contexts and mismatches clear pending keys" {
    // Stale prefixes must not run actions after focus changes or unrelated input.
    const Action = enum { next, quit };
    const Map = keymap.Bindings(enum { list, dialog }, Action);
    var bindings = try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .next, .keys = &.{"Ctrl+b n"} },
        .{ .context = .list, .action = .quit, .keys = &.{"q"} },
    }, null);
    defer bindings.deinit();
    const prefix = keymap.libvaxisMatcher(Key{ .codepoint = 'b', .mods = .{ .ctrl = true } });
    const n = keymap.libvaxisMatcher(Key{ .codepoint = 'n' });

    try testing.expect(bindings.receive(&.{.list}, prefix) == .pending);
    bindings.cancel();
    try testing.expect(bindings.receive(&.{.list}, n) == .none);
    try testing.expect(bindings.receive(&.{.list}, prefix) == .pending);
    try testing.expect(bindings.receive(&.{.dialog}, n) == .none);
    try testing.expect(bindings.receive(&.{.list}, n) == .none);
    try testing.expect(bindings.receive(&.{.list}, prefix) == .pending);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })) == .none);
    try testing.expect(bindings.receive(&.{.list}, n) == .none);
    try testing.expect(bindings.receive(&.{.list}, prefix) == .pending);
    try testing.expectEqual(Action.quit, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'q' })).action);
}

test "three-step sequences consume each event once" {
    // Repeating a context must not consume one event as multiple sequence steps.
    const Action = enum { command, space };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .command, .keys = &.{"g g e"} },
        .{ .context = .list, .action = .space, .keys = &.{"Ctrl+ "} },
    }, null);
    defer bindings.deinit();

    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'g' })) == .pending);
    try testing.expect(bindings.receive(&.{ .list, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'g' })) == .pending);
    try testing.expectEqual(Action.command, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'e' })).action);
    try testing.expectEqual(Action.space, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = ' ', .mods = .{ .ctrl = true } })).action);
}

test "native sequence overlaps follow context priority" {
    // A native short match must wait for an earlier pending sequence.
    const Action = enum { long, short };
    const Map = keymap.Bindings(enum { global, list }, Action);
    var bindings = try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .short, .keys = &.{": x"} },
        .{ .context = .global, .action = .long, .keys = &.{"Shift+; x y"} },
    }, null);
    defer bindings.deinit();
    const colon = keymap.libvaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } });

    try testing.expect(bindings.receive(&.{ .global, .list }, colon) == .pending);
    try testing.expect(bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })) == .pending);
    try testing.expectEqual(Action.long, bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'y' })).action);
    try testing.expect(bindings.receive(&.{ .list, .global }, colon) == .pending);
    try testing.expectEqual(Action.short, bindings.receive(&.{ .list, .global }, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })).action);
}

test "native sequence overlaps follow declaration priority" {
    // Action enum order must not change the application's declared priority.
    const Action = enum { short, long };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .long, .keys = &.{"Shift+; x y"} },
        .{ .context = .list, .action = .short, .keys = &.{": x"} },
    }, null);
    defer bindings.deinit();

    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } })) == .pending);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })) == .pending);
    try testing.expectEqual(Action.long, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'y' })).action);
}

test "empty overrides disable every alias" {
    // Disabling an action must remove every default key.
    const Map = keymap.Bindings(enum { list }, enum { down });
    var bindings = try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .down, .keys = &.{ "Down", "j" } },
    },
        \\{"list": {"down": []}}
    );
    defer bindings.deinit();

    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'j' })) == .none);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = Key.down })) == .none);
}

test "JSON sequences accept modifier aliases and Unicode" {
    // OS-specific spellings must work without OS selection in the API.
    const Action = enum { next };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .next, .keys = &.{} },
    },
        \\{"list": {"next": ["Cmd+あ Option+n", "Win+あ Alt+n"]}}
    );
    defer bindings.deinit();

    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'あ', .mods = .{ .super = true } })) == .pending);
    try testing.expectEqual(Action.next, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'n', .mods = .{ .alt = true } })).action);
}

test "shared keys follow active context order" {
    // Context priority replaces a separate declaration of which screens can overlap.
    const Action = enum { quit, cancel };
    const Map = keymap.Bindings(enum { global, dialog }, Action);
    var bindings = try Map.load(testing.allocator, &.{
        .{ .context = .global, .action = .quit, .keys = &.{"Cmd+q"} },
        .{ .context = .dialog, .action = .cancel, .keys = &.{"Super+q"} },
    }, null);
    defer bindings.deinit();
    const q = keymap.libvaxisMatcher(Key{ .codepoint = 'q', .mods = .{ .super = true } });

    try testing.expectEqual(Action.quit, bindings.receive(&.{ .global, .dialog }, q).action);
    try testing.expectEqual(Action.cancel, bindings.receive(&.{ .dialog, .global }, q).action);
}

test "native single-key overlaps follow declaration priority" {
    // A colon can also match Shift+semicolon under native matching rules.
    const Action = enum { down, up };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .up, .keys = &.{"Shift+;"} },
        .{ .context = .list, .action = .down, .keys = &.{":"} },
    }, null);
    defer bindings.deinit();

    try testing.expectEqual(Action.up, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } })).action);
}
