# zig-keymap

Configurable single-key bindings for Zig terminal applications. Requires Zig 0.16.0.

## Installation

```sh
zig fetch --save=zig_keymap https://github.com/hashiiiii/zig-keymap/archive/refs/heads/main.tar.gz
```

Import the module in `build.zig`:

```zig
const keymap = b.dependency("zig_keymap", .{ .target = target, .optimize = optimize }).module("keymap");
app.root_module.addImport("keymap", keymap);
```

The module has no external dependencies. libvaxis and its dependencies are used only by this repository's tests.

## Usage

Declare application contexts, actions, defaults, and the contexts that can be active together:

```zig
const std = @import("std");
const keymap = @import("keymap");
const Context = enum { global, tree, dialog };
const Action = enum { quit, move_down, cancel };
const Bindings = keymap.Keymap(Context, Action);

const specification: Bindings.Specification = .{
    .defaults = &.{
        .{ .context = .global, .action = .quit, .keys = &.{"q"} },
        .{ .context = .tree, .action = .move_down, .keys = &.{ "Down", "j" } },
        .{ .context = .dialog, .action = .cancel, .keys = &.{"Escape"} },
    },
    .active_contexts = &.{ &.{ .global, .tree }, &.{.dialog} },
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

// Modal input must not invoke global actions.
const action = bindings.resolve(&.{ .global, .tree }, keymap.vaxisMatcher(key));
const label = bindings.hint(.global, .quit);
```

The libvaxis adapter calls the consumer's `Key.matches`. Custom adapters provide `matches(KeySpec) bool`.
The application handles returned actions and loads its configuration file.

### Configuration

```json
{
  "global": { "quit": ["Ctrl+q"] },
  "tree": { "move_down": ["Down", "n"] },
  "dialog": { "cancel": [] }
}
```

Configuration uses strict JSON parsed with `std.json.Value`. Comments and trailing commas are not accepted.
Convert existing TOML configuration to JSON before loading it. Pass `null` to `load` to use all defaults.
Unspecified actions retain their defaults. Arrays replace all keys for an action. `[]` disables the action.
Unknown names, invalid values, duplicate JSON fields, and conflicting bindings return a diagnostic.
Exact collisions and equivalent ASCII Shift spellings are rejected across declared active context groups.
Other terminal matching overlaps resolve in active context order, then default declaration order.

### Keys

Use one Unicode character or a named key, with optional `Ctrl+`, `Alt+`, `Shift+`, `Super+`, `Meta+`, or `Hyper+` prefixes.
Modifier and named-key names are case insensitive. Character case is preserved.
Examples: `j`, `Ctrl+Enter`, `Shift+v`, `あ`, `+`, `Ctrl++`.

Named keys: `Up`, `Down`, `Left`, `Right`, `Enter`, `Escape`, `Tab`, `Backspace`, `Delete`, `Home`, `End`, `PageUp`, `PageDown`, `Insert`, `Space`, `F1`–`F12`.

### Ownership

`load` owns the effective bindings. `keys` and `hint` return slices valid until `deinit`.
Diagnostics store their messages by value; syntax errors include `line` and `column`.
Input JSON can be freed after loading. Resolution and hint lookup allocate no memory.

## Development

```sh
mise install
zig build test
zig build test -Doptimize=ReleaseSafe
zig fmt --check build.zig build.zig.zon src e2e
```

CI also builds a minimal consumer with an empty external package directory to prevent dependencies from becoming required by consumers.

## Releasing

Run the [Release workflow](https://github.com/hashiiiii/zig-keymap/actions/workflows/release.yml) from `main` with a version such as `0.1.0`.
It uses `bump-my-version` to update `build.zig.zon` and `.bumpversion.toml`, pushes the version commit and `vX.Y.Z` tag, and creates a GitHub release with generated notes.
The workflow requires CI to pass for the selected commit. It needs no compiler or additional secrets.
CI for a new version commit starts separately, so release does not wait for another test run.

## License

Apache-2.0. See [LICENSE](LICENSE).
