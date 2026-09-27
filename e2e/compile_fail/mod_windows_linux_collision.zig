const keymap = @import("keymap");
const Map = keymap.Bindings(enum { tree }, enum { quit, move_down });
const definition: Map.Definition = .{
    .defaults = &.{
        .{ .context = .tree, .action = .quit, .keys = &.{"Mod+q"} },
        .{ .context = .tree, .action = .move_down, .keys = &.{"Ctrl+q"} },
    },
    .context_groups = &.{},
};

test "compile-time validation checks Windows and Linux Mod collisions" {
    // Mod resolves to Ctrl on both platforms, so both collisions must be diagnosed.
    Map.validateDefaults(definition);
}
