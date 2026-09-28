const keymap = @import("keymap");
const Map = keymap.Bindings(enum { tree }, enum { move_down });
const definition: Map.Definition = .{
    .defaults = &.{
        .{ .context = .tree, .action = .move_down, .keys = &.{"j"} },
        .{ .context = .tree, .action = .move_down, .keys = &.{"k"} },
    },
    .context_groups = &.{},
};

test "compile-time validation reports duplicate context and action pairs" {
    // Repeating a context and action would make a JSON override ambiguous.
    Map.validateDefaults(definition);
}
