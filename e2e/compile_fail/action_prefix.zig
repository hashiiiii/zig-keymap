const keymap = @import("keymap");
const Map = keymap.Bindings(enum { tree }, enum { move_down });
const definition: Map.Definition = .{
    .defaults = &.{.{ .context = .tree, .action = .move_down, .keys = &.{ "g", "g g" } }},
    .context_groups = &.{},
};

test "compile-time validation rejects prefixes within one action" {
    // A shared prefix leaves input ambiguous even when both shortcuts select one action.
    Map.validateDefaults(definition);
}
