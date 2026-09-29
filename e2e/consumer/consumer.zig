const std = @import("std");
const keymap = @import("keymap");

test "consumer loads JSON without external dependencies" {
    // Applications using other adapters should not need to download test dependencies.
    const Map = keymap.Bindings(enum { global }, enum { quit, top });
    const definition: Map.Definition = .{
        .defaults = &.{
            .{ .context = .global, .action = .quit, .keys = &.{"Mod+q"} },
            .{ .context = .global, .action = .top, .keys = &.{"g g"} },
        },
        .context_groups = &.{},
    };
    comptime Map.validateDefaults(definition);
    var bindings = (try Map.loadWithOptions(std.testing.allocator, definition,
        \\{"global": {"quit": ["Ctrl+q"]}}
    , .{ .platform = .macos, .modifier_name = .macos })).bindings;
    defer bindings.deinit();
    try std.testing.expectEqualStrings("Ctrl+q", bindings.hint(.global, .quit));
    // Applications inspecting bindings need a public key type without terminal dependencies.
    try std.testing.expectEqual(keymap.KeyPress{
        .key = .{ .character = 'q' },
        .modifiers = .{ .ctrl = true },
    }, bindings.keys(.global, .quit)[0][0]);
    try std.testing.expectEqualStrings("g g", bindings.hint(.global, .top));
    try std.testing.expectEqual(@as(usize, 2), bindings.keys(.global, .top)[0].len);
}
