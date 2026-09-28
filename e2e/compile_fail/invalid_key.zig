const keymap = @import("keymap");
const Map = keymap.Bindings(enum { tree }, enum { move_down });
const definition: Map.Definition = .{
    .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{"Unknown+j"} }},
    .context_groups = &.{},
};

test "compile-time validation reports invalid default keys" {
    // Invalid application defaults should produce a compile error before startup.
    Map.validateDefaults(definition);
}
