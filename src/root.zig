//! Keyboard bindings for Zig terminal applications.
//!
//! Define contexts, actions, and default keys in Zig.
//! Load optional JSON settings, then match incoming key events to actions.
//!
//! ## Type relationships
//!
//! | Type | Represents | Example |
//! | --- | --- | --- |
//! | `Keymap` | Bindings for the application's context and action enums | `list.move_down` bound to `Down` and `j` |
//! | `Keyboard` | One key and its modifiers, used as a matching condition | `Ctrl+Enter` |
//! | `Key` | A character or named key, without modifiers | `j` or `Enter` |
//! | `NamedKey` | A key identified by name | `enter`, `down`, `f1` |
//! | `Modifiers` | Modifier flags used with a key | `ctrl = true` |
//! | `Diagnostic` | A problem in the configuration or specification | An invalid key or conflicting binding |
//!
//! `Keyboard.key` is a `Key`; `Keyboard.modifiers` is a `Modifiers` value.
//! A `Key` contains either a Unicode codepoint or a `NamedKey`.
//! Terminal libraries provide incoming key events. `vaxisMatcher` compares libvaxis events with configured `Keyboard` values.
//!
//! ## Usage
//!
//! ```zig
//! const keymap = @import("keymap");
//! const Context = enum { list };
//! const Action = enum { move_down };
//! const Bindings = keymap.Keymap(Context, Action);
//!
//! const specification: Bindings.Specification = .{
//!     .defaults = &.{
//!         .{ .context = .list, .action = .move_down, .keys = &.{ "Down", "j" } },
//!     },
//!     .context_groups = &.{},
//! };
//!
//! var bindings = switch (try Bindings.load(allocator, specification, null)) {
//!     .bindings => |value| value,
//!     .invalid => return error.InvalidKeymap,
//! };
//! defer bindings.deinit();
//!
//! const action = bindings.resolve(&.{.list}, keymap.vaxisMatcher(event));
//! const label = bindings.hint(.list, .move_down);
//! ```
//!
//! The application provides `allocator` and the incoming libvaxis key event `event`.
//! Pass JSON text to `load`, or `null` to use the declared defaults.
//! Other terminal libraries supply a matcher with `matches(Keyboard) bool`.

const key = @import("key.zig");
const map = @import("map.zig");
const vaxis = @import("vaxis.zig");

/// A key identified by name, such as `Enter`, `Down`, or `F1`.
pub const NamedKey = key.NamedKey;
/// Modifier flags used with a `Key` in `Keyboard`.
pub const Modifiers = key.Modifiers;
/// One character or named key, without modifiers.
pub const Key = key.Key;
/// One key and its modifiers, used as a matching condition.
pub const Keyboard = key.Keyboard;
/// A problem found when loading a keymap.
pub const Diagnostic = map.Diagnostic;
/// Creates a keymap type for the application's context and action enums.
pub const Keymap = map.Keymap;
/// Adapts a libvaxis key event for `Keymap.resolve`.
pub const vaxisMatcher = vaxis.vaxisMatcher;

test {
    @import("std").testing.refAllDecls(@This());
}
