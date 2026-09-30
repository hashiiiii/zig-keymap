# zig-keymap

[![License](https://img.shields.io/github/license/hashiiiii/zig-keymap)](LICENSE)
[![Release](https://img.shields.io/github/v/release/hashiiiii/zig-keymap)](https://github.com/hashiiiii/zig-keymap/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/hashiiiii/zig-keymap/ci.yml?branch=main&label=CI)](https://github.com/hashiiiii/zig-keymap/actions/workflows/ci.yml)
[![Zig](https://img.shields.io/badge/zig-0.16.0-f7a41d.svg?logo=zig&logoColor=white)](https://ziglang.org)

zig-keymap maps keys to actions in Zig terminal applications.  
Applications define defaults in Zig, and users can change them with JSON configuration.  
Bindings support platform modifiers, shortcut labels, and successive key presses.

## Installation

zig-keymap requires Zig `0.16.0` and has no external dependencies.

Add `zig_keymap` to `build.zig.zon`:

   ```sh
   zig fetch --save=zig_keymap "git+https://github.com/hashiiiii/zig-keymap#v0.2.0"
   ```

In `build.zig`, import the `keymap` module:

   ```zig
   const keymap = b.dependency("zig_keymap", .{
       .target = target,
       .optimize = optimize,
   });
   app.root_module.addImport("keymap", keymap.module("keymap"));
   ```

## Usage

Define contexts, actions, and their default keys.
Assume `allocator`, `io` (`std.Io`), `now_ms` (monotonic milliseconds), and a [libvaxis](https://github.com/rockorager/libvaxis) key event `key`:

```zig
const std = @import("std");
const keymap = @import("keymap");
const Context = enum { global, list, modal };
const Action = enum { quit, save, move_down, top, cancel };
const Bindings = keymap.Bindings(Context, Action);

const definition: Bindings.Definition = .{
    .defaults = &.{
        .{ .context = .global, .action = .quit, .keys = &.{"q"} },
        .{ .context = .global, .action = .save, .keys = &.{"Mod+s"} },
        .{ .context = .list, .action = .move_down, .keys = &.{ "Down", "j" } },
        .{ .context = .list, .action = .top, .keys = &.{"g g"} },
        .{ .context = .modal, .action = .cancel, .keys = &.{"Escape"} },
    },
    .context_groups = &.{
        &.{ .global, .list },
        &.{ .global, .modal },
    },
};

comptime {
    Bindings.validateDefaults(definition);
}

const keymap_json = try std.Io.Dir.cwd().readFileAlloc(io, "keymap.json", allocator, .unlimited);
defer allocator.free(keymap_json);

var bindings = switch (try Bindings.loadWithOptions(allocator, definition, keymap_json, .{
    .platform = .macos,
    .modifier_name = .macos,
})) {
    .bindings => |value| value,
    .invalid => |diagnostic| {
        std.log.err("{s}", .{diagnostic.message()});
        return error.InvalidKeymap;
    },
};
defer bindings.deinit();

var receiver = try bindings.receiver(allocator, .{});
defer receiver.deinit();
const action: ?Action = switch (receiver.receive(&.{ .global, .list }, keymap.vaxisMatcher(key), now_ms)) {
    .action => |value| value,
    .pending, .none => null,
};
const label = bindings.hint(.global, .quit);
```

`.invalid` returns a diagnostic.  
`validateDefaults` checks those defaults for macOS, Windows, and Linux at compile time.  
`context_groups` lists contexts that can be active together.  
The example puts `global` with `list` in one group, and `global` with `modal` in another.  
`global` belongs to both groups.  
`load` and `validateDefaults` reject conflicting shortcuts inside one context and inside each group.  
`list` and `modal` share no group, so they may use the same shortcut.  
`receive` passes the active contexts. Here, those contexts are `global` and `list`.  
`loadWithOptions` expands `Mod` for the chosen `.platform`.  
On macOS, `Mod+s` matches Super.  
The OS or terminal may not send `Mod+s` to the app.

`modifier_name` selects the modifier names in `hint` labels. It does not change matching.

`hint` returns the first shortcut label.  

`keymap.json` can replace those defaults:

```json
{
  "global": { "quit": ["Ctrl+q"] },
  "list": { "move_down": [] }
}
```

An action in the JSON replaces its default keys.  
An empty array removes all keys for that action.  
An omitted action keeps its default keys.  

`g g` means two key presses. `keys()` returns every binding for an action.
Each result has one or more `KeyPress` values. `keys()[0][0]` is the first press.

Keep one receiver for each input stream, such as a window. Call `receive` for each key event.
Call `advance` without a key event to check timeouts or context changes. `cancel` clears pending input.

## Development

```sh
mise install
zig fmt build.zig build.zig.zon src e2e
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
```

## API documentation

Read the [API documentation](https://zig-keymap.hashiiiii.workers.dev).

Run `zig build docs` to generate it in `zig-out/docs`.  
The Docs workflow publishes it to Cloudflare Workers when `main` changes.

## License

[Apache License 2.0](LICENSE)
