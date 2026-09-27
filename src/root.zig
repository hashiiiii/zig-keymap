//! zig-keymap maps keys to actions in Zig terminal applications.
//!
//! A context identifies where bindings apply.\
//! An action is an application operation.\
//! A binding assigns keys to a context and action.\
//! Define bindings in Zig.\
//! Load optional JSON configuration.
//!
//! ## Type relationships
//!
//! | Type | Represents | Example |
//! | --- | --- | --- |
//! | `Bindings` | Loaded bindings for the application's context and action enums | `list.move_down` bound to `Down` and `j` |
//! | `Bindings.Definition` | Default bindings and context groups | Input to `Bindings.load` |
//! | `Bindings.Default` | Default keys for one context and action | `list.move_down` assigned `Down` and `j` |
//! | `Keyboard` | The key and modifiers to match | `Ctrl+Enter` |
//! | `Sequence` | Successive configured key presses | `g g` |
//! | `Bindings.SequenceResolver` | Pending input driven by events and monotonic time | Waiting for the second `g` |
//! | `Platform` | Client platform used to expand `Mod` | `.macos` |
//! | `DisplayStyle` | Modifier names used in shortcut labels | `.windows` |
//! | `Key` | A character or named key, without modifiers | `j` or `Enter` |
//! | `NamedKey` | A key identified by name | `enter`, `down`, `f1` |
//! | `Modifiers` | Modifier flags used with a key | `ctrl = true` |
//! | `Platform` | The client operating system used to resolve `Mod` | `macos` |
//! | `DisplayStyle` | Modifier names used in shortcut labels | `macos` |
//! | `Diagnostic` | A problem in the configuration or definition | An invalid key or conflicting binding |
//!
//! `Keyboard.key` holds a `Key`.\
//! `Keyboard.modifiers` holds the modifier flags.\
//! A `Key` contains a Unicode codepoint or a `NamedKey`.\
//! A codepoint is a number that identifies a character.\
//! Terminal libraries provide incoming key events.\
//! `vaxisMatcher` creates a matcher that compares libvaxis events with `Keyboard` values.
//!
//! Select `Platform` from the operating system whose keyboard sends shortcut input.
//! The library does not infer it from the build target because a terminal may run remotely.
//! Pass that platform to `Keyboard.parseForPlatform` or `Bindings.loadWithOptions`.
//! Choose `DisplayStyle` separately when labels should use platform-specific names.
//!
//! ## Usage
//!
//! The application provides `allocator` and the incoming libvaxis key event `event`.
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
//! const label = bindings.hint(.list, .move_down);
//! ```
//!
//! To load `keymap.json`, pass its text to `load`.\
//! To use the keys in `definition.defaults`, pass `null`.\
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
/// `Sequence` contains successive key presses belonging to loaded bindings.
pub const Sequence = @import("sequence.zig").Sequence;
/// `Platform` selects how `Mod` resolves for a client keyboard.
pub const Platform = key.Platform;
/// `DisplayStyle` selects modifier names for shortcut labels.
pub const DisplayStyle = key.DisplayStyle;
/// `Diagnostic` describes a problem that `Bindings.load` finds.
pub const Diagnostic = map.Diagnostic;
/// `Bindings` creates a type for the application's context and action enums.
pub const Bindings = map.Bindings;
/// `vaxisMatcher` creates a matcher for libvaxis key events.
pub const vaxisMatcher = vaxis.vaxisMatcher;

test {
    @import("std").testing.refAllDecls(@This());
}
