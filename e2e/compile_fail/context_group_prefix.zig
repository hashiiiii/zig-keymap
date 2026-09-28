const keymap = @import("keymap");
const Map = keymap.Bindings(enum { global, tree }, enum { quit, move_down });
const definition: Map.Definition = .{
    .defaults = &.{
        .{ .context = .global, .action = .quit, .keys = &.{"g"} },
        .{ .context = .tree, .action = .move_down, .keys = &.{"g g"} },
    },
    .context_groups = &.{&.{ .global, .tree }},
};

test "compile-time validation checks grouped sequence prefixes" {
    // Contexts active together must not let one action shadow another sequence.
    Map.validateDefaults(definition);
}
