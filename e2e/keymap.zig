const std = @import("std");
const testing = std.testing;
const keymap = @import("keymap");
const Key = @import("vaxis").Key;

test "JSON adds typed pairs and overrides defaults in active contexts" {
    // Defaults must provide initial keys without restricting configurable enum pairs.
    const Context = enum { global, list, dialog };
    const Action = enum { quit, down, up, cancel };
    const Map = keymap.Bindings(Context, Action);
    var bindings = (try Map.load(testing.allocator, &.{
        .{ .context = .global, .action = .quit, .keys = &.{"q"} },
        .{ .context = .list, .action = .down, .keys = &.{ "Down", "j" } },
    },
        \\{"list": {"down": ["Ctrl+n"], "up": ["Up"]}, "dialog": {"cancel": ["q", "Escape"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expectEqual(Action.down, bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'n', .mods = .{ .ctrl = true } })).action);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'j' })) == .none);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = Key.down })) == .none);
    try testing.expectEqual(Action.quit, bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'q' })).action);
    try testing.expectEqual(Action.up, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = Key.up })).action);
    try testing.expectEqual(Action.cancel, bindings.receive(&.{.dialog}, keymap.libvaxisMatcher(Key{ .codepoint = 'q' })).action);
    try testing.expectEqual(Action.cancel, bindings.receive(&.{.dialog}, keymap.libvaxisMatcher(Key{ .codepoint = Key.escape })).action);
}

test "JSON alone assigns typed actions and sequences" {
    // Applications must not repeat configurable pairs in an empty default registry.
    const Action = enum { quit, down, top };
    const Map = keymap.Bindings(enum { global, list }, Action);
    var bindings = (try Map.load(testing.allocator, &.{},
        \\{"global": {"quit": ["Cmd+q"]}, "list": {"down": ["j"], "top": ["g g"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expectEqual(Action.quit, bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'q', .mods = .{ .super = true } })).action);
    try testing.expectEqual(Action.down, bindings.receive(&.{.list}, keymap.KeyPress{ .key = .{ .character = 'j' } }).action);
    try testing.expect(bindings.receive(&.{.global}, keymap.KeyPress{ .key = .{ .character = 'j' } }) == .none);
    const g: keymap.KeyPress = .{ .key = .{ .character = 'g' } };
    try testing.expect(bindings.receive(&.{.list}, g) == .pending);
    try testing.expectEqual(Action.top, bindings.receive(&.{.list}, g).action);
}

test "extended named keys select actions and distinguish keypad input" {
    // Dedicated keypad keys must remain distinct from main-keyboard characters and Enter.
    const Action = enum { function, capture, keypad, main };
    const Map = keymap.Bindings(enum { global }, Action);
    var bindings = (try Map.load(testing.allocator, &.{},
        \\{"global": {"function": ["F13", "F35"], "capture": ["PrintScreen"], "keypad": ["Keypad1", "KeypadEnter"], "main": ["1", "Enter"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expectEqual(Action.function, bindings.receive(&.{.global}, keymap.libvaxisMatcher(Key{ .codepoint = Key.f13 })).action);
    try testing.expectEqual(Action.function, bindings.receive(&.{.global}, keymap.libvaxisMatcher(Key{ .codepoint = Key.f35 })).action);
    try testing.expectEqual(Action.capture, bindings.receive(&.{.global}, keymap.libvaxisMatcher(Key{ .codepoint = Key.print_screen })).action);
    try testing.expectEqual(Action.keypad, bindings.receive(&.{.global}, keymap.libvaxisMatcher(Key{ .codepoint = Key.kp_1 })).action);
    try testing.expectEqual(Action.keypad, bindings.receive(&.{.global}, keymap.libvaxisMatcher(Key{ .codepoint = Key.kp_enter })).action);
    try testing.expectEqual(Action.main, bindings.receive(&.{.global}, keymap.libvaxisMatcher(Key{ .codepoint = '1' })).action);
    try testing.expectEqual(Action.main, bindings.receive(&.{.global}, keymap.libvaxisMatcher(Key{ .codepoint = Key.enter })).action);
}

test "input streams keep pending keys separate" {
    // A prefix typed in one window must not complete a sequence in another.
    const Action = enum { top };
    const Map = keymap.Bindings(enum { list }, Action);
    const defaults: []const Map.Default = &.{
        .{ .context = .list, .action = .top, .keys = &.{"g g"} },
    };
    var first = (try Map.load(testing.allocator, defaults, null)).bindings;
    defer first.deinit();
    var second = (try Map.load(testing.allocator, defaults, null)).bindings;
    defer second.deinit();
    const g = keymap.libvaxisMatcher(Key{ .codepoint = 'g' });

    try testing.expect(first.receive(&.{.list}, g) == .pending);
    try testing.expect(second.receive(&.{.list}, g) == .pending);
    try testing.expectEqual(Action.top, first.receive(&.{.list}, g).action);
    try testing.expectEqual(Action.top, second.receive(&.{.list}, g).action);
}

test "shared sequence prefixes select the matching action" {
    // The next key must select the right action for a shared prefix.
    const Action = enum { top, end };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .top, .keys = &.{"g g"} },
        .{ .context = .list, .action = .end, .keys = &.{"g e"} },
    }, null)).bindings;
    defer bindings.deinit();

    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'g' })) == .pending);
    try testing.expectEqual(Action.end, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'e' })).action);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'g' })) == .pending);
    try testing.expectEqual(Action.top, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'g' })).action);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })) == .none);
}

