# zig-keymap

[![License](https://img.shields.io/github/license/hashiiiii/zig-keymap)](LICENSE)
[![Release](https://img.shields.io/github/v/release/hashiiiii/zig-keymap)](https://github.com/hashiiiii/zig-keymap/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/hashiiiii/zig-keymap/ci.yml?branch=main&label=CI)](https://github.com/hashiiiii/zig-keymap/actions/workflows/ci.yml)
[![Zig](https://img.shields.io/badge/zig-0.16.0-f7a41d.svg?logo=zig&logoColor=white)](https://ziglang.org)

zig-keymap maps keys to actions in Zig terminal applications.  
Define default key bindings in Zig.  
Users can change them with JSON configuration.  

Use zig-keymap to:

- Define bindings for global actions, views, and modal dialogs.
- Assign several keys to each action.
- Check for invalid keys and conflicts between contexts that can be active together.
- Get key labels for help text.
- Match [libvaxis](https://github.com/rockorager/libvaxis) key events with `vaxisMatcher`.

## Installation

zig-keymap requires Zig `0.16.0` and has no external dependencies.

Add `zig_keymap` to your application's `build.zig.zon`:

   ```sh
   zig fetch --save=zig_keymap "git+https://github.com/hashiiiii/zig-keymap#v0.1.0"
   ```

In `build.zig`, add the `keymap` module to your application:

   ```zig
   const keymap = b.dependency("zig_keymap", .{
       .target = target,
       .optimize = optimize,
   });
   app.root_module.addImport("keymap", keymap.module("keymap"));
   ```

## Usage

A context is an application mode or view.  
An action is an application operation.  
A binding assigns keys to a context and action.  

The application provides `allocator`, a `std.Io` value named `io`, and the incoming libvaxis key event `key`.  
Declare the contexts, actions, default keys, and groups of contexts that can be active together:

```zig
const std = @import("std");
const keymap = @import("keymap");
const Context = enum { global, list, dialog };
const Action = enum { quit, move_down, cancel };
const Bindings = keymap.Keymap(Context, Action);

const specification: Bindings.Specification = .{
    .defaults = &.{
        .{ .context = .global, .action = .quit, .keys = &.{"q"} },
        .{ .context = .list, .action = .move_down, .keys = &.{ "Down", "j" } },
        .{ .context = .dialog, .action = .cancel, .keys = &.{"Escape"} },
    },
    .context_groups = &.{ &.{ .global, .list }, &.{.dialog} },
};

const keymap_json = try std.Io.Dir.cwd().readFileAlloc(io, "keymap.json", allocator, .unlimited);
defer allocator.free(keymap_json);

const loaded = try Bindings.load(allocator, specification, keymap_json);
var bindings = switch (loaded) {
    .bindings => |value| value,
    .invalid => |diagnostic| {
        std.log.err("{s}", .{diagnostic.message()});
        return error.InvalidKeymap;
    },
};
defer bindings.deinit();

const action = bindings.resolve(&.{ .global, .list }, keymap.vaxisMatcher(key));
const label = bindings.hint(.global, .quit);
```

`context_groups` lists contexts that can be active together.  
`load` checks each group for key conflicts.  
It also checks for conflicts within each context.  

Pass the current active contexts to `resolve`.  
It returns the first matching action, or `null` if no binding matches.  
It checks contexts in the order you pass, then bindings in the order of `specification.defaults`.  

`hint` returns the first configured key as a label, or an empty string if the action has no keys.  
`keys` returns the configured `Keyboard` values.  
Both results remain valid until `bindings.deinit()`.  
Do not free them separately.

### Configuration

Save the configuration in `keymap.json`:

```json
{
  "global": { "quit": ["Ctrl+q"] },
  "list": { "move_down": ["Down", "n"] },
  "dialog": { "cancel": [] }
}
```

Your application reads `keymap.json` as text.  
Pass that text to `load`.  
`load` parses the JSON.  
To use the keys in `specification.defaults`, pass `null`.  

Actions missing from the JSON keep their default keys.  
A JSON array replaces the default keys for that action.  
`[]` removes all keys for that action.  

If the configuration has errors, `load` returns a diagnostic that describes the problem.  
Errors include unknown names, invalid values or keys, duplicate fields, and key conflicts.  

### Keys

A codepoint is a number that identifies a character.  
Use a character or a key name:

| Type | Keys |
| --- | --- |
| Character | One Unicode codepoint, such as `j`, `あ`, or `+` |
| Arrows | `Up`, `Down`, `Left`, `Right` |
| Navigation | `Home`, `End`, `PageUp`, `PageDown` |
| Editing | `Backspace`, `Delete`, `Insert` |
| Other keys | `Enter`, `Escape`, `Tab`, `Space` |
| Function keys | `F1`–`F12` |

Add modifiers with `+`: `Ctrl`, `Alt`, `Shift`, `Super`, `Meta`, `Hyper`.

| Format | Examples |
| --- | --- |
| One key | `j`, `あ`, `Enter`, `+` |
| Modifier + key | `Ctrl+Enter`, `Shift+v`, `Ctrl++` |
| Several modifiers + key | `Ctrl+Shift+Enter` |

Key names and modifier names ignore case.  
Character keys keep their case.

For other terminal libraries, provide a matcher with `matches(Keyboard) bool`.

## Development

```sh
mise install
zig fmt build.zig build.zig.zon src e2e
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
```

## API documentation

Read the [API documentation](https://zig-keymap.hashiiiii.workers.dev).  
To generate it locally, run `zig build docs`.  
The output is in `zig-out/docs`.  
The Docs workflow publishes the documentation to Cloudflare Workers when `main` changes.

## License

[Apache License 2.0](LICENSE).
