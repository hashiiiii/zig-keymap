const std = @import("std");
const keymap = @import("keymap");

test "consumer loads JSON and receives typed input without dependencies" {
    // Other input backends must work without downloading terminal packages.
    const Action = enum { quit, top };
    const Map = keymap.Bindings(enum { global }, Action);
    var bindings = (try Map.load(std.testing.allocator, @embedFile("keymap.json"))).bindings;
    defer bindings.deinit();

    const q: keymap.KeyPress = .{
        .key = .{ .character = 'q' },
        .modifiers = .{ .ctrl = .any },
    };
    const g: keymap.KeyPress = .{ .key = .{ .character = 'g' } };
    const result: Map.Result = bindings.receive(&.{.global}, q);
    try std.testing.expectEqual(Action.quit, result.action);
    // The matcher interface also accepts references to real key presses.
    try std.testing.expectEqual(Action.quit, bindings.receive(&.{.global}, &q).action);
    try std.testing.expect(bindings.receive(&.{.global}, g) == .pending);
    try std.testing.expectEqual(Action.top, bindings.receive(&.{.global}, g).action);
    try std.testing.expect(bindings.receive(&.{.global}, keymap.KeyPress{
        .key = .{ .character = 'q' },
        .modifiers = .{ .super = .any },
    }) == .none);
}

test "consumer tracks typed modifier events without dependencies" {
    // Sided shortcuts must also work for applications that do not use a native adapter.
    const Action = enum { select };
    const Map = keymap.Bindings(enum { list }, Action);
    var bindings = (try Map.load(std.testing.allocator,
        \\{"list": {"select": ["LeftCtrl+x"]}}
    )).bindings;
    defer bindings.deinit();
    const x: keymap.KeyPress = .{ .key = .{ .character = 'x' }, .modifiers = .{ .ctrl = .any } };

    try std.testing.expect(bindings.receive(&.{.list}, keymap.KeyEvent{
        .press = .{ .key = .{ .named = .left_control } },
    }) == .none);
    try std.testing.expectEqual(Action.select, bindings.receive(&.{.list}, x).action);
    try std.testing.expect(bindings.receive(&.{.list}, keymap.KeyEvent{
        .release = .{ .key = .{ .named = .left_control } },
    }) == .none);
    try std.testing.expect(bindings.receive(&.{.list}, x) == .none);
    try std.testing.expectEqual(Action.select, bindings.receive(&.{.list}, keymap.KeyPress{
        .key = .{ .character = 'x' },
        .modifiers = .{ .ctrl = .left },
    }).action);
}
