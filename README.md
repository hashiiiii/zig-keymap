# zig-keymap

[![Zig](https://img.shields.io/badge/zig-0.16.0-f7a41d.svg?logo=zig&logoColor=white)](https://ziglang.org)
[![License](https://img.shields.io/github/license/hashiiiii/zig-keymap)](LICENSE)
[![Release](https://img.shields.io/github/v/release/hashiiiii/zig-keymap)](https://github.com/hashiiiii/zig-keymap/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/hashiiiii/zig-keymap/ci.yml?branch=main&label=CI)](https://github.com/hashiiiii/zig-keymap/actions/workflows/ci.yml)

JSON key bindings for Zig applications.
Define typed contexts and actions, then receive single keys or sequences such as `g g`.

## Installation

Requires Zig `0.16.0`. The library has no external dependencies.
The examples below use the API on `main`; `v0.3.0` has the previous interface.

```sh
zig fetch --save=zig_keymap "git+https://github.com/hashiiiii/zig-keymap#main"
```

Import `keymap` in `build.zig`:

```zig
const keymap = b.dependency("zig_keymap", .{
    .target = target,
    .optimize = optimize,
});
app.root_module.addImport("keymap", keymap.module("keymap"));
```

## Usage

This example reads keyboard input with [libvaxis](https://github.com/rockorager/libvaxis) and prints a row counter.

```zig
const std = @import("std");
const keymap = @import("keymap");
const vaxis = @import("vaxis");

const Context = enum { global, list };
const Action = enum { quit, down, top };
const Bindings = keymap.Bindings(Context, Action);
const Event = union(enum) { key_press: vaxis.Key };
const defaults: []const Bindings.Default = &.{
    .{ .context = .global, .action = .quit, .keys = &.{ "q", "Cmd+q" } },
    .{ .context = .list, .action = .down, .keys = &.{ "Down", "j" } },
    .{ .context = .list, .action = .top, .keys = &.{"g g"} },
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const json = try std.Io.Dir.cwd().readFileAlloc(io, "keymap.json", allocator, .unlimited);
    defer allocator.free(json);

    var bindings = try Bindings.load(allocator, defaults, json);
    defer bindings.deinit();

    var tty_buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &tty_buffer);
    defer tty.deinit();
    var vx = try vaxis.init(io, allocator, init.environ_map, .{});
    defer vx.deinit(allocator, tty.writer());
    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    var row: usize = 0;
    while (true) {
        const event = try loop.nextEvent();
        switch (bindings.receive(&.{ .global, .list }, keymap.libvaxisMatcher(event.key_press))) {
            .action => |action| switch (action) {
                .quit => return,
                .down => row +|= 1,
                .top => row = 0,
            },
            .pending, .none => continue,
        }
        std.debug.print("Row: {d}\r\n", .{row});
    }
}
```

Save `keymap.json`:

```json
{
  "global": { "quit": ["Ctrl+q"] },
  "list": { "down": ["Ctrl+n"] }
}
```

Arrays replace an action's default keys. `[]` disables it. Omitted actions keep their defaults, including `top` above.
Only pairs listed in `defaults` can be configured. Use `.keys = &.{}` to declare an action without default keys.

| Method | Purpose |
| --- | --- |
| `load(allocator, defaults, json)` | Load JSON overrides; `null` keeps defaults. |
| `receive(contexts, key)` | Return `.none`, `.pending`, or `.action: Action`. |
| `cancel()` | Clear pending keys when focus changes without input. |
| `deinit()` | Free the configuration and input state. |

Pass a `KeyPress` directly, or use `libvaxisMatcher` for native text and Shift matching.
Other backends can pass a type with `matches(KeyPress) bool`.
Create one `Bindings` instance per input stream.

Active-context order sets priority, followed by default declaration order.
Loading rejects sequence prefixes within a context and equivalent keys assigned to different actions.
A mismatch retries the input as a new binding. Input in another context clears inactive prefixes.
Sequences have no timeout; call `cancel()` when focus changes without input.

## Keys

Characters keep their case. Named keys and modifier names ignore case.
Use `Ctrl++` for plus, `Space` within a sequence, and spaces between successive presses.

| Modifier | Accepted names |
| --- | --- |
| Ctrl | `Ctrl`, `Control` |
| Alt | `Alt`, `Option`, `Opt` |
| Super | `Super`, `Command`, `Cmd`, `Win`, `Windows` |
| Shift | `Shift` |
| Meta | `Meta` |
| Hyper | `Hyper` |

These names work on every target. The input backend must report the configured key and modifiers.
`KeyPress.parse` converts a string to typed input; `KeyPress.matches` compares key presses.

## Migration from v0.3.0

Pass `[]const Bindings.Default` directly to `load` and handle failures with `try` or `catch`.
Call `receive` and `cancel` on `Bindings`. Use `KeyPress.matches` in place of `equivalent`.

`Definition`, `Receiver`, `LoadResult`, `Diagnostic`, `loadWithOptions`, and `context_groups` were removed.
Cross-context overlaps now follow the order passed to `receive`.
Clock arguments, timeouts, `advance`, and `validateDefaults` were removed; loading validates the configuration.

`Platform`, `ModifierName`, key accessors, and label formatting were removed.
Use concrete modifiers such as `Cmd` or `Ctrl` in place of `Mod`.

## Development

```sh
mise install
zig fmt build.zig build.zig.zon src e2e
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
```

## API documentation

Read the [API documentation](https://zig-keymap.hashiiiii.workers.dev).
Run `zig build docs` to generate `zig-out/docs`.
The Docs workflow publishes it when `main` changes.

## License

[Apache License 2.0](LICENSE)
