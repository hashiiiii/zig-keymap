# Terminal validation

This page separates library behavior, native build coverage, and terminal input observations. Adapter tests use real `libvaxis.Key` values, but they do not claim that an operating system or terminal produced those values.

## Matching policy

`Keyboard.parse` resolves modifier aliases to the same flags. For example, `Option+k` and `Alt+k` are equivalent configured keys. `Keyboard.equivalent` detects these configuration collisions before input arrives.

The terminal decides whether macOS Option reaches the application as Alt or as text. Configure the terminal accordingly when testing shortcuts; a keymap alias cannot change terminal behavior. For example, Ghostty has a `macos-option-as-alt` setting.

Choose `Platform` for the operating system whose keyboard sends input. The build target does not select it, which matters when a client runs remotely. `Keyboard.parseForPlatform("Mod+s", .macos)` resolves to `Super+s`; `.windows` and `.linux` resolve it to `Ctrl+s`. Explicit `Ctrl` and `Super` keep their meanings on every platform. `Bindings.loadWithOptions` applies the same choice to defaults and JSON overrides before checking for conflicts. With no platform selected, keys remain concrete-only and `Mod` is invalid.

Choose `DisplayStyle` separately when formatting labels with `hint()`. It can display macOS `Option` and `Command`, Windows `Alt` and `Win`, Linux `Alt` and `Super`, or the common `Ctrl`, `Alt`, `Shift`, and `Super` names. Display style changes labels only; it does not change matching or collision checks.

`vaxisMatcher` calls libvaxis `Key.matches`. It compares the event's codepoint, text, shifted codepoint, and modifiers. It does not use `base_layout_codepoint`, so a logical key binding does not become a physical-key binding based on a layout hint.

AltGr has no separate flag in `Keyboard`. The matcher uses only the key and modifiers that the terminal reports. It does not infer AltGr from a character or from a layout name.

Configuration checks detect equivalent definitions. They cannot predict every native overlap. For example, libvaxis may match a shifted punctuation event against both `Shift+;` and `:`. A Caps Lock event can also match more than one logical character when its codepoint and text differ. `Bindings.resolve` keeps deterministic behavior by checking active contexts in the supplied order and bindings in default declaration order.

The probe resolves `.key_press` events and records their decoded fields. Paste events appear separately with a byte count, no action, and no label. Applications choose shortcut handling through their active context.

Text input handling remains the application's responsibility.

## Run the probe

Build the repository-only probe with Zig `0.16.0`:

```sh
zig build terminal-probe
```

Run it inside the terminal and pass the OS version and keyboard layout as reported by the host:

```sh
zig build run-terminal-probe -- --os-version "27.0 (Build 26A428)" --layout "ABC (source ID com.apple.keylayout.ABC; physical layout unrecorded)"
```

On macOS, get the version with `sw_vers`. On Linux, use `uname -sr`. On Windows, use `winver` or `cmd /c ver`. Record both the active input source and the physical keyboard layout when they differ.

The probe prints one JSON record per key press. Each record includes the OS tag and version, terminal environment, protocol status, keyboard layout, key fields, action, and label.

`keyboard_protocol` is `kitty` when libvaxis detects Kitty keyboard support. Otherwise it is `not-detected-by-libvaxis`, which does not identify other encodings.

Press Escape to record the final key and exit. Use physical key presses for the checks. Do not use paste or injected escape bytes as evidence of keyboard behavior. The probe records paste events separately and does not resolve them as shortcuts.

For each run, record the OS version, terminal name and version, `keyboard_protocol`, keyboard layout, input, event record, action, and label. Check Ctrl, Alt or Option, Shift, and Super or Command/Windows where the terminal delivers them. Also try Caps Lock, Unicode input, an AltGr combination where available, and keys whose logical character differs between US and JIS layouts. If a key does not reach the probe, record it as intercepted or unsupported rather than inferring an event.

## Evidence status

The repository test suite checks the adapter with libvaxis key values, including modifier aliases, Caps Lock text, Unicode, explicit Ctrl+Alt flags, and native shifted-key overlap. Those checks do not establish OS keyboard behavior.

GitHub Actions runs Debug and ReleaseSafe library tests and dependency-free consumer checks on native Linux, macOS, and Windows runners. Those checks establish build and public API behavior; they do not establish that a terminal delivers a particular key.

Host metadata collected separately from the probe: macOS 27.0 build 26A428, Ghostty 1.3.1, `TERM_PROGRAM=ghostty`, `TERM=xterm-256color`, and active input source `com.apple.keylayout.ABC`. The physical keyboard layout and terminal-delivered key events were not recorded. The computer-use safety review rejected opening Ghostty for this probe, so no physical input was collected here.

No physical terminal input results are recorded yet. Add a row only after running the probe with physical input and retaining the complete JSON record and environment details.

| OS and version | Terminal and version | Protocol | Layout | Input and libvaxis event | Action and label | Status |
| --- | --- | --- | --- | --- | --- | --- |
| macOS | pending | pending | pending | pending | pending | pending physical input |
| Windows | pending | pending | pending | pending | pending | pending physical input |
| Linux | pending | pending | pending | pending | pending | pending physical input |

For macOS Option behavior, see [Ghostty's `macos-option-as-alt` setting](https://ghostty.org/docs/config/reference#macos-option-as-alt). For the enhanced terminal key event fields, see the [Kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/).
