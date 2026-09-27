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

Add `zig_keymap` to `build.zig.zon`:

   ```sh
   zig fetch --save=zig_keymap "git+https://github.com/hashiiiii/zig-keymap#v0.1.0"
   ```

The examples below use APIs added after `v0.1.0`. Fetch `main` to use the latest source:

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

A context identifies where bindings apply. Define contexts, actions, and their default keys.
Provide `allocator`, `io` (`std.Io`), and a [libvaxis](https://github.com/rockorager/libvaxis) key event named `key`:

```zig
const std = @import("std");
const keymap = @import("keymap");
const Context = enum { global, list, dialog };
const Action = enum { quit, save, move_down, cancel };
const Bindings = keymap.Bindings(Context, Action);

const definition: Bindings.Definition = .{
    .defaults = &.{
        .{ .context = .global, .action = .quit, .keys = &.{"q"} },
        .{ .context = .global, .action = .save, .keys = &.{"Mod+s"} },
        .{ .context = .list, .action = .move_down, .keys = &.{ "Down", "j" } },
        .{ .context = .dialog, .action = .cancel, .keys = &.{"Escape"} },
    },
    .context_groups = &.{ &.{ .global, .list }, &.{.dialog} },
};

const keymap_json = try std.Io.Dir.cwd().readFileAlloc(io, "keymap.json", allocator, .unlimited);
defer allocator.free(keymap_json);

const loaded = try Bindings.loadWithOptions(allocator, definition, keymap_json, .{
    .platform = .macos,
    .display_style = .macos,
});
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
It checks active contexts in order, then bindings in `definition.defaults` order.

`hint` returns the first shortcut label, or an empty string. `keys` returns single-key shortcuts.
`sequences` returns every shortcut as a `Sequence`, including single-key shortcuts.
These results remain valid until `bindings.deinit()`. Do not free them separately.

### Platform modifiers and labels

Choose the application's client platform explicitly when loading bindings. This choice can differ from the build target, including over SSH.

| Platform | `Mod+s` | `.display_style` | Alt label | Super label |
| --- | --- | --- | --- | --- |
| `.macos` | `Super+s` | `.macos` | `Option` | `Command` |
| `.windows` | `Ctrl+s` | `.windows` | `Alt` | `Win` |
| `.linux` | `Ctrl+s` | `.linux` | `Alt` | `Super` |

Defaults and JSON overrides expand `Mod` in the same way. Explicit `Ctrl`, `Alt`, and `Super` keep their meaning on every platform.
Expansion precedes duplicate-modifier and collision checks. For example, `Ctrl+Mod+s` is invalid on Windows and Linux.

Use `.display_style = .common` for `Ctrl`, `Alt`, and `Super` labels on any OS.
Display style changes labels only; matching uses the parsed key and modifier flags.
`Bindings.load` keeps common labels and accepts concrete modifiers. Use `loadWithOptions` with `.platform` when bindings contain `Mod`.

Parse and format individual keys with the same choices:

```zig
const shortcut = try keymap.Keyboard.parseForPlatform("Mod+Option+S", .macos);
var buffer: [96]u8 = undefined;
const label = shortcut.formatWithStyle(&buffer, .macos);
```

`label` refers to `buffer`; keep that buffer alive and unchanged while using the label.
This example produces `Option+Command+S`.

### Configuration

The library has no default file path. The example above reads `keymap.json` from the current working directory.

Pass a path relative to that directory:

```zig
const keymap_json = try std.Io.Dir.cwd().readFileAlloc(io, "config/keymap.json", allocator, .unlimited);
defer allocator.free(keymap_json);
```

Pass an absolute path:

```zig
const keymap_json = try std.Io.Dir.cwd().readFileAlloc(io, "/path/to/keymap.json", allocator, .unlimited);
defer allocator.free(keymap_json);
```

Use this JSON in `keymap.json`:

```json
{
  "global": { "quit": ["Ctrl+q"], "save": ["Mod+s"] },
  "list": { "move_down": ["Down", "n"] },
  "dialog": { "cancel": [] }
}
```

`load` and `loadWithOptions` parse JSON text. Pass `null` to use `definition.defaults`.
The `save` override follows the platform table above: Command on macOS and Ctrl on Windows or Linux.

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

Combine modifiers with `+`. These aliases ignore case:

| Modifier | Accepted names |
| --- | --- |
| Ctrl | `Ctrl`, `Control` |
| Alt | `Alt`, `Option`, `Opt` |
| Shift | `Shift` |
| Super | `Super`, `Command`, `Cmd`, `Win`, `Windows` |
| Meta | `Meta` |
| Hyper | `Hyper` |
| Platform modifier | `Mod`, with an explicit platform |

Aliases set the same flags. Repeating a modifier through an alias, such as `Alt+Option+k`, is invalid.

| Format | Examples |
| --- | --- |
| One key | `j`, `あ`, `Enter`, `+` |
| Modifier + key | `Ctrl+Enter`, `Shift+v`, `Ctrl++` |
| Several modifiers + key | `Ctrl+Shift+Enter` |

Key and modifier names ignore case. Character keys keep their case.
For other terminal libraries, provide a matcher with `matches(Keyboard) bool`.

### Compile-time validation

Validate static defaults before the application starts:

```zig
comptime {
    Bindings.validateDefaults(definition);
}
```

The validator checks every macOS, Windows, and Linux expansion.
Invalid keys, duplicate context/action pairs, and overlapping shortcut conflicts fail compilation with a diagnostic.
Runtime loading still validates dynamic definitions and JSON configuration.

### Sequences

Each key string can describe successive presses separated by spaces:

```zig
const Context = enum { list };
const Action = enum { top, next };
const Bindings = keymap.Bindings(Context, Action);
const definition: Bindings.Definition = .{
    .defaults = &.{
        .{ .context = .list, .action = .top, .keys = &.{"g g"} },
        .{ .context = .list, .action = .next, .keys = &.{"Mod+b n"} },
    },
    .context_groups = &.{},
};
```

JSON uses the same strings:

```json
{
  "list": { "top": ["g g"], "next": ["Ctrl+b n"] }
}
```

Use `Space` for a space inside a sequence, such as `g Space`. Aliases and `Mod` apply to each step.
Single-key shortcuts continue to work through `resolve`. To handle both single keys and sequences, create a resolver from loaded bindings:

```zig
var resolver = try bindings.sequenceResolver(allocator, .{ .timeout_ms = 1000 });
defer resolver.deinit();

switch (resolver.feed(&.{.list}, keymap.vaxisMatcher(key), now_ms)) {
    .none => {},
    .pending => {},
    .action => |action| handleAction(action),
}
```

The application supplies monotonic milliseconds in `now_ms` and decides how pending events affect text input.
Each matched step restarts the timeout. Set `.timeout_ms = null` to disable it.
Call `resolver.advance(active_contexts, now_ms)` when time or contexts change without a key event.
Expiration and removal of a pending context clear its partial input. `resolver.cancel()` clears all pending input explicitly.
A mismatched event clears the prefix and is tried as a new shortcut.

Equal shortcuts assigned to different context/action pairs and proper-prefix shortcuts in overlapping contexts are rejected during loading.
For example, `g` conflicts with `g g`; `g g` and `g e` can coexist.
This rule also rejects proper-prefix aliases assigned to the same action.
Native matches that depend on the received event use active context order, then default declaration order.
An earlier pending candidate takes priority over a later completed candidate when native matches overlap.
Free the resolver before freeing its bindings.

### Terminal input

A binding works only when the terminal delivers its input. OS shortcuts and terminal shortcuts can intercept keys, including Command and Win combinations.
On macOS, Option can produce Unicode characters instead of Alt input. Configure the terminal to send Alt when shortcuts need that modifier.
For Ghostty, see [`macos-option-as-alt`](https://ghostty.org/docs/config/reference#macos-option-as-alt).
Unicode text remains character input; the library does not infer AltGr or physical US/JIS keys from text alone.

Legacy terminal protocols cannot identify every modifier combination. Extended keyboard protocols can provide additional key and modifier fields.
See the [kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/) for protocol details.
The adapter uses the event fields and matching rules supplied by libvaxis.

The application remains responsible for file loading, event decoding, client-platform selection, and input routing.

## Development

```sh
mise install
zig fmt build.zig build.zig.zon src e2e
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
```

CI runs library, public API, and dependency-free consumer tests natively on macOS, Windows, and Linux in both modes.

## API documentation

Read the [API documentation](https://zig-keymap.hashiiiii.workers.dev).
Run `zig build docs` to generate it in `zig-out/docs`.
The Docs workflow publishes it to Cloudflare Workers when `main` changes.

## License

[Apache License 2.0](LICENSE).
