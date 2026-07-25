# gtkdecor — notas de desarrollo

Documento interno de trabajo (en español; el `README.md` va en inglés por si
algún día se manda upstream).

Primera sesión: **2026-07-25**.

**Estado: funcionando, confirmado en vivo por el usuario.** Instalado en
`/usr/local`, integrado en `install.sh`, en `plugins=` (en lugar de
`decoration`) y en la sección `[gtkdecor]` de ambos `wayfire.ini`. Salió bien a
la primera, sin ningún ciclo de depuración — ver §3, la maqueta.

---

## 1. Qué problema resuelve

Las apps que **no** dibujan sus propios adornos (Qt como VLC, GTK2/3 viejo como
synaptic o gparted, y otras librerías como Audacity) reciben decoración del
compositor. El plugin `decoration` del core de Wayfire las pinta con un aspecto
totalmente distinto al de las apps GTK modernas del escritorio: barra plana sin
esquinas redondeadas, título a la izquierda y tres círculos tipo semáforo.

`gtkdecor` es un fork de ese plugin que replica la barra de título de
GTK4/libadwaita tal y como se ve en este equipo.

## 2. Medidas tomadas del tema real (no inventadas)

Se midieron **a píxel** sobre un pantallazo de una ventana GTK4 real
(`~/Imágenes/Screenshots/gnome-terminal-screenshot.png`, hecho a escala 2, o sea
que todo lo de abajo son px físicos ÷ 2 = lógicos):

| Elemento | Medida | Valor lógico |
| --- | --- | --- |
| Barra completa (borde incluido) | 76 px físicos | **38** = 1 borde + 37 |
| Fondo de la barra | RGB 235 | `#EBEBEB` |
| Borde exterior | RGB 154-156 | `#9A9A9C` |
| Línea de luz bajo el borde | RGB 251, 1 px | `#FBFBFB` |
| Separador con el cliente | RGB 189, 1 px | `#BDBDBD` |
| Fondo del cliente | RGB 250 | `#FAFAFA` |
| Radio de las esquinas | ajuste de círculo sobre la curva del borde en 2 puntos → R≈35,5 físicos | **18** |
| Botón: diámetro | 44 px físicos | **22** |
| Botón: fondo | RGB 218 sobre 235 → α≈0,072 de negro | `#00000012` |
| Botón: margen al borde | 13 px físicos | **6,5 → 7** |
| Glifo del botón | caja de 16x16 físicos con la × ocupando 8,2/16 | icono symbolic de **16** |
| Título | tinta de 22 px físicos de alto, centrado en la ventana | Bold 11 |

`gsettings get org.gnome.desktop.wm.preferences button-layout` da `appmenu:close`
→ las apps GTK de este equipo enseñan **solo cerrar**, por eso `button_order`
tiene de default `close` (decisión confirmada por el usuario).

`Adwaita Sans` **no está instalada** (`fc-list` no la tiene): fontconfig la
resuelve a Noto Sans, que es justo lo que hace GTK. Se deja `Adwaita Sans Bold
11` como default para que ambos sigan resolviendo igual si algún día se instala.

## 3. Metodología: maqueta cairo antes de compilar

Iterar sobre un plugin de Wayfire cuesta **un cierre de sesión por prueba** (los
`.so` se cargan con `RTLD_GLOBAL`, ver NOTES de showpointer §5.2). Para no gastar
ciclos afinando píxeles se hizo lo mismo que con showpointer: replicar el cairo
en un `.c` suelto que genera un PNG y compararlo numéricamente con el pantallazo
real.

Se hicieron **dos** maquetas, y la segunda es la que de verdad importa:

1. `mockup.c` — la barra dibujada de un tirón con un solo `path`. Validó colores,
   radio y métricas. Diferencia con el pantallazo real: **1,63 %** de píxeles.
2. `mockup2.c` — replica la **descomposición real del render**: hornea las dos
   texturas de esquina con la misma función que `render_corner()` y luego compone
   exactamente la misma lista de rectángulos que `gtk_decoration_node_t::render()`.
   Diferencia: **1,40 %**, y todo el residuo es antialias de la fuente.

La segunda es la que evita el bug tonto: el aspecto podía estar bien y la
composición por trozos dejar una costura o un hueco. Merece la pena replicar la
*secuencia de dibujo*, no solo el aspecto. (Los `.c` viven en el scratchpad de la
sesión, que es efímero; si hace falta afinar más, rehacerlos es media hora.)

