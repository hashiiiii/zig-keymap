//! zig-keymap maps keys to actions in Zig terminal applications.
//!
//! Define defaults in Zig, then load them with optional JSON.
//!
//! ```zig
//! const keymap = @import("keymap");
//! const Context = enum { global, list, modal };
//! const Action = enum { quit, move_down, cancel };
//! const Bindings = keymap.Bindings(Context, Action);
//!
//! const definition: Bindings.Definition = .{
//!     .defaults = &.{
//!         .{ .context = .global, .action = .quit, .keys = &.{"q"} },
//!         .{ .context = .list, .action = .move_down, .keys = &.{ "Down", "j" } },
//!         .{ .context = .modal, .action = .cancel, .keys = &.{"Escape"} },
//!     },
//!     .context_groups = &.{
//!         &.{ .global, .list },
//!         &.{ .global, .modal },
//!     },
//! };
//!
//! var bindings = switch (try Bindings.load(allocator, definition, null)) {
//!     .bindings => |value| value,
//!     .invalid => return error.InvalidKeymap,
//! };
//! defer bindings.deinit();
//!
//! var receiver = try bindings.receiver(allocator, .{});
//! defer receiver.deinit();
//! const action: ?Action = switch (receiver.receive(&.{ .global, .list }, keymap.vaxisMatcher(event), now_ms)) {
//!     .action => |value| value,
//!     .pending, .none => null,
//! };
//! ```

const key = @import("key.zig");
const map = @import("map.zig");
const vaxis = @import("vaxis.zig");

pub const NamedKey = key.NamedKey;
pub const Modifiers = key.Modifiers;
pub const Key = key.Key;
pub const KeyPress = key.KeyPress;
pub const Platform = key.Platform;
pub const ModifierName = key.ModifierName;
pub const Diagnostic = map.Diagnostic;
pub const Bindings = map.Bindings;
pub const vaxisMatcher = vaxis.vaxisMatcher;

test {
    @import("std").testing.refAllDecls(@This());
}
