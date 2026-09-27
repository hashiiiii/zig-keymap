const keymap = @import("keymap");
const Map = keymap.Bindings(enum { tree }, enum { move_down });
const definition: Map.Definition = .{
    .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{"Ctrl+Mod+j"} }},
    .context_groups = &.{},
};

test "compile-time validation checks duplicate expanded modifiers" {
    // Platform expansion must not turn two modifier names into one duplicate flag.
    Map.validateDefaults(definition);
}
