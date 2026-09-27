const std = @import("std");
const keymap = @import("keymap");

test "consumer loads JSON without external dependencies" {
    // Applications using other adapters should not need to download test dependencies.
    const Map = keymap.Keymap(enum { global }, enum { quit });
    var bindings = (try Map.load(std.testing.allocator, .{
        .defaults = &.{.{ .context = .global, .action = .quit, .keys = &.{"q"} }},
        .context_groups = &.{},
    },
        \\{"global": {"quit": ["Ctrl+q"]}}
    )).bindings;
    defer bindings.deinit();
    try std.testing.expectEqualStrings("Ctrl+q", bindings.hint(.global, .quit));
    // Applications inspecting bindings need Keyboard without terminal dependencies.
    try std.testing.expectEqual(keymap.Keyboard{
        .key = .{ .character = 'q' },
        .modifiers = .{ .ctrl = true },
    }, bindings.keys(.global, .quit)[0]);
}
