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
zig fetch --save=zig_keymap "git+https://github.com/hashiiiii/zig-keymap#v0.5.1"
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

Pass only the contexts enabled for the current input to `receive`, in priority order.  
Bindings in omitted contexts are inactive.

```zig
const std = @import("std");
const keymap = @import("keymap");
const vaxis = @import("vaxis");

const Context = enum { global, list };
const Action = enum { quit, down, up, top };
const Bindings = keymap.Bindings(Context, Action);
const Event = union(enum) { key_press: vaxis.Key };

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const json: ?[]u8 = std.Io.Dir.cwd().readFileAlloc(io, "keymap.json", allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (json) |text| allocator.free(text);

    var bindings = switch (try Bindings.load(allocator, json orelse @embedFile("keymap.json"))) {
        .bindings => |value| value,
        .invalid => |value| {
            var diagnostic = value;
            defer diagnostic.deinit();
            std.debug.print("{s}\n", .{diagnostic.message});
            if (diagnostic.position) |position| {
                std.debug.print("At {d}:{d}\n", .{ position.line, position.column });
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
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));

    var row: usize = 0;
    const active_contexts: []const Context = &.{ .list, .global };
    while (true) {
        const event = try loop.nextEvent();
        switch (bindings.receive(active_contexts, keymap.libvaxisMatcher(event.key_press))) {
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

Keep the application's initial bindings in `keymap.json` beside the Zig source:

```json
{
  "global": { "quit": ["q", "Cmd+q", "Ctrl+q"] },
  "list": {
    "down": ["Down", "j", "Ctrl+n"],
    "up": ["Up", "k", "Ctrl+p"],
    "top": ["g g"]
  }
}
```

The example embeds this JSON and reads an editable copy from the working directory when present.  
The loaded JSON defines every binding. Empty arrays and omitted actions leave keys unbound.  
Context and action names must belong to the application's enums.

| Method | Purpose |
| --- | --- |
| `load(allocator, json)` | Load JSON and return `.bindings` or `.invalid`. |
| `receive(active_contexts, key)` | Match input in the enabled contexts and return `.none`, `.pending`, or `.action: Action`. |
| `cancel()` | Clear pending keys when focus changes without input. |
| `deinit()` | Free the configuration and input state. |

For an application with a dialog, select contexts from the current view:

```zig
const Context = enum { global, list, dialog };

const active_contexts: []const Context = if (dialog_open)
    &.{ .dialog, .global }
else
    &.{ .list, .global };

const result = bindings.receive(active_contexts, keymap.libvaxisMatcher(event.key_press));
```

While the dialog is open, omitting `list` prevents its bindings from moving the background selection.

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
| Media | `MediaPlay`, `MediaPause`, `MediaPlayPause`, `MediaReverse`, `MediaStop`, `MediaFastForward`, `MediaRewind`, `MediaTrackNext`, `MediaTrackPrevious`, `MediaRecord` |
| Volume | `LowerVolume`, `RaiseVolume`, `MuteVolume` |

Keypad names remain distinct from main-keyboard bindings when the backend reports keypad identity.  
`libvaxisMatcher` uses `base_layout_codepoint` for shortcuts and keypad identity.  
Caps Lock does not imply Shift for ASCII bindings.

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
