const std = @import("std");
const testing = std.testing;
const keymap = @import("keymap");
const Key = @import("vaxis").Key;

test "sequence defaults load without firing on the first key" {
    // A partial sequence must not invoke an action through the single-event API.
    const Map = keymap.Bindings(enum { list }, enum { top });
    const loaded = try Map.load(testing.allocator, .{
        .defaults = &.{.{ .context = .list, .action = .top, .keys = &.{"g g"} }},
        .context_groups = &.{},
    }, null);
    try testing.expect(loaded == .bindings);
    var map = loaded.bindings;
    defer map.deinit();
    try testing.expect(map.resolve(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'g' })) == null);
}

test "sequence resolver completes shared prefixes and preserves single shortcuts" {
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
    var resolver = try map.sequenceResolver(testing.allocator, .{ .timeout_ms = 100 });
    defer resolver.deinit();
    try testing.expect(resolver.feed(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'g' }), 0) == .pending);
    try testing.expectEqual(Action.end, resolver.feed(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'e' }), 1).action);
    try testing.expect(resolver.feed(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'g' }), 2) == .pending);
    try testing.expectEqual(Action.top, resolver.feed(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'g' }), 3).action);
    try testing.expectEqual(Action.quit, resolver.feed(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'q' }), 4).action);
    try testing.expectEqualStrings("g g", map.hint(.list, .top));
    try testing.expectEqual(@as(usize, 2), map.sequences(.list, .top)[0].keys.len);
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
    var resolver = try map.sequenceResolver(testing.allocator, .{ .timeout_ms = 10 });
    defer resolver.deinit();
    const prefix = keymap.vaxisMatcher(Key{ .codepoint = 'b', .mods = .{ .ctrl = true } });
    try testing.expect(resolver.feed(&.{.list}, prefix, 0) == .pending);
    resolver.cancel();
    try testing.expect(resolver.feed(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'n' }), 1) == .none);
    try testing.expect(resolver.feed(&.{.list}, prefix, 2) == .pending);
    try testing.expect(resolver.advance(&.{.list}, 11) == .pending);
    try testing.expect(resolver.advance(&.{.list}, 12) == .none);
    try testing.expect(resolver.feed(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'n' }), 13) == .none);
    try testing.expect(resolver.feed(&.{.list}, prefix, 14) == .pending);
    try testing.expect(resolver.advance(&.{.dialog}, 15) == .none);
    try testing.expect(resolver.feed(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'n' }), 16) == .none);
    try testing.expect(resolver.feed(&.{.list}, prefix, 17) == .pending);
    try testing.expectEqual(Action.quit, resolver.feed(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'q' }), 18).action);
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
    try testing.expectEqual(@as(usize, 0), map.sequences(.list, .quit).len);
    const prefix = (try Map.load(testing.allocator, definition,
        \\{"list":{"next":["g"]}}
    )).invalid;
    try testing.expectEqual(keymap.Diagnostic.Kind.collision, prefix.kind);
    const exact = (try Map.load(testing.allocator, definition,
        \\{"list":{"next":["g g"]}}
    )).invalid;
    try testing.expectEqual(keymap.Diagnostic.Kind.collision, exact.kind);
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
    var resolver = try map.sequenceResolver(testing.allocator, .{ .timeout_ms = 10 });
    defer resolver.deinit();
    try testing.expect(resolver.feed(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'g' }), 0) == .pending);
    // Repeating a context must not consume one event as two sequence steps.
    try testing.expect(resolver.feed(&.{ .list, .list }, keymap.vaxisMatcher(Key{ .codepoint = 'g' }), 9) == .pending);
    try testing.expect(resolver.advance(&.{.list}, 10) == .pending);
    try testing.expectEqual(Action.command, resolver.feed(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'e' }), 18).action);
    try testing.expectEqual(Action.space, map.resolve(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = ' ', .mods = .{ .ctrl = true } })).?);
}

test "sequence steps expand Mod and aliases for each selected platform" {
    // Platform expansion must apply to every shortcut step in defaults and overrides.
    const Action = enum { next };
    const Map = keymap.Bindings(enum { list }, Action);
    const definition: Map.Definition = .{
        .defaults = &.{.{ .context = .list, .action = .next, .keys = &.{"Mod+Option+b n"} }},
        .context_groups = &.{},
    };
    var mac = (try Map.loadWithOptions(testing.allocator, definition, null, .{ .platform = .macos, .display_style = .macos })).bindings;
    defer mac.deinit();
    try testing.expectEqualStrings("Option+Command+b n", mac.hint(.list, .next));
    var resolver = try mac.sequenceResolver(testing.allocator, .{ .timeout_ms = null });
    defer resolver.deinit();
    try testing.expect(resolver.feed(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'b', .mods = .{ .alt = true, .super = true } }), 0) == .pending);
    try testing.expect(resolver.advance(&.{.list}, 100000) == .pending);
    try testing.expectEqual(Action.next, resolver.feed(&.{.list}, keymap.vaxisMatcher(Key{ .codepoint = 'n' }), 100001).action);
    var windows = (try Map.loadWithOptions(testing.allocator, definition,
        \\{"list":{"next":["Mod+Opt+b n"]}}
    , .{ .platform = .windows, .display_style = .windows })).bindings;
    defer windows.deinit();
    try testing.expectEqualStrings("Ctrl+Alt+b n", windows.hint(.list, .next));
    try testing.expectEqual(keymap.Keyboard{ .key = .{ .character = 'b' }, .modifiers = .{ .ctrl = true, .alt = true } }, windows.sequences(.list, .next)[0].keys[0]);
    var linux = (try Map.loadWithOptions(testing.allocator, definition, null, .{ .platform = .linux, .display_style = .common })).bindings;
    defer linux.deinit();
    try testing.expectEqualStrings("Ctrl+Alt+b n", linux.hint(.list, .next));
    try testing.expectEqual(keymap.Keyboard{ .key = .{ .character = 'b' }, .modifiers = .{ .ctrl = true, .alt = true } }, linux.sequences(.list, .next)[0].keys[0]);
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
