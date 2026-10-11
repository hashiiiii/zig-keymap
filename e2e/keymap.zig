const std = @import("std");
const testing = std.testing;
const keymap = @import("keymap");
const vaxis = @import("vaxis");
const Key = vaxis.Key;

test "JSON assigns typed actions in active contexts" {
    // Only configured keys in active contexts may invoke actions.
    const Context = enum { global, list, dialog };
    const Action = enum { quit, down, up, cancel };
    const Map = keymap.Bindings(Context, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"global": {"quit": ["q"]}, "list": {"down": ["Ctrl+n"], "up": ["Up"]}, "dialog": {"cancel": ["q", "Escape"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expectEqual(Action.down, bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'n', .mods = .{ .ctrl = true } })).action);
    try testing.expectEqual(Action.quit, bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'q' })).action);
    try testing.expectEqual(Action.up, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = Key.up })).action);
    try testing.expectEqual(Action.cancel, bindings.receive(&.{.dialog}, keymap.libvaxisMatcher(Key{ .codepoint = 'q' })).action);
    try testing.expectEqual(Action.cancel, bindings.receive(&.{.dialog}, keymap.libvaxisMatcher(Key{ .codepoint = Key.escape })).action);
}

test "extended named keys select actions and distinguish keypad input" {
    // Protocol keys must reach configured actions without losing keypad identity to text.
    const Action = enum { function, capture, keypad, main, play, volume };
    const Map = keymap.Bindings(enum { global }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"global": {"main": ["1", "Enter"], "function": ["F13", "F35"], "capture": ["PrintScreen"], "keypad": ["Keypad1", "KeypadEnter"], "play": ["MediaPlayPause"], "volume": ["Ctrl+RaiseVolume"]}}
    )).bindings;
    defer bindings.deinit();

    var parser: vaxis.Parser = .{};
    const cases = [_]struct { []const u8, Action }{
        .{ "\x1b[57376u", .function },
        .{ "\x1b[57398u", .function },
        .{ "\x1b[57361u", .capture },
        .{ "\x1b[57400;129;49u", .keypad },
        .{ "\x1b[57414;129;13u", .keypad },
        .{ "\x1b[57430u", .play },
        .{ "\x1b[57439;5u", .volume },
    };
    for (cases) |case| {
        const event = (try parser.parse(case[0], null)).event.?;
        try testing.expectEqual(case[1], bindings.receive(&.{.global}, keymap.libvaxisMatcher(event.key_press)).action);
    }

    // Windows console events retain the keypad codepoint separately from the produced character.
    try testing.expectEqual(Action.keypad, bindings.receive(&.{.global}, keymap.libvaxisMatcher(Key{
        .codepoint = '1',
        .base_layout_codepoint = Key.kp_1,
        .text = "1",
        .mods = .{ .num_lock = true },
    })).action);
    try testing.expectEqual(Action.main, bindings.receive(&.{.global}, keymap.libvaxisMatcher(Key{ .codepoint = '1' })).action);
    try testing.expectEqual(Action.main, bindings.receive(&.{.global}, keymap.libvaxisMatcher(Key{ .codepoint = Key.enter })).action);
}

test "input streams keep pending keys separate" {
    // A prefix typed in one window must not complete a sequence in another.
    const Action = enum { top };
    const Map = keymap.Bindings(enum { list }, Action);
    const json =
        \\{"list": {"top": ["g g"]}}
    ;
    var first = (try Map.load(testing.allocator, json)).bindings;
    defer first.deinit();
    var second = (try Map.load(testing.allocator, json)).bindings;
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
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"top": ["g g"], "end": ["g e"]}}
    )).bindings;
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
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"next": ["Ctrl+b n"], "quit": ["q"]}}
    )).bindings;
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

    // Releases must discard inactive prefixes even if the original context resumes before the next press.
    try testing.expect(bindings.receive(&.{.list}, prefix) == .pending);
    var parser: vaxis.Parser = .{};
    const release = (try parser.parse("\x1b[98;5:3u", null)).event.?;
    try testing.expect(bindings.receive(&.{.dialog}, keymap.libvaxisMatcher(release)) == .none);
    try testing.expect(bindings.receive(&.{.list}, n) == .none);
}

test "three-step sequences consume each event once" {
    // Repeating a context must not consume one event as multiple sequence steps.
    const Action = enum { command };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"command": ["g g e"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'g' })) == .pending);
    try testing.expect(bindings.receive(&.{ .list, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'g' })) == .pending);
    try testing.expectEqual(Action.command, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'e' })).action);
}

test "Space works as a key and within a sequence" {
    // Space separates sequence steps, so the named key must remain usable with modifiers.
    const Action = enum { select, next };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"select": ["Space"], "next": ["Ctrl+Space n"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expectEqual(Action.select, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = ' ' })).action);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = ' ', .mods = .{ .ctrl = true } })) == .pending);
    try testing.expectEqual(Action.next, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'n' })).action);
}

