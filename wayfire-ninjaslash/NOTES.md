# NOTES — wayfire-ninjaslash (en español, NO va al PR)

Animación de **cierre** de ventana estilo corte de espada ninja: una o varias
estelas luminosas barren la ventana en arco y la parten; los pedazos se separan
perpendiculares al corte, giran, caen y salen de pantalla. Con sonido por tajo.

**Estado: funcionando y confirmado en vivo por el usuario.**

## 1. Arquitectura y linaje

- Plugin autocontenido (patrón de `wayfire-showpointer` / `wayfire-shift-switcher`).
  **No** parchea el core ni `extra-animations`.
- Se engancha al **registry compartido** de `animate`
  (`wf::shared_data::ref_ptr_t<wf::animate::animate_effects_registry_t>`), registrando
  el efecto `"ninjaslash"`. Con eso, `[animate] close_animation = ninjaslash` lo activa.
- Plantilla de render: la animación **`shatter`** de `wayfire-plugins-extra`
  (`src/extra-animations/shatter.hpp`). De ahí sale el esqueleto: subclase de
  `wf::scene::view_2d_transformer_t` con render-instance
  `transformer_render_instance_t`, `custom_gles_subpass`, `pre_hook` en
  `OUTPUT_EFFECT_PRE` que daña el output entero, z-order `TRANSFORMER_HIGHLEVEL + 1`,
  y la clase `animation_base_t` con init/step/reverse.
- **Snapshot propio (importante, ver §9):** en el ctor del transformer hacemos
  `view->take_snapshot(win_snapshot)` UNA vez y todos los frames se dibujan desde
  esa textura fija (`wf::auxilliary_buffer_t`), NO desde `get_texture(1.0)`. El core
  mantiene viva la vista durante el unmap (`animation_hook` +
  `unmapped_view_snapshot_node`), pero recomponer los hijos cada frame daba un flip
  (§9). El box se guarda también en el ctor (`snap_box`) para no depender de que los
  hijos sigan vivos.
- Requiere GLES2 (`is_gles2()` guard en `init()`).

## 2. Las decisiones clave (diferencias con shatter)

1. **Troceo por DESCARTE en el shader, sin geometría.** Se dibuja el quad completo
   de la ventana una vez por trozo y el fragment descarta lo que cae fuera de la
   banda de ese trozo. Elimina Voronoi/Boost y hace triviales N tiras y la cruz.

2. **Proyección ORTOGRÁFICA en coords lógicas, NO perspectiva.** shatter usa
   `lookAt`+`perspective`, que **encoge** la ventana → habría un "pop" al empezar
   (nuestra fase inicial muestra la ventana intacta y debe coincidir pixel a pixel
   con la real). Usamos `wf::gles::render_target_orthographic_projection(data.target)`
   con los quads en píxeles lógicos: sin pop, HiDPI correcto gratis y matemática
   mucho más simple.

3. **Cortes CURVOS por distancia a una circunferencia.** Un tajo recto "parece una
   bala, no una espada". `cut_dist()` devuelve `length(P - centro) - radio` en modo
   curvo (uniform `winsize` para reconstruir `P = (uv-0.5)*winsize`) y el `dot` de
   siempre en recto. Los cortes paralelos pasan a ser **arcos concéntricos**
   compartiendo centro, así que las bandas `[lo,hi]` y el realce de borde siguen
   valiendo sin tocarlos.
   - Geometría: círculo tangente a la recta en su punto base, centro `C = -n*Rc`
     (relativo al centro de ventana), `Rc = win_diag * 1.2 / curve`.
   - **`Rc ≥ 1.2·diagonal` SIEMPRE**, por diseño del mapeo: si el centro cayera
     dentro de la ventana, el signo se invertiría al otro lado y saldrían
     artefactos de recorte.

## 3. Patrones, tajos y tiempos

- `pattern`: `random` (default, sortea por cierre: 30% cross, si no paralelo con
  `cuts` 1..4), `parallel` (usa `cuts`), `cross` (2 tajos perpendiculares, 4 trozos).
