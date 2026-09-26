const std = @import("std");
const keymap = @import("keymap");

test "consumer loads JSON without external dependencies" {
    // Applications using other adapters should not need to download test dependencies.
    const Map = keymap.Keymap(enum { global }, enum { quit });
    var bindings = (try Map.load(std.testing.allocator, .{
        .defaults = &.{.{ .context = .global, .action = .quit, .keys = &.{"q"} }},
        .active_contexts = &.{},
    },
        \\{"global": {"quit": ["Ctrl+q"]}}
    )).bindings;
    defer bindings.deinit();
    try std.testing.expectEqualStrings("Ctrl+q", bindings.hint(.global, .quit));
}
