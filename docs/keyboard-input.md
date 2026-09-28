# Keyboard input and native matching

`Bindings.load` compares configured shortcuts before it sees terminal input.
It rejects equivalent shortcuts in one context or in contexts listed together in `context_groups`.

| Configured shortcuts | Load-time result |
| --- | --- |
| `Option+k` and `Alt+k` | Equivalent |
| `Mod+k` and `Super+k` on macOS | Equivalent when `platform` is `.macos` |
| `Mod+k` and `Ctrl+k` on Windows or Linux | Equivalent when `platform` is `.windows` or `.linux` |
| `J` and `Shift+j` | Equivalent |
| `Space` and a literal space | Equivalent |

`vaxisMatcher` calls the received libvaxis key's `matches` method.
That method can use `codepoint`, `text`, and `shifted_codepoint`, and it ignores Caps Lock and Num Lock for exact matches.
`vaxisMatcher` does not use `base_layout_codepoint` to infer a physical key.
These event fields can make two shortcuts match the same input even when their configured values differ:

| Example `vaxis.Key` fields | Possible matching shortcuts |
| --- | --- |
| `codepoint = ';'`, `text = ":"`, `mods.shift = true` | `Shift+;` and `:` |
| `codepoint = 'j'`, `text = "J"`, `mods.caps_lock = true` | `j` and `J` |
| `codepoint = 'あ'`, `base_layout_codepoint = 'x'` | `あ`; the layout hint alone does not match `x` |

When native matches overlap, `Bindings.resolve` checks `active_contexts` in the caller's order, then defaults in declaration order.
`SequenceResolver.feed` uses the same order and lets an earlier pending sequence finish before a later completed shortcut.

The library cannot identify AltGr from a `vaxis.Key` that contains only Ctrl and Alt modifier flags.
It also cannot determine whether the OS or terminal intercepted a key before libvaxis received it.
When an application accepts text input, it decides which events to send to `resolve` or `feed`; `vaxisMatcher` may match the event's `text` field.

## Record terminal observations

The repository tests construct libvaxis key values, and CI runs them on macOS, Windows, and Linux.
Those checks do not record keys delivered by a physical keyboard and terminal.
For each target OS, use a consuming application's real event loop to record the event before matching it.
Record the resolved action and `hint` for that action.
Record one row per input, including inputs intercepted before the application receives an event.

| OS and version | Terminal and version | Protocol | Layout | Physical input | Received `codepoint`, `text`, `shifted_codepoint`, `base_layout_codepoint`, `mods` | Action | Label | Limitation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | | |

Check Ctrl, Alt/Option, Shift, and Super/Command/Win where the terminal delivers them.
Also check Caps Lock, a Unicode character, AltGr where available, and the relevant US or JIS layout.
For an intercepted or unsupported combination, record the missing event or missing modifier and the terminal setting used.
