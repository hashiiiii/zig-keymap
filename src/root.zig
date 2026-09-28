//! zig-keymap maps keys to actions in Zig terminal applications.
//!
//! The hosted API documentation follows `main` and may include unreleased changes.
//! Use a release tag's README for that version's API.
//!
//! Define defaults in Zig, then load them with optional JSON.
//!
//! ```zig
//! const keymap = @import("keymap");
//! const Context = enum { list };
//! const Action = enum { move_down };
//! const Bindings = keymap.Bindings(Context, Action);
//!
//! const definition: Bindings.Definition = .{
//!     .defaults = &.{
//!         .{ .context = .list, .action = .move_down, .keys = &.{ "Down", "j" } },
//!     },
//!     .context_groups = &.{},
//! };
//!
//! var bindings = switch (try Bindings.load(allocator, definition, null)) {
//!     .bindings => |value| value,
//!     .invalid => return error.InvalidKeymap,
//! };
//! defer bindings.deinit();
//!
//! const action = bindings.resolve(&.{.list}, keymap.vaxisMatcher(event));
//! ```

const key = @import("key.zig");
const map = @import("map.zig");
const vaxis = @import("vaxis.zig");

pub const NamedKey = key.NamedKey;
pub const Modifiers = key.Modifiers;
pub const Key = key.Key;
pub const Keyboard = key.Keyboard;
pub const Sequence = @import("sequence.zig").Sequence;
pub const Platform = key.Platform;
pub const DisplayStyle = key.DisplayStyle;
pub const Diagnostic = map.Diagnostic;
pub const Bindings = map.Bindings;
pub const vaxisMatcher = vaxis.vaxisMatcher;

test {
    @import("std").testing.refAllDecls(@This());
}
