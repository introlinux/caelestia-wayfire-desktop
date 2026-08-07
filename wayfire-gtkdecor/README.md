# wayfire-gtkdecor

Wayfire plugin providing server side decorations that look like a GTK/Adwaita
header bar, so that Qt applications, old GTK applications and anything else
which does not draw its own decorations blends in with the rest of a
GNOME-styled desktop.

Compared to Wayfire's built-in `decoration` plugin, which it is a fork of, it
draws:

* **rounded top corners** with a hairline border and a lighter line just inside
  it, and a separator line where the title bar meets the client;
* the title **centred and ellipsized**, as a header bar does, instead of left
  aligned and clipped;
* **flat circular buttons** carrying the `window-close-symbolic`,
  `window-maximize-symbolic` and `window-minimize-symbolic` glyphs, which darken
  on hover and while pressed, instead of the traffic-light circles;
* everything baked at the **output scale**, so it stays crisp on HiDPI outputs.

The bottom corners stay square: they belong to the client, and a server side
decoration cannot round them off.

## Building

```sh
meson setup build --prefix=/usr/local --buildtype=release
ninja -C build
sudo ninja -C build install
```

Then put `gtkdecor` in `plugins` in `~/.config/wayfire.ini` **in place of**
`decoration` — the two must never be enabled at the same time, as both would
decorate the same toplevel.

Wayfire only scans plugin metadata at startup, so log out and back in after
installing the plugin for the first time.

## Options

All sizes are in logical pixels. The defaults reproduce the GTK 4 / libadwaita
light header bar as shipped by Ubuntu.

| Option | Default | Meaning |
| --- | --- | --- |
| `title_height` | `37` | Height of the title bar, top border excluded |
| `border_size` | `1` | Thickness of the border around the window |
| `corner_radius` | `18` | Radius of the two top corners |
| `button_size` | `22` | Diameter of the round buttons |
| `button_padding` | `7` | Gap between the buttons and the window edge |
| `button_spacing` | `6` | Gap between two adjacent buttons |
| `shadow_size` | `24` | How far the drop shadow reaches out, `0` to drop none |
| `shadow_offset` | `6` | How far down the shadow is pushed |
| `font` | `Adwaita Sans Bold 11` | Font of the title |
| `button_order` | `close` | Which buttons to show, out of `minimize`, `maximize`, `close` |
| `active_color` | `#EBEBEBFF` | Title bar background, focused |
| `inactive_color` | `#FAFAFAFF` | Title bar background, unfocused |
| `border_color` | `#9A9A9CFF` | The hairline around the window |
| `highlight_color` | `#FBFBFBFF` | Light line just inside the top border |
| `separator_color` | `#BDBDBDFF` | Line between title bar and client |
| `font_color` | `#3D3D3DFF` | Title and button glyphs, focused |
| `inactive_font_color` | `#3D3D3D80` | Title and button glyphs, unfocused |
| `button_color` | `#00000012` | Round button background at rest |
| `shadow_color` | `#00000059` | Drop shadow, focused |
| `inactive_shadow_color` | `#00000026` | Drop shadow, unfocused |
| `ignore_views` | `none` | Never decorate views matching this criteria |
| `forced_views` | `none` | Always decorate views matching this criteria |

The alpha of `button_color` is multiplied by 1.8 while the button is hovered and
by 2.6 while it is pressed. For a dark theme, use a translucent white instead of
a translucent black.

The drop shadow is cast by the window inset by `border_size`, which is what is
actually seen of it when the border is left transparent to serve as an invisible
margin to grab while resizing. Maximised, tiled and fullscreen windows never cast
one, the same way GTK drops its own. The shadow is baked once into a small atlas
and painted as nine slices, so resizing a window never bakes anything again; only
the shadow itself grows the area the frame paints, never the geometry of the
window, so tiling and snapping are left alone.

## Credits

Forked from the `decoration` plugin of [Wayfire](https://github.com/WayfireWM/wayfire)
(MIT). The button glyphs are traced from the Yaru / Adwaita symbolic icons.