test "native single keys yield to higher-priority sequences" {
    // A shared input must start the earlier sequence instead of running a lower-priority action.
    const Action = enum { long, short };
    const Map = keymap.Bindings(enum { global, list }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"short": [":"]}, "global": {"long": ["Shift+; x"]}}
    )).bindings;
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
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"short": [": x"]}, "global": {"long": ["Shift+; x y"]}}
    )).bindings;
    defer bindings.deinit();
    const colon = keymap.libvaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } });

    try testing.expect(bindings.receive(&.{ .global, .list }, colon) == .pending);
    try testing.expect(bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })) == .pending);
    try testing.expectEqual(Action.long, bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'y' })).action);
    try testing.expect(bindings.receive(&.{ .global, .list }, colon) == .pending);
    try testing.expectEqual(Action.short, bindings.receive(&.{ .list, .global }, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })).action);
    try testing.expect(bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })) == .none);
}

test "native sequence overlaps follow JSON declaration priority" {
    // Native overlaps must follow JSON order rather than Action enum order.
    const Action = enum { short, long };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"long": ["Shift+; x y"], "short": [": x"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } })) == .pending);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'x' })) == .pending);
    try testing.expectEqual(Action.long, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'y' })).action);
}

test "empty arrays and omitted actions leave keys unbound" {
    // Empty and omitted assignments must not gain implicit keys.
    const Map = keymap.Bindings(enum { list }, enum { down, up });
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"down": []}}
    )).bindings;
    defer bindings.deinit();

    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'j' })) == .none);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = Key.down })) == .none);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = Key.up })) == .none);
}

test "JSON sequences accept modifier aliases and Unicode" {
    // OS-specific spellings must work without OS selection in the API.
    const Action = enum { next };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator,
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
    var bindings = (try Map.load(testing.allocator,
        \\{"global": {"quit": ["Cmd+q"]}, "dialog": {"cancel": ["Super+q"]}}
    )).bindings;
    defer bindings.deinit();
    const q = keymap.libvaxisMatcher(Key{ .codepoint = 'q', .mods = .{ .super = true } });

    try testing.expectEqual(Action.quit, bindings.receive(&.{ .global, .dialog }, q).action);
    try testing.expectEqual(Action.cancel, bindings.receive(&.{ .dialog, .global }, q).action);
}

test "native single-key overlaps follow JSON declaration priority" {
    // Native overlaps must follow JSON order rather than Action enum order.
    const Action = enum { down, up };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"up": ["Shift+;"], "down": [":"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expectEqual(Action.up, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = ';', .text = ":", .mods = .{ .shift = true } })).action);
}

test "native text requires Shift before selecting shifted bindings" {
    // Text fields must not let an unshifted event invoke a shifted action.
    const Action = enum { shifted_digit, digit, shifted_space, space };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"shifted_digit": ["Ctrl+Shift+1"], "digit": ["Ctrl+1"], "space": ["Space"], "shifted_space": ["Shift+Space"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expectEqual(Action.digit, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{
        .codepoint = '1',
        .text = "1",
        .mods = .{ .ctrl = true },
    })).action);
    try testing.expectEqual(Action.shifted_digit, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{
        .codepoint = '1',
        .text = "!",
        .mods = .{ .ctrl = true, .shift = true },
    })).action);
    try testing.expectEqual(Action.space, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{
        .codepoint = Key.space,
        .text = " ",
    })).action);
    try testing.expectEqual(Action.shifted_space, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{
        .codepoint = Key.space,
        .text = " ",
        .mods = .{ .shift = true },
    })).action);
}

test "ASCII Shift bindings ignore optional native text" {
    // Caps Lock can produce lowercase text while Shift remains pressed.
    const Action = enum { plain, shifted };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"plain": ["Ctrl+j"], "shifted": ["Ctrl+J"]}}
    )).bindings;
    defer bindings.deinit();

    var parser: vaxis.Parser = .{};
    const without_text = (try parser.parse("\x1b[106:74;70u", null)).event.?;
    try testing.expectEqual(Action.shifted, bindings.receive(&.{.list}, keymap.libvaxisMatcher(without_text.key_press)).action);
    const with_text = (try parser.parse("\x1b[106:74;70;106u", null)).event.?;
    try testing.expectEqual(Action.shifted, bindings.receive(&.{.list}, keymap.libvaxisMatcher(with_text.key_press)).action);
}

