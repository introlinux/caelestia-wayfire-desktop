# wayfire-shift-switcher

Animación de *raise* estilo baraja de cartas (inspirada en el Shift Switcher de
Compiz) para Wayfire ≥ 0.10.

Cuando se enfoca una ventana que está tapada por otras, en lugar de saltar
instantáneamente al frente, la ventana se desliza lateralmente fuera del montón
(todavía por detrás), se eleva en el punto más alejado del recorrido y vuelve a
su sitio ya en primer plano. Así el ojo puede seguir físicamente a dónde ha ido
la ventana — útil sobre todo para niños o usuarios noveles, que con el
solapamiento instantáneo pierden la pista de la ventana que quedó detrás.

## Cómo funciona

Sustituye el `window_manager_t` por defecto de core por una subclase cuyo
`focus_raise_view()` retrasa el *bring-to-front* real hasta la mitad de la
animación. Cualquier vía de foco (clic, IPC `focus-view`, barra de tareas…)
pasa por ahí, así que la animación es consistente en todo el escritorio.

La dirección del tirón se calcula automáticamente: es el lado por el que la
ventana necesita recorrer menos distancia para salir del área que la cubre.

No se anima cuando: la ventana no está tapada, está minimizada (eso ya lo hace
la lámpara mágica), es un diálogo con padre, o hay un plugin con grab activo
(move, scale, expo, switcher…).

## Opciones (`[shift-switcher]` en wayfire.ini)

| opción     | por defecto     | descripción                                     |
|------------|-----------------|-------------------------------------------------|
| `duration` | `600ms linear`  | duración total del recorrido de ida y vuelta    |
| `tilt`     | `3.0`           | inclinación máxima en grados (0 la desactiva)   |
| `margin`   | `24`            | píxeles extra más allá del borde que la cubre   |

## Compilación

```sh
meson setup build --prefix /usr/local
ninja -C build
sudo ninja -C build install
```

Añade `shift-switcher` a la lista `plugins` de `[core]` en `wayfire.ini`.

## Limitaciones conocidas (v0.1)

- Si se desconecta el output mientras una ventana está en vuelo, el hook de
  render no se migra (caso raro; pendiente).
- Los diálogos con ventana padre usan el raise instantáneo por defecto.
