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
    const f13 = (try parser.parse("\x1b[57376u", null)).event.?;
    try testing.expectEqual(Action.function, bindings.receive(&.{.global}, keymap.libvaxisMatcher(f13.key_press)).action);
    const f35 = (try parser.parse("\x1b[57398u", null)).event.?;
    try testing.expectEqual(Action.function, bindings.receive(&.{.global}, keymap.libvaxisMatcher(f35.key_press)).action);
    const print_screen = (try parser.parse("\x1b[57361u", null)).event.?;
    try testing.expectEqual(Action.capture, bindings.receive(&.{.global}, keymap.libvaxisMatcher(print_screen.key_press)).action);
    const keypad_digit = (try parser.parse("\x1b[57400;129;49u", null)).event.?;
    try testing.expectEqual(Action.keypad, bindings.receive(&.{.global}, keymap.libvaxisMatcher(keypad_digit.key_press)).action);
    const keypad_enter = (try parser.parse("\x1b[57414;129;13u", null)).event.?;
    try testing.expectEqual(Action.keypad, bindings.receive(&.{.global}, keymap.libvaxisMatcher(keypad_enter.key_press)).action);
    const media = (try parser.parse("\x1b[57430u", null)).event.?;
    try testing.expectEqual(Action.play, bindings.receive(&.{.global}, keymap.libvaxisMatcher(media.key_press)).action);
    const volume = (try parser.parse("\x1b[57439;5u", null)).event.?;
    try testing.expectEqual(Action.volume, bindings.receive(&.{.global}, keymap.libvaxisMatcher(volume.key_press)).action);

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

    // Logical Unicode keys must remain usable even when a backend also reports a physical base key.
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{ .codepoint = 'あ', .base_layout_codepoint = 'a', .mods = .{ .super = true } })) == .pending);
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

test "ASCII Shift bindings ignore optional native text" {
    // Caps Lock can produce lowercase text while Shift remains pressed.
    const Action = enum { plain, shifted };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"plain": ["Ctrl+j", "Ctrl+i"], "shifted": ["Ctrl+J", "Ctrl+Shift+i"]}}
    )).bindings;
    defer bindings.deinit();

    var parser: vaxis.Parser = .{};
    const without_text = (try parser.parse("\x1b[106:74;70u", null)).event.?;
    try testing.expectEqual(Action.shifted, bindings.receive(&.{.list}, keymap.libvaxisMatcher(without_text.key_press)).action);
    const with_text = (try parser.parse("\x1b[106:74;70;106u", null)).event.?;
    try testing.expectEqual(Action.shifted, bindings.receive(&.{.list}, keymap.libvaxisMatcher(with_text.key_press)).action);
    try testing.expectEqual(Action.shifted, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{
        .codepoint = 'J',
        .mods = .{ .ctrl = true },
    })).action);
    try testing.expectEqual(Action.plain, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{
        .codepoint = 'j',
        .mods = .{ .ctrl = true },
    })).action);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{
        .codepoint = 'j',
        .mods = .{ .shift = true },
    })) == .none);

    // Alternate layouts can produce an ASCII letter from a non-ASCII key without a text field.
    try testing.expectEqual(Action.shifted, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{
        .codepoint = 'ı',
        .shifted_codepoint = 'I',
        .mods = .{ .ctrl = true, .shift = true },
    })).action);
}

test "native shifted symbols preserve shortcut and text matching" {
    // Windows reports the produced symbol separately from the key used by the shortcut.
    const Action = enum { shortcut, symbol, plain };
    const Map = keymap.Bindings(enum { key, text }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"key": {"shortcut": ["Ctrl+Shift+1"]}, "text": {"symbol": ["Ctrl+!"], "plain": ["Ctrl+1"]}}
    )).bindings;
    defer bindings.deinit();
    const windows = keymap.libvaxisMatcher(Key{
        .codepoint = '!',
        .base_layout_codepoint = '1',
        .text = "!",
        .mods = .{ .ctrl = true, .shift = true },
    });

    try testing.expectEqual(Map.Result{ .action = .shortcut }, bindings.receive(&.{ .key, .text }, windows));
    try testing.expectEqual(Map.Result{ .action = .symbol }, bindings.receive(&.{ .text, .key }, windows));
    try testing.expectEqual(Action.shortcut, bindings.receive(&.{ .key, .text }, keymap.libvaxisMatcher(Key{
        .codepoint = '1',
        .shifted_codepoint = '!',
        .text = "!",
        .mods = .{ .ctrl = true, .shift = true },
    })).action);
}

test "Caps Lock preserves ASCII binding selection across native encodings" {
    // Lock state must not be mistaken for holding Shift on a backend that reports uppercase codepoints.
    const Action = enum { plain, shifted };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"plain": ["j"], "shifted": ["J"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expectEqual(Action.plain, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{
        .codepoint = 'j',
        .text = "J",
        .mods = .{ .caps_lock = true },
    })).action);
    try testing.expectEqual(Map.Result{ .action = .plain }, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{
        .codepoint = 'J',
        .base_layout_codepoint = 'j',
        .text = "J",
        .mods = .{ .caps_lock = true },
    })));
    try testing.expectEqual(Action.shifted, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{
        .codepoint = 'j',
        .base_layout_codepoint = 'j',
        .text = "j",
        .mods = .{ .shift = true, .caps_lock = true },
    })).action);
}

test "native text preserves modifiers on unchanged keys" {
    // Text matching must not consume Shift when it leaves a digit or named key unchanged.
    const Action = enum { digit, shifted_space, space };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(testing.allocator,
        \\{"list": {"digit": ["Ctrl+1"], "space": ["Space"], "shifted_space": ["Shift+Space"]}}
    )).bindings;
    defer bindings.deinit();

    try testing.expectEqual(Action.digit, bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{
        .codepoint = '1',
        .text = "1",
        .mods = .{ .ctrl = true },
    })).action);
    try testing.expect(bindings.receive(&.{.list}, keymap.libvaxisMatcher(Key{
        .codepoint = '1',
        .text = "1",
        .mods = .{ .ctrl = true, .shift = true },
    })) == .none);
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
