# wayfire-intro

Cinematic session-start reveal for Wayfire.

From the very first composited frame every output is covered by an opaque
curtain (black by default), so the desktop never flashes while the shell and
the wallpaper are still loading — the session appears to continue seamlessly
from the login manager's black transition. Once the session is ready, the
curtain opens:

- **split** (default): the curtain parts in two horizontal halves which slide
  off the top and bottom edges, movie style.
- **iris**: a circle opens from the center and grows until the whole desktop
  is revealed.

No shaders are used (plain rects plus one cairo-baked texture), so the plugin
works on any wlroots renderer.

## Trigger

The reveal is triggered through the Wayfire IPC socket: the plugin registers
the methods `intro/reveal` (open the curtain) and `intro/replay` (drop it and
open it again) on the shared method repository, so only the plain `ipc`
plugin needs to be loaded. In this desktop, the shell calls
`caelestia-intro-reveal` the moment the wallpaper is actually visible
(`shell/modules/background/Wallpaper.qml`).

If nothing calls `intro/reveal` within `timeout` milliseconds, the curtain
opens on its own — a broken shell can never leave the session black forever.

## Options (`[intro]`)

| Option        | Type      | Default        | Meaning                                   |
|---------------|-----------|----------------|-------------------------------------------|
| `pattern`     | string    | `split`        | `split` or `iris`                          |
| `duration`    | animation | `1200ms circle`| Length/easing of the opening animation     |
| `timeout`     | int (ms)  | `10000`        | Safety net if `intro/reveal` never arrives |
| `hide_cursor` | bool      | `true`         | Hide the cursor while the curtain is up    |
| `color`       | color     | black          | Curtain color                              |
| `replay`      | activator | none           | Re-run the whole intro (tuning aid)        |

`pattern`, `duration`, `color` and `hide_cursor` are read live, so together
with the `replay` binding (Super+F12 in this desktop) the animation can be
tuned without restarting the session. `timeout` is read once at startup.
