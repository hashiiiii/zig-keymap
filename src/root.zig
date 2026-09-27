//! zig-keymap maps keys to actions in Zig terminal applications.
//!
//! A context is an application mode or view.
//! An action is an application operation.
//! A binding assigns keys to a context and action.
//! Define bindings in Zig.
//! Load optional JSON configuration.
//!
//! ## Type relationships
//!
//! | Type | Represents | Example |
//! | --- | --- | --- |
//! | `Keymap` | Bindings for the application's context and action enums | `list.move_down` bound to `Down` and `j` |
//! | `Keyboard` | The key and modifiers to match | `Ctrl+Enter` |
//! | `Key` | A character or named key, without modifiers | `j` or `Enter` |
//! | `NamedKey` | A key identified by name | `enter`, `down`, `f1` |
//! | `Modifiers` | Modifier flags used with a key | `ctrl = true` |
//! | `Diagnostic` | A problem in the configuration or specification | An invalid key or conflicting binding |
//!
//! `Keyboard.key` holds a `Key`.
//! `Keyboard.modifiers` holds the modifier flags.
//! A `Key` contains a Unicode codepoint or a `NamedKey`.
//! A codepoint is a number that identifies a character.
//! Terminal libraries provide incoming key events.
//! `vaxisMatcher` creates a matcher that compares libvaxis events with `Keyboard` values.
//!
//! ## Usage
//!
//! The application provides `allocator` and the incoming libvaxis key event `event`.
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
//! If you have JSON configuration, pass its text to `load`.
//! To use the keys in `specification.defaults`, pass `null`.
//! For other terminal libraries, provide a matcher with `matches(Keyboard) bool`.

const key = @import("key.zig");
const map = @import("map.zig");
const vaxis = @import("vaxis.zig");

/// `NamedKey` represents a key identified by name, such as `Enter`, `Down`, or `F1`.
pub const NamedKey = key.NamedKey;
/// `Modifiers` holds the modifier flags for a `Keyboard` value.
pub const Modifiers = key.Modifiers;
/// `Key` represents one character or named key, without modifiers.
pub const Key = key.Key;
/// `Keyboard` describes the key and modifiers to match.
pub const Keyboard = key.Keyboard;
/// `Diagnostic` describes a problem that `Keymap.load` finds.
pub const Diagnostic = map.Diagnostic;
/// `Keymap` creates a type for the application's context and action enums.
pub const Keymap = map.Keymap;
/// `vaxisMatcher` creates a matcher for libvaxis key events.
pub const vaxisMatcher = vaxis.vaxisMatcher;

test {
    @import("std").testing.refAllDecls(@This());
}
