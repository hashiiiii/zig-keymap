const std = @import("std");
const testing = std.testing;
const keymap = @import("keymap");
const Key = @import("vaxis").Key;

test "windows keep pending keys separate" {
    // A key in one window must not complete a shortcut started in another.
    const Map = keymap.Bindings(enum { list }, enum { top });
    var bindings = (try Map.load(testing.allocator, .{
        .defaults = &.{.{ .context = .list, .action = .top, .keys = &.{"g g"} }},
        .context_groups = &.{},
    }, null)).bindings;
    defer bindings.deinit();

    var first = try bindings.receiver(testing.allocator, .{});
    defer first.deinit();
    var second = try bindings.receiver(testing.allocator, .{});
    defer second.deinit();

    const g = keymap.vaxisMatcher(Key{ .codepoint = 'g' });
    try testing.expect(first.receive(&.{.list}, g, 0) == .pending);
    try testing.expect(second.receive(&.{.list}, g, 1) == .pending);
    try testing.expectEqual(@as(Map.Receiver.Result, .{ .action = .top }), first.receive(&.{.list}, g, 2));
    try testing.expectEqual(@as(Map.Receiver.Result, .{ .action = .top }), second.receive(&.{.list}, g, 3));
}

test "one receiver matches single keys and sequences" {
    // Tracking all matching prefixes keeps g g and g e independently reachable.
    const Action = enum { top, end, quit };
    const Map = keymap.Bindings(enum { list }, Action);
    var map = (try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .list, .action = .top, .keys = &.{"g g"} },
            .{ .context = .list, .action = .end, .keys = &.{"g e"} },
            .{ .context = .list, .action = .quit, .keys = &.{"q"} },
        },
        .context_groups = &.{},
    }, null)).bindings;
    defer map.deinit();
    var receiver = try map.receiver(testing.allocator, .{ .timeout_ms = 100 });
    defer receiver.deinit();
    try testing.expect(receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'g' }), 0) == .pending);
    try testing.expectEqual(Action.end, receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'e' }), 1).action);
    try testing.expect(receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'g' }), 2) == .pending);
    try testing.expectEqual(Action.top, receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'g' }), 3).action);
    try testing.expectEqual(Action.quit, receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'q' }), 4).action);
    try testing.expectEqualStrings("g g", map.hint(.list, .top));
    try testing.expectEqual(@as(usize, 2), map.keys(.list, .top)[0].len);
    try testing.expectEqual(@as(usize, 1), map.keys(.list, .quit)[0].len);
}

test "cancellation timeout context removal and mismatch clear pending input" {
    // Stale prefixes must not fire after navigation, cancellation, or a typing pause.
    const Action = enum { next, quit };
    const Map = keymap.Bindings(enum { list, dialog }, Action);
    var map = (try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .list, .action = .next, .keys = &.{"Ctrl+b n"} },
            .{ .context = .list, .action = .quit, .keys = &.{"q"} },
        },
        .context_groups = &.{},
    }, null)).bindings;
    defer map.deinit();
    var receiver = try map.receiver(testing.allocator, .{ .timeout_ms = 10 });
    defer receiver.deinit();
    const prefix = keymap.vaxisMatcher(Key{ .codepoint = 'b', .mods = .{ .ctrl = true } });
    try testing.expect(receiver.receive(&.{.list}, prefix, 0) == .pending);
    receiver.cancel();
    try testing.expect(receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'n' }), 1) == .none);
    try testing.expect(receiver.receive(&.{.list}, prefix, 2) == .pending);
    try testing.expect(receiver.advance(&.{.list}, 11) == .pending);
    try testing.expect(receiver.advance(&.{.list}, 12) == .none);
    try testing.expect(receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'n' }), 13) == .none);
    try testing.expect(receiver.receive(&.{.list}, prefix, 14) == .pending);
    try testing.expect(receiver.advance(&.{.dialog}, 15) == .none);
    try testing.expect(receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'n' }), 16) == .none);
    try testing.expect(receiver.receive(&.{.list}, prefix, 17) == .pending);
    try testing.expectEqual(Action.quit, receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'q' }), 18).action);
}

