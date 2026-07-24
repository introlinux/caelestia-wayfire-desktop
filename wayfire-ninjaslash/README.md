# wayfire-ninjaslash

A Wayfire **close animation** that slices the window in two along a fast sword
stroke, Fruit-Ninja style: a glowing blade sweeps across the window, then the two
halves separate perpendicular to the cut, spin, fall with gravity and fade off the
screen edges.

It registers itself as a named effect in the `animate` plugin's shared effects
registry, so it plugs in exactly like the built-in animations — no core patching.

## Requirements

- Wayfire ≥ 0.10.0, running the **GLES2** renderer (the plugin bails out with a
  log message on other renderers).
- The `animate` plugin (ships with Wayfire).

## Build & install

```sh
meson setup build --prefix=/usr/local --buildtype=release
ninja -C build
sudo ninja -C build install
```

This installs `libninjaslash.so` into Wayfire's plugin directory and
`ninjaslash.xml` into its metadata directory.

## Usage

Add `ninjaslash` to your `plugins` list and select it as the close animation:

```ini
[core]
plugins = ... animate ninjaslash

[animate]
close_animation = ninjaslash
```

Metadata is only scanned at Wayfire startup, so **log out and back in** after
installing.

## Options (`[ninjaslash]`)

| Option | Default | Meaning |
| --- | --- | --- |
| `duration` | `800ms circle` | Length of the whole slash. |
| `pattern` | `random` | `random` picks a fresh pattern per close; `parallel` uses `cuts` parallel strokes; `cross` uses two perpendicular strokes (4 pieces). |
| `cuts` | `1` | Parallel pattern only: number of sword strokes, each sweeping in order. `N` cuts leave `N+1` pieces. Ignored for `random`/`cross`. |
| `random_angle` | `true` | Pick a fresh slash direction on every close. |
| `angle` | `30` | Fixed cut angle in degrees (used when `random_angle` is off). With `cross`, `45` gives an X and `0` a plus. |
| `curve` | `0.35` | How much the cuts bow, like a real sword stroke. `0` = dead straight; parallel cuts become concentric arcs and the trail follows the same curve. |
| `spread` | `1.0` | How far the pieces fly apart perpendicular to the cut. |
| `gravity` | `1.0` | Downward pull on the flying pieces. |
| `fade` | `true` | Fade the pieces out near the end. When off, they stay opaque and are guaranteed to fly fully past the screen edge instead. |
| `blade_enabled` | `true` | Draw the glowing sword trail. |
| `blade_color` | `0.8 1.0 1.0 1.0` | Blade color; alpha scales brightness. |
| `blade_width` | `6.0` | Thickness of the bright core of the trail, in pixels. |
| `sound_enabled` | `true` | Play a sword-swish sound as **each** stroke lands. |
| `sound_file` | `/usr/local/share/ninjaslash/espada-ninja.mp3` | Audio file, played with `pw-play`. Empty disables it. |
| `sound_volume` | `100` | Playback volume in percent (0-100). |

## How it works

The window content is drawn once per piece as a full-window quad, and the fragment
shader **discards** everything outside that piece's band along the cut normal — so
the window is sliced without any polygon geometry. Pieces are placed with an
orthographic projection in logical coordinates, so at the start of the animation
the "intact" window matches the real one pixel-for-pixel (no perspective pop). The
blade is a separate additive-blended quad drawn along the cut line.

The rendering machinery is modelled on the `shatter` animation from
`wayfire-plugins-extra` (© Scott Moreau, MIT).

## License

MIT.
