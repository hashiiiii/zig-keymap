const keymap = @import("keymap");
const Map = keymap.Bindings(enum { tree }, enum { quit, move_down });
const definition: Map.Definition = .{
    .defaults = &.{
        .{ .context = .tree, .action = .quit, .keys = &.{"Mod+q"} },
        .{ .context = .tree, .action = .move_down, .keys = &.{"Super+q"} },
    },
    .context_groups = &.{},
};

test "compile-time validation checks macOS Mod collisions" {
    // Mod and Super become the same modifier on macOS.
    Map.validateDefaults(definition);
}