test "cancellation inactive contexts and mismatches clear pending keys" {
    // Stale prefixes must not run actions after focus changes or unrelated input.
    const Action = enum { next, quit };
    const Map = keymap.Bindings(enum { list, dialog }, Action);
    var bindings = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .next, .keys = &.{"Ctrl+b n"} },
        .{ .context = .list, .action = .quit, .keys = &.{"q"} },
    }, null)).bindings;
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
    const Action = enum { command };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .command, .keys = &.{"g g e"} },
    }, null)).bindings;
    defer bindings.deinit();

    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'g' })) == .pending);
    try testing.expect(bindings.receive(&.{ .list, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'g' })) == .pending);
    try testing.expectEqual(Action.command, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'e' })).action);
}

test "Space works as a key and within a sequence" {
    // Space separates sequence steps, so the named key must remain usable with modifiers.
    const Action = enum { select, next };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .select, .keys = &.{"Space"} },
        .{ .context = .list, .action = .next, .keys = &.{"Ctrl+Space n"} },
    }, null)).bindings;
    defer bindings.deinit();

    try testing.expectEqual(Action.select, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = ' ' })).action);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = ' ', .mods = .{ .ctrl = true } })) == .pending);
    try testing.expectEqual(Action.next, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'n' })).action);
}

test "native single keys yield to higher-priority sequences" {
    // A shared input must start the earlier sequence instead of running a lower-priority action.
    const Action = enum { long, short };
    const Map = keymap.Bindings(enum { global, list }, Action);
    var bindings = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .short, .keys = &.{":"} },
        .{ .context = .global, .action = .long, .keys = &.{"Shift+; x"} },
    }, null)).bindings;
    defer bindings.deinit();
    const colon = keymap.libvaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } });
    const x = keymap.libvaxisMatcher(Key{ .codepoint = 'x' });

    try testing.expect(bindings.receive(&.{ .global, .list }, colon) == .pending);
    try testing.expectEqual(Action.long, bindings.receive(&.{ .global, .list }, x).action);
    try testing.expectEqual(Action.short, bindings.receive(&.{ .list, .global }, colon).action);
    try testing.expect(bindings.receive(&.{ .global, .list }, x) == .none);
}

test "native sequence overlaps follow context priority" {
    // A native short match must wait for an earlier pending sequence.
    const Action = enum { long, short };
    const Map = keymap.Bindings(enum { global, list }, Action);
    var bindings = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .short, .keys = &.{": x"} },
        .{ .context = .global, .action = .long, .keys = &.{"Shift+; x y"} },
    }, null)).bindings;
    defer bindings.deinit();
    const colon = keymap.libvaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } });

    try testing.expect(bindings.receive(&.{ .global, .list }, colon) == .pending);
    try testing.expect(bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })) == .pending);
    try testing.expectEqual(Action.long, bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'y' })).action);
    try testing.expect(bindings.receive(&.{ .global, .list }, colon) == .pending);
    try testing.expectEqual(Action.short, bindings.receive(&.{ .list, .global }, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })).action);
    try testing.expect(bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })) == .none);
}

test "default sequences precede new JSON pairs" {
    // JSON-only actions must follow the application's default priority, regardless of enum order.
    const Action = enum { short, long };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .long, .keys = &.{"Shift+; x y"} },
    },
        \\{"list": {"short": [": x"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } })) == .pending);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })) == .pending);
    try testing.expectEqual(Action.long, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'y' })).action);
}

test "empty overrides disable every alias" {
    // Disabling an action must remove every default key.
    const Map = keymap.Bindings(enum { list }, enum { down });
    var bindings = (try Map.load(testing.allocator, &.{
        .{ .context = .list, .action = .down, .keys = &.{ "Down", "j" } },
    },
        \\{"list": {"down": []}}
    )).bindings;
    defer bindings.deinit();

    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'j' })) == .none);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = Key.down })) == .none);
}

test "JSON sequences accept modifier aliases and Unicode" {
    // OS-specific spellings must work without OS selection in the API.
    const Action = enum { next };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator, &.{},
        \\{"list": {"next": ["Cmd+あ Option+n", "Win+あ Alt+n"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'あ', .mods = .{ .super = true } })) == .pending);
    try testing.expectEqual(Action.next, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'n', .mods = .{ .alt = true } })).action);
}

test "shared keys follow active context order" {
    // Shared keys must follow the application's active context order.
    const Action = enum { quit, cancel };
    const Map = keymap.Bindings(enum { global, dialog }, Action);
    var bindings = (try Map.load(testing.allocator, &.{
        .{ .context = .global, .action = .quit, .keys = &.{"Cmd+q"} },
        .{ .context = .dialog, .action = .cancel, .keys = &.{"Super+q"} },
    }, null)).bindings;
    defer bindings.deinit();
    const q = keymap.libvaxisMatcher(Key{ .codepoint = 'q', .mods = .{ .super = true } });

    try testing.expectEqual(Action.quit, bindings.receive(&.{ .global, .dialog }, q).action);
    try testing.expectEqual(Action.cancel, bindings.receive(&.{ .dialog, .global }, q).action);
}

test "native single-key overlaps follow JSON declaration priority" {
    // Native overlaps must follow JSON order rather than Action enum order.
    const Action = enum { down, up };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator, &.{},
        \\{"list": {"up": ["Shift+;"], "down": [":"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expectEqual(Action.up, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } })).action);
}