## 4. Decisiones de arquitectura

**Fork out-of-tree en vez de parche a Wayfire.** El plugin `decoration` del core
solo usa cabeceras públicas instaladas (`toplevel.hpp`, `toplevel-view.hpp`,
`txn/transaction-manager.hpp`, `scene*.hpp`, `plugins/common/cairo-util.hpp`), así
que se puede forkear fuera del árbol como shift-switcher / showpointer /
ninjaslash / intro. Ventajas: no añade un parche más que reaplicar en cada
recompilación de Wayfire, y deja añadir opciones nuevas sin tocar el core.

**Todo renombrado.** Namespace `wf::decor` → `wf::gtkdecor`, clase
`wf::simple_decorator_t` → `wf::gtk_decorator_t`, prefijo de opciones
`decoration/` → `gtkdecor/`. **Esto no es cosmético**: los `.so` de plugins se
cargan con `RTLD_GLOBAL`, así que si los dos plugins estuvieran cargados a la vez
los símbolos duplicados se interpondrían entre sí. Con nombres distintos, cargar
los dos a la vez sería redundante (dos decoraciones sobre el mismo toplevel) pero
no corrupción de memoria.

**Esquinas por textura, no por shader ni por textura de barra completa.** Se
hornean dos imágenes de `radius x radius` (36x36 físicos con los defaults) que
llevan borde + línea de luz + fondo, y el resto de la barra son `add_rect()`.
Alternativas descartadas:

- Barra entera como una textura de ancho de ventana: se rehornearía en cada frame
  de un resize (~600 KB de subida por frame).
- Shaders: innecesario y ataría el plugin a GLES (misma decisión que en
  showpointer).

Las esquinas se cachean por `(radius, scale, active)` en el nodo, o sea 2
texturas pequeñas por ventana.

Truco de la esquina derecha: se dibuja **la misma figura de `2*radius` de ancho**
y se hace `cairo_translate(-radius, 0)` antes, así la esquina derecha de la figura
cae dentro del lienzo de `radius x radius`. Los dos arcos (exterior e interior con
`radius - border`) comparten centro, que es lo que hace que el borde tenga grosor
uniforme en toda la curva.

**Título centrado en la VENTANA, no en el hueco libre.** El texto se hornea en una
superficie que va de `reserved` a `W - reserved`, con `reserved` = lo que ocupan
los botones en su lado. Al ser simétrico, el centro de la superficie coincide con
el centro de la ventana, que es lo que hace GTK. Pango se encarga del centrado
(`PANGO_ALIGN_CENTER`) y del recorte (`PANGO_ELLIPSIZE_END`), así que el título
nunca se mete debajo de los botones. El área de input del título **no** cambia:
sigue siendo toda la barra hasta los botones, para poder arrastrar la ventana.

**Escala.** Todas las superficies cairo se crean a `tamaño * scale` y se dibuja
con `cairo_scale(scale, scale)`, o sea que el código de dibujo está siempre en px
lógicos. La escala sale de `data.target.scale` en el render, y es parte de la
clave de caché de las tres cosas horneadas (esquinas, título, botones).
El plugin del core horneaba los botones a `title_height` y los escalaba al vuelo;
aquí se hornean a su tamaño real por la escala del output, así que salen nítidos
en HiDPI.

**No se pinta detrás del cliente.** El plugin del core rellena todo el marco con
el color de fondo antes de dibujar nada; aquí solo se pintan la barra y los tres
bordes. Además de ahorrar relleno, hace que un cliente translúcido deje ver el
escritorio, como haría una app con decoración propia.

## 5. Limitaciones conocidas

- **Las esquinas inferiores no se redondean.** Son del cliente, y desde una
  decoración de servidor no se puede recortar su contenido. Habría que meter un
  transformer con máscara sobre el `surface_root` de la vista, que es un proyecto
  aparte.
- El botón de maximizar siempre lleva el glifo `window-maximize-symbolic`; GTK
  cambia a `window-restore-symbolic` cuando la ventana está maximizada. Con el
  `button_order = close` de este equipo no se nota.
- Los tamaños (`title_height`, `border_size`, `button_*`) se leen al construir el
  layout de cada ventana, así que cambiarlos en caliente desde WCM solo afecta a
  las ventanas que se abran después. Los **colores** sí se releen en cada frame.
- Sin variante oscura automática: hay que cambiar los colores a mano (y poner
  `button_color` a un blanco translúcido).