test "sequence overrides preserve omitted defaults and reject action prefixes" {
    // Arrays replace shortcuts; ambiguous action prefixes cannot wait for a reliable exact match.
    const Map = keymap.Bindings(enum { list }, enum { top, next, quit });
    const definition: Map.Definition = .{
        .defaults = &.{
            .{ .context = .list, .action = .top, .keys = &.{"g g"} },
            .{ .context = .list, .action = .next, .keys = &.{"Ctrl+b n"} },
            .{ .context = .list, .action = .quit, .keys = &.{"q"} },
        },
        .context_groups = &.{},
    };
    var map = (try Map.load(testing.allocator, definition,
        \\{"list":{"next":["g n"],"quit":[]}}
    )).bindings;
    defer map.deinit();
    try testing.expectEqualStrings("g g", map.hint(.list, .top));
    try testing.expectEqualStrings("g n", map.hint(.list, .next));
    try testing.expectEqual(@as(usize, 0), map.keys(.list, .quit).len);
    const prefix = (try Map.load(testing.allocator, definition,
        \\{"list":{"next":["g"]}}
    )).invalid;
    try testing.expectEqual(keymap.Diagnostic.Kind.collision, prefix.kind);
    const exact = (try Map.load(testing.allocator, definition,
        \\{"list":{"next":["g g"]}}
    )).invalid;
    try testing.expectEqual(keymap.Diagnostic.Kind.collision, exact.kind);
    const alias_prefix = (try Map.load(testing.allocator, definition,
        \\{"list":{"top":["g","g g"]}}
    )).invalid;
    try testing.expectEqual(keymap.Diagnostic.Kind.collision, alias_prefix.kind);
    var disabled = (try Map.load(testing.allocator, definition,
        \\{"list":{"top":[],"next":[]}}
    )).bindings;
    defer disabled.deinit();
    var receiver = try disabled.receiver(testing.allocator, .{});
    defer receiver.deinit();
    try testing.expectEqualStrings("", disabled.hint(.list, .top));
    try testing.expect(receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'g' }), 0) == .none);
}

test "three-step sequences restart timeouts and preserve literal space shortcuts" {
    // Each matched step extends the deadline, while existing literal Space syntax stays usable.
    const Action = enum { command, space };
    const Map = keymap.Bindings(enum { list }, Action);
    var map = (try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .list, .action = .command, .keys = &.{"g g e"} },
            .{ .context = .list, .action = .space, .keys = &.{"Ctrl+ "} },
        },
        .context_groups = &.{},
    }, null)).bindings;
    defer map.deinit();
    var receiver = try map.receiver(testing.allocator, .{ .timeout_ms = 10 });
    defer receiver.deinit();
    try testing.expect(receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'g' }), 0) == .pending);
    // Repeating a context must not consume one event as two sequence steps.
    try testing.expect(receiver.receive(&.{ .list, .list }, keymap.vaxisMatcher(Key{ .codepoint = 'g' }), 9) == .pending);
    try testing.expect(receiver.advance(&.{.list}, 10) == .pending);
    try testing.expectEqual(Action.command, receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'e' }), 18).action);
    try testing.expectEqual(Action.space, receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = ' ', .mods = .{ .ctrl = true } }), 19).action);
}

test "sequence steps expand Mod and aliases for each selected platform" {
    // Platform expansion must apply to every shortcut step in defaults and overrides.
    const Action = enum { next };
    const Map = keymap.Bindings(enum { list }, Action);
    // Consumers must be able to refer to the public `ModifierName` type.
    const modifier_name: keymap.ModifierName = .macos;
    const definition: Map.Definition = .{
        .defaults = &.{.{ .context = .list, .action = .next, .keys = &.{"Mod+Option+b Mod+n"} }},
        .context_groups = &.{},
    };
    var mac = (try Map.loadWithOptions(testing.allocator, definition, null, .{ .platform = .macos, .modifier_name = modifier_name })).bindings;
    defer mac.deinit();
    try testing.expectEqualStrings("Option+Command+b Command+n", mac.hint(.list, .next));
    var receiver = try mac.receiver(testing.allocator, .{ .timeout_ms = null });
    defer receiver.deinit();
    try testing.expect(receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'b', .mods = .{ .alt = true, .super = true } }), 0) == .pending);
    try testing.expect(receiver.advance(&.{.list}, 100000) == .pending);
    try testing.expectEqual(Action.next, receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'n', .mods = .{ .super = true } }), 100001).action);
    var windows = (try Map.loadWithOptions(testing.allocator, definition,
        \\{"list":{"next":["Mod+Opt+b Mod+n"]}}
    , .{ .platform = .windows, .modifier_name = .windows })).bindings;
    defer windows.deinit();
    try testing.expectEqualStrings("Ctrl+Alt+b Ctrl+n", windows.hint(.list, .next));
    try testing.expectEqual(keymap.KeyPress{ .key = .{ .character = 'n' }, .modifiers = .{ .ctrl = true } }, windows.keys(.list, .next)[0][1]);
    var linux = (try Map.loadWithOptions(testing.allocator, definition, null, .{ .platform = .linux, .modifier_name = .common })).bindings;
    defer linux.deinit();
    try testing.expectEqualStrings("Ctrl+Alt+b Ctrl+n", linux.hint(.list, .next));
    try testing.expectEqual(keymap.KeyPress{ .key = .{ .character = 'n' }, .modifiers = .{ .ctrl = true } }, linux.keys(.list, .next)[0][1]);
}

