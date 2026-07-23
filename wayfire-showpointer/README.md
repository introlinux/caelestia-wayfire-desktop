# wayfire-showpointer

Wayfire plugin that draws the audience's attention to the mouse pointer, for
presentations, screencasts and video tutorials — or simply for finding a lost
cursor on a large screen.

It provides four independent effects, all centered on the pointer:

| Effect | What it looks like | How it is triggered |
| --- | --- | --- |
| **Attention burst** | Rings that shrink towards the pointer and vanish when they reach it | `attention` binding, or shaking the pointer |
| **Spotlight** | Everything dimmed except a soft circle following the pointer | `toggle_spotlight` binding |
| **Halo** | A persistent glow stuck to the pointer, gently pulsating | `toggle_halo` binding |
| **Click ripple** | A ring expanding from every button press, one color per button | Automatic, when `ripple_enabled` is set |

## Building

```sh
meson setup build --prefix=/usr/local --buildtype=release
ninja -C build
sudo ninja -C build install
```

Then add `showpointer` to `plugins` in `~/.config/wayfire.ini`.

> Wayfire only scans plugin metadata at startup, so after installing a **new**
> plugin you have to log out and back in — enabling it in a running session
> fails with "No such option".

## Configuration

Everything is configurable from WCM under *Effects → Show Pointer*, or by hand:

```ini
[showpointer]
attention = <super> KEY_P
toggle_spotlight = <super> <shift> KEY_P
toggle_halo = <super> <alt> KEY_P
ripple_enabled = true
shake_enabled = true
```

Notable options:

- `ring_radius` / `ring_count` / `ring_width` / `burst_duration` — shape and
  timing of the attention burst.
- `shake_reversals` / `shake_distance` / `shake_timeout` — how vigorous a shake
  has to be. Shake detection samples absolute cursor positions, so it works
  with mice, touchpads and tablets alike. It is off by default because brisk
  normal movement can occasionally look like a shake.
- `spotlight_radius` / `spotlight_feather` / `spotlight_color` — size, edge
  softness and strength of the dimming.
- `halo_pulse` — set to `0` to get a steady glow instead of a pulsating one.
- `ripple_color_left` / `_right` / `_middle` — per-button ripple colors.

## Implementation notes

No shaders are used, so the plugin works on every wlroots renderer rather than
only on GLES2. Each effect draws a single texture baked with cairo
(`wf::owned_texture_t`), scaled per frame through
`render_pass_t::add_texture()`; the spotlight adds four plain rectangles for
the dimmed area around the hole. Textures are re-baked only when the relevant
options or the output scale change, never per frame.

While an effect is running the output is damaged in full on every frame. This
is deliberate rather than lazy: the effects are drawn translucently over the
scene, so any area not repainted from scratch would accumulate the same texture
frame after frame until it turned solid, and a pointer that lives in a hardware
cursor plane emits no damage of its own, so partial damage would also stall the
animation whenever the pointer stopped moving. The cost is bounded — bursts and
ripples last well under a second, and the halo and spotlight are explicit
presentation modes. When no effect is running the render hooks are detached
entirely and the plugin costs nothing.

## License

MIT.
