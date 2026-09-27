# zig-keymap

A library for keyboard shortcuts in Zig terminal applications. Define default shortcuts in Zig and let users change them with JSON settings.

- Define shortcuts for global actions, views, and modal dialogs.
- Assign several keys to each action. Users can change or disable its shortcuts while keeping defaults for other actions.
- Check settings for invalid keys and conflicts between contexts that can be active together.
- Get shortcut labels for help text.
- Match [libvaxis](https://github.com/rockorager/libvaxis) key events with the included `vaxisMatcher` helper.

Requires Zig `0.16.0`. The library has no external dependencies.

## Installation

1. Add `zig_keymap` to your application's `build.zig.zon`:

   ```sh
   zig fetch --save=zig_keymap "git+https://github.com/hashiiiii/zig-keymap#v0.1.0"
   ```

2. In your `build.zig`, add the `keymap` module to your application:

   ```zig
   const keymap = b.dependency("zig_keymap", .{
       .target = target,
       .optimize = optimize,
   });
   app.root_module.addImport("keymap", keymap.module("keymap"));
   ```

## Usage

Declare application contexts, actions, defaults, and the contexts that can be active together:

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

const loaded = try Bindings.load(allocator, specification, optional_json);
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

`context_groups` lists contexts that can be used together. `load` checks each group for key conflicts.
Pass the active contexts to `resolve`. It returns an action, or `null` if no key matches.

### Configuration

```json
{
  "global": { "quit": ["Ctrl+q"] },
  "list": { "move_down": ["Down", "n"] },
  "dialog": { "cancel": [] }
}
```

Your application reads the JSON file. Pass its text to `load`.
Pass `null` to use the keys in `specification.defaults`.

Actions missing from the JSON keep their default keys.
A key array replaces the default keys for that action. `[]` removes all keys for that action.

If the settings have errors, `load` returns a diagnostic.
Errors include unknown names, invalid values or keys, duplicate fields, and key conflicts.

### Keys

Use a character or a key name.

| Type | Keys |
| --- | --- |
| Character | One Unicode character, such as `j`, `あ`, or `+` |
| Arrows | `Up`, `Down`, `Left`, `Right` |
| Navigation | `Home`, `End`, `PageUp`, `PageDown` |
| Editing | `Backspace`, `Delete`, `Insert` |
| Other keys | `Enter`, `Escape`, `Tab`, `Space` |
| Function keys | `F1`–`F12` |

Add one or more modifiers with `+`: `Ctrl`, `Alt`, `Shift`, `Super`, `Meta`, `Hyper`.

| Format | Examples |
| --- | --- |
| One key | `j`, `あ`, `Enter`, `+` |
| Modifier + key | `Ctrl+Enter`, `Shift+v`, `Ctrl++` |
| Several modifiers + key | `Ctrl+Shift+Enter` |

Key names and modifier names ignore case. Character keys keep their case.

## API documentation

Read the [API documentation](https://zig-keymap.hashiiiii.workers.dev).

Generate API documentation with `zig build docs`. The output is in `zig-out/docs`.

The Docs workflow publishes it to Cloudflare Workers when `main` changes.

## License

[Apache License 2.0](LICENSE)