- `cuts` cuenta **pasos de espada**, no pedazos (renombrado desde `slices` a
  propuesta del usuario): paralelo deja `cuts + 1` trozos; cross son 2 por definición.
  Se **ignora** en `random` y `cross` — está documentado en el XML porque el usuario
  lo reportó como bug.
- Cada línea de corte es un `Stroke{n, offset, t0, c}` con timeline local
  escalonada: `gap = min(0.16, 0.5 / n_strokes)`, `t0 = s*gap`.
- Cada `Piece` tiene un `release` (cuándo empieza a moverse = tras el tajo que la
  libera) y vuela con su `tp` local → efecto de pelado **en orden**. El alpha y el
  realce de borde van gateados por ese `tp` local, no por el progreso global, para
  que los trozos que salen tarde no se desvanezcan antes de tiempo.

## 4. Estela

- Dos programas GLES. El de la estela **no** usa textura, así que NO se compila con
  `program_t::compile` (que inyecta `@builtin@`/`get_pixel`) sino con
  `OpenGL::compile_program()` + `blade_program.set_simple(id, TEXTURE_TYPE_RGBA)`;
  y NO se llama `set_active_texture`.
- **DOS PASADAS** (lección importante): la v1 era solo aditiva y el usuario **no la
  veía** — un blanco aditivo sobre ventana clara no suma nada. Ahora: pasada 1 halo
  aditivo (`GL_SRC_ALPHA, GL_ONE`, luce en fondos oscuros) + pasada 2 **núcleo
  opaco** (`GL_ONE, GL_ONE_MINUS_SRC_ALPHA`, se ve sobre CUALQUIER fondo).
  *Nunca fiar la visibilidad de un overlay sobre contenido arbitrario solo al blend
  aditivo.*
- Forma "reveal": una punta brillante viaja por el corte y deja estela detrás
  (`step(along, head)` + gaussiana en la punta), no una línea encendida de golpe.
- Sigue el arco: es una cinta `GL_TRIANGLE_STRIP` tesselada (SEG=28 curvo, 1 recto
  → el mismo código sirve para ambos) con la normal radial por vértice.

## 5. Sonido

- Un swish **por tajo**: el ctor precalcula `sound_times[s] = s*gap` (mismo schedule
  que los strokes) y el `pre_hook` dispara al alcanzar cada `t0`. Con `cuts=1` es
  un único sonido en t=0, así que es una generalización estricta.
- Guard `started` (se pone en `init_animation()`) porque **`progress()` devuelve 1.0
  ANTES del primer `start()`** y dispararía todos los sonidos en el primer frame.
- Reproductor **`pw-play`**, no mpv: mpv cuesta ~100 ms de arranque y hasta 5
  procesos por cierre descuadraban el sincronismo. libsndfile 1.2.2 reproduce mp3
  (soporte desde 1.1) y el resto del proyecto ya lo usa así (`Screenshot.qml`).
- **TRAMPA pw-play**: `--volume` se parsea con `strtod`, que es **locale-aware** →
  con locale es_ES un `0.9` se leería como 0 (silencio total). Se lanza con
  `LC_NUMERIC=C` y el literal se construye con aritmética entera (`"0."+pct`),
  nunca con un to_string de float.
- El mp3 vive en `assets/` y meson lo instala en `/usr/local/share/ninjaslash/`
  (ruta estable a la que apunta el default). **No** referenciar
  `~/.caelestia/caelestia-wayfire/assets/`: esa carpeta la borra el rsync del shell.

## 6. Trayectorias (`trajectory`)

- `radial` (default): el desplazamiento total `disp + (0, grav_full)` escalado por
  `t²`. Todo acelera hacia fuera; no es físico pero es el look original.
- `ballistic`: tiro real. `pos = v0·t + ½·g·t²`, con deriva lateral a velocidad
  constante (`disp·t`) y una componente vertical con impulso hacia arriba. El giro
  pasa a ser lineal en `t` (volteo constante), no `t²`.
  - `v0` y `g` **se despejan** para cumplir dos condiciones a la vez: que el ápice
    quede a la altura pedida por `lift` y que en `t=1` el trozo haya pasado el borde
    inferior. De `apex = v0²/2g` y `y(1) = -v0 + g/2 = Yend` sale
    `sqrt(g) = sqrt(2·apex) + sqrt(2·apex + 2·Yend)`. Así la salida de pantalla está
    garantizada por construcción y NO hace falta el escalado del §7.
  - `gravity` multiplica `Yend` con un `max(1.0, gravity)`: solo puede hacer que
    caigan MÁS lejos, nunca menos, para no romper esa garantía.