test "native modifier events distinguish left right and both sides" {
    // Aggregate Ctrl flags need press/release history; an unknown side must never select a sided action.
    const Action = enum { left, right, both, modifier };
    const Map = keymap.Bindings(enum { list }, Action);
    const json =
        \\{"list": {"left": ["LeftCtrl+x"], "right": ["RightCtrl+x"], "both": ["LeftCtrl+RightCtrl+x"], "modifier": ["LeftControl", "RightControl"]}}
    ;
    var bindings = (try Map.load(testing.allocator, json)).bindings;
    defer bindings.deinit();
    var other = (try Map.load(testing.allocator, json)).bindings;
    defer other.deinit();

    var parser: vaxis.Parser = .{};
    const cases = [_]struct { []const u8, Map.Result }{
        .{ "\x1b[120;5u", .none },
        .{ "\x1b[57442;5u", .none },
        .{ "\x1b[120;5u", .none },
        .{ "\x1b[57442;5:3u", .none },
        .{ "\x1b[120;5u", .{ .action = .right } },
        .{ "\x1b[57448;1:3u", .none },
        .{ "\x1b[120u", .none },
        .{ "\x1b[57442;5u", .{ .action = .modifier } },
        .{ "\x1b[120;5u", .{ .action = .left } },
        .{ "\x1b[I", .none },
        .{ "\x1b[57442;5:2u", .{ .action = .modifier } },
        .{ "\x1b[120;5:2u", .{ .action = .left } },
        .{ "\x1b[57448;5u", .none },
        .{ "\x1b[120;5u", .{ .action = .both } },
        .{ "\x1b[57442;5:3u", .none },
        .{ "\x1b[120;5u", .{ .action = .right } },
        .{ "\x1b[57448;1:3u", .none },
        .{ "\x1b[120;5u", .none },
        .{ "\x1b[120u", .none },
        .{ "\x1b[57448;5u", .{ .action = .modifier } },
        .{ "\x1b[120;5u", .{ .action = .right } },
        .{ "\x1b[O", .none },
        .{ "\x1b[120;5u", .none },
    };
    for (cases) |case| {
        const event = (try parser.parse(case[0], null)).event.?;
        try testing.expectEqualDeep(case[1], bindings.receive(&.{.list}, keymap.libvaxisMatcher(event)));
        if (case[1] == .action and case[1].action == .left) {
            const x = (try parser.parse("\x1b[120;5u", null)).event.?;
            try testing.expect(other.receive(&.{.list}, keymap.libvaxisMatcher(x)) == .none);
        }
    }
    const left = (try parser.parse("\x1b[57442;5u", null)).event.?;
    _ = bindings.receive(&.{.list}, keymap.libvaxisMatcher(left));
    bindings.cancel();
    const x = (try parser.parse("\x1b[120;5u", null)).event.?;
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(x)) == .none);
}

test "modifier presses and key releases preserve pending sequences" {
    // Holding a modifier for a later step must not consume or cancel the earlier prefix.
    const Action = enum { next };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"next": ["g LeftCtrl+x"]}}
    )).bindings;
    defer bindings.deinit();
    var parser: vaxis.Parser = .{};
    const cases = [_]struct { []const u8, Map.Result }{
        .{ "\x1b[103u", .pending },
        .{ "\x1b[103;1:3u", .none },
        .{ "\x1b[57442;5u", .pending },
        .{ "\x1b[120;5u", .{ .action = .next } },
        .{ "\x1b[57442;1:3u", .none },
        .{ "\x1b[103u", .pending },
        .{ "\x1b[O", .none },
        .{ "\x1b[57442;5u", .none },
        .{ "\x1b[120;5u", .none },
    };
    for (cases) |case| {
        const event = (try parser.parse(case[0], null)).event.?;
        try testing.expectEqualDeep(case[1], bindings.receive(&.{.list}, keymap.libvaxisMatcher(event)));
    }
}

test "configured modifier presses retry the start of a sequence" {
    // A bound modifier remains an ordinary sequence key, including restart after a mismatch.
    const Action = enum { next };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"next": ["LeftControl Ctrl+y Ctrl+x"]}}
    )).bindings;
    defer bindings.deinit();
    var parser: vaxis.Parser = .{};
    const cases = [_]struct { []const u8, Map.Result }{
        .{ "\x1b[57442;5u", .pending },
        .{ "\x1b[121;5u", .pending },
        .{ "\x1b[57442;5:2u", .pending },
        .{ "\x1b[120;5u", .none },
        .{ "\x1b[57442;5:2u", .pending },
        .{ "\x1b[121;5u", .pending },
        .{ "\x1b[120;5u", .{ .action = .next } },
    };
    for (cases) |case| {
        const event = (try parser.parse(case[0], null)).event.?;
        try testing.expectEqualDeep(case[1], bindings.receive(&.{.list}, keymap.libvaxisMatcher(event)));
    }
}

test "native Shift and Cmd sides combine independently" {
    // Sided Shift must preserve ASCII aliases while another modifier changes sides.
    const Action = enum { first, second };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"first": ["LeftShift+RightCmd+J"], "second": ["RightShift+LeftCmd+j"]}}
    )).bindings;
    defer bindings.deinit();
    var parser: vaxis.Parser = .{};
    const cases = [_]struct { []const u8, Map.Result }{
        .{ "\x1b[57441;2u", .none },
        .{ "\x1b[57450;10u", .none },
        .{ "\x1b[106:74;10;106u", .{ .action = .first } },
        .{ "\x1b[57441;9:3u", .none },
        .{ "\x1b[106;9u", .none },
        .{ "\x1b[57444;9u", .none },
        .{ "\x1b[57447;10u", .none },
        .{ "\x1b[106:74;10u", .none },
        .{ "\x1b[57450;10:3u", .none },
        .{ "\x1b[106:74;10u", .{ .action = .second } },
    };
    for (cases) |case| {
        const event = (try parser.parse(case[0], null)).event.?;
        try testing.expectEqualDeep(case[1], bindings.receive(&.{.list}, keymap.libvaxisMatcher(event)));
    }
}
