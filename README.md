# zig-keymap

[![License](https://img.shields.io/github/license/hashiiiii/zig-keymap)](LICENSE)
[![Release](https://img.shields.io/github/v/release/hashiiiii/zig-keymap)](https://github.com/hashiiiii/zig-keymap/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/hashiiiii/zig-keymap/ci.yml?branch=main&label=CI)](https://github.com/hashiiiii/zig-keymap/actions/workflows/ci.yml)
[![Zig](https://img.shields.io/badge/zig-0.16.0-f7a41d.svg?logo=zig&logoColor=white)](https://ziglang.org)

zig-keymap maps keys to actions in Zig terminal applications.  
Applications define defaults in Zig, and users can change them with JSON configuration.  
Bindings support platform modifiers, shortcut labels, and sequences of key presses.

## Installation

zig-keymap requires Zig `0.16.0` and has no external dependencies.

For the released API, use the [README at the release tag](https://github.com/hashiiiii/zig-keymap/blob/v0.1.0/README.md).
Add that release as `zig_keymap` in `build.zig.zon`:

   ```sh
   zig fetch --save=zig_keymap "git+https://github.com/hashiiiii/zig-keymap#v0.1.0"
   ```

The usage below follows `main`, which may contain unreleased APIs. To try it, fetch `main`:

   ```sh
   zig fetch --save=zig_keymap "git+https://github.com/hashiiiii/zig-keymap#main"
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
Provide `allocator`, `io` (`std.Io`), monotonic milliseconds named `now_ms`, and a [libvaxis](https://github.com/rockorager/libvaxis) key event named `key`:

```zig
const std = @import("std");
const keymap = @import("keymap");
const Context = enum { global, list };
const Action = enum { quit, save, move_down, top };
const Bindings = keymap.Bindings(Context, Action);

const definition: Bindings.Definition = .{
    .defaults = &.{
        .{ .context = .global, .action = .quit, .keys = &.{"q"} },
        .{ .context = .global, .action = .save, .keys = &.{"Mod+s"} },
        .{ .context = .list, .action = .move_down, .keys = &.{ "Down", "j" } },
        .{ .context = .list, .action = .top, .keys = &.{"g g"} },
    },
    .context_groups = &.{&.{ .global, .list }},
};

comptime {
    Bindings.validateDefaults(definition);
}

const keymap_json = try std.Io.Dir.cwd().readFileAlloc(io, "keymap.json", allocator, .unlimited);
defer allocator.free(keymap_json);

var bindings = switch (try Bindings.loadWithOptions(allocator, definition, keymap_json, .{
    .platform = .macos,
    .display_style = .macos,
})) {
    .bindings => |value| value,
    .invalid => |diagnostic| {
        std.log.err("{s}", .{diagnostic.message()});
        return error.InvalidKeymap;
    },
};
defer bindings.deinit();

var resolver = try bindings.sequenceResolver(allocator, .{});
defer resolver.deinit();
const action: ?Action = switch (resolver.feed(&.{ .global, .list }, keymap.vaxisMatcher(key), now_ms)) {
    .action => |value| value,
    .pending, .none => null,
};
const label = bindings.hint(.global, .quit);
```

`.invalid` returns a diagnostic.  
`validateDefaults` checks those defaults for macOS, Windows, and Linux at compile time.  
`context_groups` lists contexts that can be active together.  
`loadWithOptions` expands `Mod` for the chosen `.platform`.  
On macOS, `Mod+s` matches Super.  
The terminal must deliver that modifier in its key event; the OS or terminal may intercept a shortcut first.

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

A key string can name successive presses, such as `g g`.  
Create the resolver once and reuse it for each key event. `feed` matches single keys and sequences, so do not also call `resolve` for the same event.
Call `advance` when time or active contexts change without a key event. Call `cancel` to clear a pending sequence.
For bindings without sequences, `resolve` matches a single event without a resolver.

## Development

```sh
mise install
zig fmt build.zig build.zig.zon src e2e
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
```

To prepare a release, run `bump-my-version bump --new-version X.Y.Z` in a PR and merge it after CI passes. Then run the Release workflow on `main` with the same version.

## API documentation

Read the [API documentation for `main`](https://zig-keymap.hashiiiii.workers.dev). It may describe APIs that are not in the latest release.
Run `zig build docs` to generate it in `zig-out/docs`.  
The Docs workflow publishes it to Cloudflare Workers when `main` changes.

## License

[Apache License 2.0](LICENSE)
