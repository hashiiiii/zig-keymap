//! Map JSON key bindings to typed actions.
//!
//! Load JSON assignments, receive one key event, and handle the result:
//!
//! ```zig
//! const keymap = @import("keymap");
//! const Context = enum { list };
//! const Action = enum { quit, top };
//! const Bindings = keymap.Bindings(Context, Action);
//!
//! const json =
//!     \\{"list": {"quit": ["Cmd+q"], "top": ["g g"]}}
//! ;
//! var bindings = switch (try Bindings.load(allocator, json)) {
//!     .bindings => |value| value,
//!     .invalid => |value| {
//!         var diagnostic = value;
//!         defer diagnostic.deinit();
//!         showConfigError(diagnostic.message);
//!         return;
//!     },
//! };
//! defer bindings.deinit();
//!
//! const key: keymap.KeyPress = .{
//!     .key = .{ .character = 'q' },
//!     .modifiers = .{ .super = true },
//! };
//! switch (bindings.receive(&.{.list}, key)) {
//!     .action => |action| handleAction(action),
//!     .pending, .none => {},
//! }
//! ```
//!
//! For libvaxis input, pass libvaxisMatcher(event.key_press) to receive.

const key = @import("key.zig");

pub const NamedKey = key.NamedKey;
pub const Modifiers = key.Modifiers;
pub const Key = key.Key;
pub const KeyPress = key.KeyPress;
pub const Diagnostic = @import("bindings.zig").Diagnostic;
pub const Bindings = @import("bindings.zig").Bindings;
pub const libvaxisMatcher = @import("matcher/libvaxis.zig").libvaxisMatcher;

test {
    @import("std").testing.refAllDecls(@This());
}