test "native sequence prefixes retain active context priority" {
    // A layout-dependent short match must not interrupt a higher-priority pending sequence.
    const Action = enum { long, short };
    const Map = keymap.Bindings(enum { global, list }, Action);
    var map = (try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .list, .action = .short, .keys = &.{": x"} },
            .{ .context = .global, .action = .long, .keys = &.{"Shift+; x y"} },
        },
        .context_groups = &.{&.{ .global, .list }},
    }, null)).bindings;
    defer map.deinit();
    var receiver = try map.receiver(testing.allocator, .{});
    defer receiver.deinit();
    const colon = keymap.vaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } });
    try testing.expect(receiver.receive(&.{ .global, .list }, colon, 0) == .pending);
    try testing.expect(receiver.receive(&.{ .global, .list }, keymap.vaxisMatcher(Key{ .codepoint = 'x' }), 1) == .pending);
    try testing.expectEqual(Action.long, receiver.receive(&.{ .global, .list }, keymap.vaxisMatcher(Key{ .codepoint = 'y' }), 2).action);
    try testing.expect(receiver.receive(&.{ .list, .global }, colon, 3) == .pending);
    try testing.expectEqual(Action.short, receiver.receive(&.{ .list, .global }, keymap.vaxisMatcher(Key{ .codepoint = 'x' }), 4).action);
}

test "native sequence prefixes retain default declaration priority" {
    // Enum order must not replace the application's declared priority for native overlaps.
    const Action = enum { short, long };
    const Map = keymap.Bindings(enum { list }, Action);
    var map = (try Map.load(testing.allocator, .{
        .defaults = &.{
            .{ .context = .list, .action = .long, .keys = &.{"Shift+; x y"} },
            .{ .context = .list, .action = .short, .keys = &.{": x"} },
        },
        .context_groups = &.{},
    }, null)).bindings;
    defer map.deinit();
    var receiver = try map.receiver(testing.allocator, .{});
    defer receiver.deinit();
    try testing.expect(receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } }), 0) == .pending);
    try testing.expect(receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'x' }), 1) == .pending);
    try testing.expectEqual(Action.long, receiver.receive(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'y' }), 2).action);
}

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

    var receiver = try map.receiver(testing.allocator, .{});
    defer receiver.deinit();
    try testing.expectEqual(Action.move_down, receiver.receive(&.{ .global, .tree }, keymap.vaxisMatcher(Key{ .codepoint = 'n', .mods = .{ .ctrl = true } }), 0).action);
    try testing.expect(receiver.receive(&.{.tree}, keymap.vaxisMatcher(Key{ .codepoint = 'j' }), 1) == .none);
    try testing.expect(receiver.receive(&.{.tree}, keymap.vaxisMatcher(Key{ .codepoint = Key.down }), 2) == .none);
    try testing.expectEqual(Action.quit, receiver.receive(&.{ .global, .tree }, keymap.vaxisMatcher(Key{ .codepoint = 'q' }), 3).action);
    try testing.expectEqual(Action.move_up, receiver.receive(&.{.tree}, keymap.vaxisMatcher(Key{ .codepoint = Key.up }), 4).action);
    try testing.expectEqual(Action.cancel, receiver.receive(&.{.dialog}, keymap.vaxisMatcher(Key{ .codepoint = 'q' }), 5).action);
    try testing.expectEqual(Action.cancel, receiver.receive(&.{.dialog}, keymap.vaxisMatcher(Key{ .codepoint = Key.escape }), 6).action);
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

    var receiver = try map.receiver(testing.allocator, .{});
    defer receiver.deinit();
    try testing.expect(receiver.receive(&.{.tree}, keymap.vaxisMatcher(Key{ .codepoint = 'j' }), 0) == .none);
    try testing.expect(receiver.receive(&.{.tree}, keymap.vaxisMatcher(Key{ .codepoint = Key.down }), 1) == .none);
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

    var receiver = try map.receiver(testing.allocator, .{});
    defer receiver.deinit();
    try testing.expectEqual(Action.quit, receiver.receive(&.{ .global, .tree }, keymap.vaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } }), 0).action);
    try testing.expectEqual(Action.move_down, receiver.receive(&.{ .tree, .global }, keymap.vaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } }), 1).action);
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

    var receiver = try map.receiver(testing.allocator, .{});
    defer receiver.deinit();
    try testing.expectEqual(Action.move_up, receiver.receive(&.{.tree}, keymap.vaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } }), 0).action);
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
