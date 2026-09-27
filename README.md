# zig-keymap

[![License](https://img.shields.io/github/license/hashiiiii/zig-keymap)](LICENSE)
[![Release](https://img.shields.io/github/v/release/hashiiiii/zig-keymap)](https://github.com/hashiiiii/zig-keymap/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/hashiiiii/zig-keymap/ci.yml?branch=main&label=CI)](https://github.com/hashiiiii/zig-keymap/actions/workflows/ci.yml)
[![Zig](https://img.shields.io/badge/zig-0.16.0-f7a41d.svg?logo=zig&logoColor=white)](https://ziglang.org)

zig-keymap maps keys to actions in Zig terminal applications.  
Applications define defaults in Zig, and users can change them with JSON configuration.

## Installation

zig-keymap requires Zig `0.16.0` and has no external dependencies.

Add `zig_keymap` to `build.zig.zon`:

   ```sh
   zig fetch --save=zig_keymap "git+https://github.com/hashiiiii/zig-keymap#v0.1.0"
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

A context is a view or mode. Define contexts, actions, and their default keys.  
Provide `allocator`, `io` (`std.Io`), and a [libvaxis](https://github.com/rockorager/libvaxis) key event named `key`:

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
`load` checks for conflicts within each context and group.

`resolve` returns the first matching action, or `null` if none match.  
It checks active contexts in order, then bindings in `specification.defaults` order.

`hint` returns the first key label, or an empty string. `keys` returns configured `Keyboard` values.  
Both results remain valid until `bindings.deinit()`. Do not free them separately.

### Configuration

The library has no default file path. This example reads `keymap.json` from the current working directory.  
For another location, pass `config/keymap.json` (relative to that directory) or `/path/to/keymap.json` (absolute) to `readFileAlloc`.

Use this JSON in `keymap.json`:

```json
{
  "global": { "quit": ["Ctrl+q"] },
  "list": { "move_down": ["Down", "n"] },
  "dialog": { "cancel": [] }
}
```

`load` parses the JSON text. To use `specification.defaults`, pass `null`.

| JSON | Keys |
| --- | --- |
| Missing action | Keeps its default keys |
| Non-empty array | Replaces its default keys |
| Empty array (`[]`) | Removes all keys |

`load` returns a diagnostic for unknown names, invalid values or keys, duplicate fields, or key conflicts.

### Keys

Use a character or key name:

| Type | Keys |
| --- | --- |
| Character | One Unicode codepoint, such as `j`, `あ`, or `+` |
| Arrows | `Up`, `Down`, `Left`, `Right` |
| Navigation | `Home`, `End`, `PageUp`, `PageDown` |
| Editing | `Backspace`, `Delete`, `Insert` |
| Other keys | `Enter`, `Escape`, `Tab`, `Space` |
| Function keys | `F1`–`F12` |

Combine `Ctrl`, `Alt`, `Shift`, `Super`, `Meta`, or `Hyper` with `+`:

| Format | Examples |
| --- | --- |
| One key | `j`, `あ`, `Enter`, `+` |
| Modifier + key | `Ctrl+Enter`, `Shift+v`, `Ctrl++` |
| Several modifiers + key | `Ctrl+Shift+Enter` |

Key and modifier names ignore case. Character keys keep their case.  
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
Run `zig build docs` to generate it in `zig-out/docs`.  
The Docs workflow publishes it to Cloudflare Workers when `main` changes.

## License

[Apache License 2.0](LICENSE).
