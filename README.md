# zig-keymap

[![Zig](https://img.shields.io/badge/zig-0.16.0-f7a41d.svg?logo=zig&logoColor=white)](https://ziglang.org)
[![License](https://img.shields.io/github/license/hashiiiii/zig-keymap)](LICENSE)
[![Release](https://img.shields.io/github/v/release/hashiiiii/zig-keymap)](https://github.com/hashiiiii/zig-keymap/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/hashiiiii/zig-keymap/ci.yml?branch=main&label=CI)](https://github.com/hashiiiii/zig-keymap/actions/workflows/ci.yml)

JSON key bindings for Zig applications.  
Define typed contexts and actions, then receive single keys or sequences such as `g g`.

## Installation

Requires Zig `0.16.0`. The library has no external dependencies.

```sh
zig fetch --save=zig_keymap "git+https://github.com/hashiiiii/zig-keymap#v0.4.0"
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
const Action = enum { quit, down, up, top };
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

    var bindings = switch (try Bindings.load(allocator, defaults, json)) {
        .bindings => |value| value,
        .invalid => |value| {
            var diagnostic = value;
            defer diagnostic.deinit();
            std.debug.print("{s}\n", .{diagnostic.message});
            if (diagnostic.line) |line| {
                std.debug.print("At {d}:{d}\n", .{ line, diagnostic.column.? });
            }
            return error.InvalidKeymap;
        },
    };
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
                .up => row -|= 1,
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
  "list": { "down": ["Ctrl+n"], "up": ["Ctrl+p"] }
}
```

Arrays replace an action's default keys. `[]` disables it. Omitted actions keep their defaults, including `top` above.  
JSON accepts every pair from the Context and Action enums, including `up` above.  
Pass `&.{}` as `defaults` to assign all keys in JSON.

| Method | Purpose |
| --- | --- |
| `load(allocator, defaults, json)` | Return `.bindings` or `.invalid`; `null` keeps defaults. |
| `receive(contexts, key)` | Return `.none`, `.pending`, or `.action: Action`. |
| `cancel()` | Clear pending keys when focus changes without input. |
| `deinit()` | Free the configuration and input state. |

An invalid configuration returns a `Diagnostic` with a `kind` and an owned `message`.  
Messages identify affected names and key expressions; JSON syntax errors also include `line` and `column`, starting at 1.  
Call `deinit()` on the selected payload. Only allocation failures return `error.OutOfMemory`.

Pass a `KeyPress` directly, or use `libvaxisMatcher` for native text and Shift matching.  
Other backends can pass a type with `matches(KeyPress) bool`.  
Create one `Bindings` instance per input stream.

Active-context order sets priority, followed by default declaration order and then new pairs in JSON order.  
Loading rejects sequence prefixes within a context and equivalent keys assigned to different actions.  
A mismatch retries the input as a new binding. Input in another context clears inactive prefixes.  
Sequences have no timeout; call `cancel()` when focus changes without input.

## Keys

Characters keep their case; ASCII uppercase matches the lowercase letter with Shift, so `J` equals `Shift+j`.  
Named keys and modifier names ignore case.  
Use `Ctrl++` for plus, `Space` for the space key, and spaces between successive presses.  

| Named keys | Accepted names |
| --- | --- |
| Navigation | `Up`, `Down`, `Left`, `Right`, `Home`, `End`, `PageUp`, `PageDown`, `Insert`, `Delete` |
| Editing | `Enter`, `Escape`, `Tab`, `Backspace`, `Space` |
| Function | `F1`–`F35` |
| System | `CapsLock`, `ScrollLock`, `NumLock`, `PrintScreen`, `Pause`, `Menu` |
| Keypad digits | `Keypad0`–`Keypad9` |
| Keypad operations | `KeypadDecimal`, `KeypadDivide`, `KeypadMultiply`, `KeypadSubtract`, `KeypadAdd`, `KeypadEnter`, `KeypadEqual`, `KeypadSeparator` |
| Keypad navigation | `KeypadLeft`, `KeypadRight`, `KeypadUp`, `KeypadDown`, `KeypadPageUp`, `KeypadPageDown`, `KeypadHome`, `KeypadEnd`, `KeypadInsert`, `KeypadDelete`, `KeypadBegin` |

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

## License

[Apache License 2.0](LICENSE)