## 7. Salida de pantalla (`fade`, solo trayectoria radial)

Sin `fade` los pedazos se eliminan en `tp=1` **estén donde estén**, así que los de
poco desplazamiento (la tira central de un número impar de cortes, `frac≈0`) hacían
"pop" con una franja aún visible. Arreglado: cuando `!fade`, el desplazamiento final
`Dend = disp + (0, grav_full)` se escala a un mínimo de `diag(output)+diag(ventana)`
(solo si se queda corto; un trozo parado se manda hacia abajo), garantizando que
TODOS cruzan del todo el borde antes de terminar. Con `fade` activo no se toca.

## 8. Trampas de Wayfire respetadas

- **Iterar cuesta un cierre de sesión**: los `.so` se cargan con `RTLD_GLOBAL` → la
  recarga en vivo reusa el código viejo; y los XML solo se escanean al arrancar
  Wayfire. Cada cambio de código = logout/login. Las opciones numéricas/booleanas sí
  se releen en vivo (`pattern`, `cuts` y `angle` no: se leen en el ctor).
- `duration_t::running()` **no es idempotente**: se llama UNA sola vez por frame en
  `step()`; en `render()` y en el `pre_hook` se usa `progress()`.
- `LOGI` no llega al journal en sesión GDM → usar `LOGE` o fichero para depurar.

## 9. Flip vertical antes del corte (RESUELTO, no reintroducir)

Síntoma: la ventana intacta aparecía **volteada verticalmente** durante los primeros
frames (antes del corte) y se enderezaba al trocearse. Causa: usábamos
`get_texture(1.0)`, que **recompone los hijos** de la vista cada frame. Durante el
cierre coexisten el `surface_root` vivo (el cliente aún no soltó sus búferes) y el
`unmapped_view_snapshot_node` que el core inserta (`set_unmapped_contents()` en el
ctor del `animation_hook`, `add_front`). Al desmapearse el cliente, el número de
hijos cae de 2 a 1 y `get_texture` cambia de camino (búfer auxiliar ↔ zero-copy),
con orientación Y distinta → flip en el instante del unmap, justo antes del corte.

Causa real (confirmada en vivo): **el búfer auxiliar tiene el origen abajo**, así que
muestrearlo con `uv` tal cual sale espejado en vertical. El camino zero-copy (1 solo
hijo, tras el unmap) venía derecho y el de búfer auxiliar (2 hijos, antes del unmap)
venía volteado — de ahí que el síntoma pareciera "solo al principio": en realidad
cambiaba de un camino al otro a mitad de animación.

Arreglo, en dos partes:
1. Tomar **nuestro propio** snapshot una sola vez en el ctor
   (`view->take_snapshot(win_snapshot)`) y dibujar SIEMPRE desde esa textura fija;
   el box se guarda en `snap_box`. Una sola fuente, una sola orientación (y de paso
   no se recomponen los hijos por frame, más eficiente).
2. Compensar el origen del búfer muestreando con
   `get_pixel(vec2(uv.x, 1.0 - uv.y))`.

**OJO al tocar esto:** el flip va SOLO en el muestreo, nunca en la `uv` de los
vértices (`{0,0,1,0,1,1,0,1}`), porque esa misma `uv` alimenta `cut_dist()`, que
deriva de ella la geometría del corte; voltearla ahí espejaría los tajos y los arcos
respecto a la estela, que se dibuja en coordenadas lógicas de pantalla.

## 10. Validación offline (opcional, ahorra logouts)

Metodología de showpointer §6: replicar en un `.c` con cairo la cinemática y el
perfil de brillo de la estela y volcar un PNG con varios instantes sobre fondo claro
y oscuro (`gcc x.c $(pkg-config --cflags --libs cairo) -lm`). El descarte GLES no se
replica, pero sí las curvas y colores.
