//! zig-keymap maps keys to actions in Zig terminal applications.
//!
//! Define defaults in Zig and override keys with JSON.
//! This example requires `keymap.json` and uses libvaxis for terminal input.
//!
//! ```zig
//! const std = @import("std");
//! const keymap = @import("keymap");
//! const vaxis = @import("vaxis");
//! const Context = enum { global, list };
//! const Action = enum { quit, move_down, top };
//! const Bindings = keymap.Bindings(Context, Action);
//!
//! // Only key presses matter here because this example has no screen to resize.
//! const Event = union(enum) { key_press: vaxis.Key };
//!
//! // Enum values let the compiler reject unknown contexts and actions in these defaults.
//! const definition: Bindings.Definition = .{
//!     .defaults = &.{
//!         .{ .context = .global, .action = .quit, .keys = &.{ "q", "Mod+q" } },
//!         .{ .context = .list, .action = .move_down, .keys = &.{ "Down", "j" } },
//!         .{ .context = .list, .action = .top, .keys = &.{"g g"} },
//!     },
//!     // Groups declare possible overlaps for conflict checks.
//!     // Receive selects the active contexts.
//!     // With these defaults, assigning q to list.move_down would collide with global.quit.
//!     .context_groups = &.{
//!         &.{ .global, .list },
//!     },
//! };
//!
//! pub fn main(init: std.process.Init) !void {
//!     const allocator = init.gpa;
//!     const io = init.io;
//!
//!     // A missing or unreadable file must stop startup because JSON configuration is required.
//!     const keymap_json = try std.Io.Dir.cwd().readFileAlloc(io, "keymap.json", allocator, .unlimited);
//!     defer allocator.free(keymap_json);
//!
//!     // Mod follows the keyboard's platform, which may differ from the build target.
//!     var bindings = switch (try Bindings.loadWithOptions(allocator, definition, keymap_json, .{
//!         .platform = .macos,
//!         // Label spelling can follow the client without changing which input matches.
//!         .modifier_name = .macos,
//!     })) {
//!         .bindings => |value| value,
//!         .invalid => |diagnostic| {
//!             std.log.err("{s}", .{diagnostic.message()});
//!             return error.InvalidKeymap;
//!         },
//!     };
//!     defer bindings.deinit();
//!
//!     // Keep one receiver per input stream so partial sequences stay separate.
//!     var receiver = try bindings.receiver(allocator, io, .{});
//!     defer receiver.deinit();
//!
//!     var tty_buffer: [1024]u8 = undefined;
//!     var tty = try vaxis.Tty.init(io, &tty_buffer);
//!     defer tty.deinit();
//!
//!     var vx = try vaxis.init(io, allocator, init.environ_map, .{});
//!     defer vx.deinit(allocator, tty.writer());
//!
//!     var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
//!
//!     // Start native input parsing so nextEvent() returns real keyboard events.
//!     try loop.start();
//!     defer loop.stop();
//!
//!     // Loaded labels keep the quit hint consistent with JSON changes.
//!     std.debug.print("Quit: {s}\r\n", .{bindings.hint(.global, .quit)});
//!
//!     // Passing both contexts keeps global quit available while list navigation is active.
//!     const active_contexts: []const Context = &.{ .global, .list };
//!     var row: usize = 0;
//!     while (true) {
//!         const event = try loop.nextEvent();
//!         const key = event.key_press;
//!
//!         // Delegating to Key.matches preserves libvaxis's text and Shift matching rules.
//!         switch (receiver.receive(active_contexts, keymap.libvaxisMatcher(key))) {
//!             // The receiver chooses an action; the application owns its behavior.
//!             .action => |action| switch (action) {
//!                 .quit => return,
//!                 .move_down => row +|= 1,
//!                 .top => row = 0,
//!             },
//!             // A partial "g g" must wait; unassigned input has no action to run.
//!             .pending, .none => continue,
//!         }
//!         std.debug.print("Row: {d}\r\n", .{row});
//!     }
//! }
//! ```
//!
//! Save this configuration as `keymap.json`:
//!
//! ```json
//! {
//!   "global": { "quit": ["Ctrl+q"] },
//!   "list": { "move_down": ["Ctrl+n"] }
//! }
//! ```
//!
//! Here, `top` is omitted from the JSON configuration, so its default binding `g g` remains available.

const key = @import("key.zig");
const bindings = @import("bindings.zig");
const libvaxis = @import("matcher/libvaxis.zig");

pub const NamedKey = key.NamedKey;
pub const Modifiers = key.Modifiers;
pub const Key = key.Key;
pub const KeyPress = key.KeyPress;
pub const Platform = key.Platform;
pub const ModifierName = key.ModifierName;
pub const Diagnostic = bindings.Diagnostic;
pub const Bindings = bindings.Bindings;
pub const libvaxisMatcher = libvaxis.libvaxisMatcher;

test {
    @import("std").testing.refAllDecls(@This());
}
