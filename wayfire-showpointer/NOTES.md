# showpointer — notas de desarrollo

Documento interno de trabajo (en español, **no** forma parte del PR a
`wayfire-plugins-extra`; el `README.md` sí, y está en inglés).

Última sesión: **2026-07-23**.

---

## 1. Estado actual

- El plugin **compila limpio** contra Wayfire 0.10.1 con `-Wall -Wextra`.
- Está **instalado** en `/usr/local` e integrado en `install.sh`, en `plugins=` y
  en la sección `[showpointer]` de ambos `wayfire.ini`.
- Atajos configurados: `Super+P` (ráfaga), `Super+Shift+P` (spotlight),
  `Super+Alt+P` (halo). `ripple_enabled` y `shake_enabled` a `true` en la config
  viva; `false` por defecto en el XML (conservador para upstream).
- **Sin bugs abiertos. Funcionalmente COMPLETO** desde el 2026-07-23: el bug del
  cuadrante (antiguo §4) resultó ser la causa única de los defectos observados en
  *todos* los efectos, porque los cuatro comparten el mismo `overlay_hook`.

### Lo que ya se comprobó que funciona

- El plugin carga, los tres activadores disparan, y los efectos se dibujan.
- **Los cuatro efectos funcionan bien en toda la pantalla** — ráfaga
  (`Super+P`), spotlight (`Super+Shift+P`), halo (`Super+Alt+P`) y ondas de clic
  — confirmado por el usuario el 2026-07-23 tras instalar el arreglo de §3.9 y
  cerrar sesión. No hizo falta tocar ningún efecto por separado: arreglar el
  clip del damage los arregló todos a la vez.
- El spotlight oscurece la pantalla de verdad (ver medición abajo).
- El spotlight oscurece la pantalla de verdad (medido: luminancia media de la
  pantalla baja de 179,9 a 60,8 al activarlo).
- Las texturas de cairo se generan correctamente (verificado *offline*,
  volcando los alfa del gradiente: 0 en el centro → 178 = 0,7·255 en el borde).

---

## 2. Arquitectura y decisiones de diseño

Ver la cabecera de `src/showpointer.cpp` y el `README.md` para el detalle. En
resumen:

- **Sin shaders.** Cairo → `wf::owned_texture_t` (de
  `wayfire/plugins/common/cairo-util.hpp`, que usa `wlr_texture_from_pixels`) →
  `render_pass_t::add_texture()`. Funciona en cualquier renderer de wlroots, sin
  el guard `is_gles2()` que obliga a `showtouch` a abortar en Vulkan. **Es el
  principal argumento de venta del PR.**
- Una textura horneada **una sola vez** por color/radio/escala; la animación se
  hace escalando el `wlr_fbox` de destino y variando el `alpha`. Nunca se
  rehornea por frame.
- Estado global compartido con `wf::shared_data::ref_ptr_t<>` (patrón de
  `hide-cursor`) porque el puntero es global pero el render es por output. Los
  activadores se registran por output; los eventos de entrada, solo en el global.
- Plantilla de referencia para el idioma moderno de render: **`src/bench.cpp`**
  de plugins-extra. **No** usar `showtouch.cpp` ni `annotate.cpp` como modelo:
  son GLES-only.

---

## 3. Bugs encontrados y corregidos

1. **`duration_t::running()` no es idempotente.** Ver §5.1. Se llamaba varias
   veces por frame y dentro de un `||` con cortocircuito → comportamiento no
   determinista. Sustituido por un helper `animating()` basado en `progress()`.
2. **Damage parcial con efectos translúcidos.** Toda zona no repintada desde
   cero acumulaba la misma textura cada frame hasta volverse sólida (síntoma:
   "cuadrado negro que pierde la transparencia"). Además, el cursor en plano de
   hardware no genera damage, así que con el puntero quieto la animación se
   congelaba. Ahora se daña el output completo cada frame mientras haya efecto.
3. **El anillo salía filiforme.** El gradiente radial tenía **un solo stop de
   color en el centro**, así que el color pleno existía en un radio
   matemáticamente exacto. Corregido con dos stops del mismo color (meseta).
4. **Los anillos se desvanecían justo al llegar al puntero.** La opacidad era
   `sin(t·π)`, que vale 0 en `t=1`. Ahora entra rápido, se mantiene opaco casi
   todo el recorrido y solo se apaga al final.
5. **Anillos ilegibles sobre fondos claros.** Añadido un contorno oscuro
   flanqueando la banda de color.
6. **Los anillos convergían hasta radio 0.** Al escalar la textura, el trazo
   encoge con ella hasta desaparecer. Ahora paran en `RING_CONVERGE = 0.82` de
   su radio inicial.
7. **Costura de 1 px en el spotlight.** La textura del agujero se dibujaba en
   coordenadas float y los 4 rectángulos oscuros en enteros redondeados hacia
   fuera. Ahora ambos comparten la misma caja entera.
8. **Halo casi invisible.** Gradiente que caía a cero desde el centro; ahora
   mantiene el color en la mitad interior. Defaults subidos a alpha 0,55 y
   radio 60.
9. **Los efectos solo se veían bien en el primer cuadrante** (el bug que paró la
   sesión del 22-jul; **cerrado y confirmado por el usuario el 2026-07-23**). En
   el `overlay_hook` se hacía `damage &= og`, intersecando el damage de
   `get_swap_damage()` (coordenadas de **búfer/píxel**) con
   `get_relative_geometry()` (coordenadas **lógicas**). Con eDP-1 a escala 2
   (lógico 1500×1000, búfer 3000×2000) eso recorta contra un rectángulo de la
   mitad de tamaño en cada eje → todo lo dibujado fuera del cuarto superior
   izquierdo se perdía. Arreglado con `const wf::region_t damage{og};`: el damage
   hook ya daña el output entero cada frame (§3.2), así que el clip correcto es
   el output completo en unidades lógicas. Ver §5.4 para el mapa de sistemas de
   coordenadas. **Moraleja general: cualquier plugin que interseque
   `get_swap_damage()` con algo está mal en HiDPI, y en escala 1 el bug es
   invisible.**

---

## 4. RESUELTO: los efectos solo se veían bien en el primer cuadrante

**Cerrado el 2026-07-23** — el arreglo descrito abajo se instaló, se cerró sesión
y el usuario confirmó que la ráfaga se ve bien en toda la pantalla. Se conserva
el razonamiento entero porque el patrón (mezclar unidades de damage) reaparecerá
en cualquier plugin que dibuje, y en escala 1 es invisible.

### Síntoma (reportado por el usuario, reproducible)

La ráfaga de anillos se ve correctamente cuando el puntero está en el cuarto
**superior izquierdo** de la pantalla. En el resto, sale "cortada" o se ven solo
un par de círculos exteriores que desaparecen enseguida. Igual comportamiento
antes y después de las correcciones §3.3–§3.6, así que **no era un problema de
contraste ni de curva de opacidad**.

### Por qué es sospechoso de ser un problema de escala

El portátil tiene **eDP-1 a escala 2**: geometría lógica 1500×1000, framebuffer
3000×2000 (confirmado por IPC `window-rules/list-outputs` + tamaño de `grim`).
"Primer cuadrante" = exactamente la mitad en cada eje = el factor de escala.

### Causa raíz (corregida y VERIFICADA en vivo el 2026-07-23)

En el `overlay_hook` había:

```cpp
wf::region_t damage = output->render->get_swap_damage();
damage &= og;   // og = get_relative_geometry(), LÓGICO
```

- `get_swap_damage()` devuelve el damage en **coordenadas de búfer (píxeles)**:
  `render-manager.cpp`, al final de `start_output_pass()`, hace
  `total_damage = params.target.framebuffer_region_from_geometry_region(total_damage)`
  justo antes de devolverlo.
- `add_texture()`/`add_rect()` esperan el damage en **coordenadas lógicas** y lo
  convierten ellos mismos (`render.cpp`, misma función).

Intersecar lo uno con lo otro mezcla los dos sistemas: a escala 2 se recorta
contra un rectángulo de la mitad de tamaño del búfer en cada eje.

**Corregido** sustituyendo esas dos líneas por `const wf::region_t damage{og};`
(el damage hook ya daña el output entero cada frame, así que el clip correcto es
el output completo, en unidades lógicas). Instalado y verificado en vivo el
2026-07-23: era exactamente esto, no hizo falta instrumentar nada más.

---

## 5. Trampas de Wayfire aprendidas (valen para cualquier plugin futuro)

### 5.1. `duration_t::running()` NO es una consulta

`wf-config/src/duration.cpp:143`:

```cpp
bool duration_t::running()
{
    if (this->priv->is_ready())
    {
        bool was_running = this->priv->is_running;
        this->priv->is_running = false;   // ← EFECTO SECUNDARIO
        return was_running;
    }
    return true;
}
```

Cuando la animación ha terminado, la **primera** llamada devuelve `true` y borra
el flag; las siguientes devuelven `false`. Llamarla más de una vez por frame, o
dentro de un `||` con cortocircuito (donde que se evalúe o no depende de los
otros efectos), hace que el resultado dependa del orden de evaluación.

**Usar `progress() < 1.0`**, que es `const` y sin efectos secundarios. Devuelve
1.0 tanto **antes** del primer `start()` (el `start_point` se inicializa a la
época, así que `is_ready()` es true) como al terminar.

### 5.2. La recarga de plugins en vivo NO sirve para iterar sobre un plugin

Wayfire relee `wayfire.ini` al vuelo y `plugins=` **acepta rutas absolutas**
(`plugin-loader.cpp`: `if (plugin_name.at(0) == '/') return plugin_name;`), así
que parece que se puede iterar sin cerrar sesión. **No se puede**: los `.so` se
cargan con `RTLD_GLOBAL`, de modo que `newInstance` del `.so` nuevo se resuelve
por interposición al del **primer** `.so` cargado. Wayfire sigue instanciando el
código viejo indefinidamente.

**Síntoma característico**: el efecto funciona, pero ningún log nuevo aparece
jamás — ni siquiera uno puesto en la primera línea de `init()`. Usar nombres de
fichero distintos en cada iteración **no** lo evita.

→ **Cada prueba real cuesta un cierre de sesión.** Conviene acumular cambios.

### 5.3. Los `LOGI` de plugins no llegan al journal

En la sesión GDM solo se ven los `EE`. Los `II` que aparecen al arrancar se
emiten antes de que se aplique el nivel de log. Para depurar: usar `LOGE`, o
escribir directamente a un fichero.

### 5.4. Sistemas de coordenadas

- `add_texture()` / `add_rect()`: damage **y** geometría en **coordenadas
  lógicas** del output. La conversión a framebuffer la hacen ellos.
- `get_swap_damage()`: **coordenadas de búfer (píxeles)**. No mezclar.
- `output->render->damage(box)`: output-local **lógicas**.
- `render_target_t::geometry` = `output->get_relative_geometry()` (lógica) y
  `scale` = `output->handle->scale`.

### 5.5. Otras

- `operator&` de dos `wf::geometry_t` devuelve **`bool`** (¿intersecan?), no un
  rectángulo. Y **no existe** `geometry_union`. Hay que escribir los helpers.
- El estado de botón de puntero en wlroots 0.19 es
  `WL_POINTER_BUTTON_STATE_PRESSED`, no `WLR_BUTTON_PRESSED` (esa sigue
  existiendo para tablet, de ahí la confusión y el `-Wenum-compare`).
- `wlr_tablet_tool_axis_event` necesita `<wayfire/nonstd/wlroots-full.hpp>`.
- `wf::get_core().bindings->add_activator()` existe y es **global** (útil cuando
  el binding no debe depender del output enfocado).
- `run_effects` itera sobre un `safe_list_t`, así que **sí** es seguro llamar a
  `rem_effect()` desde dentro de un effect hook.
- Damage parcial + efectos translúcidos = acumulación hasta volverse sólido.
  `crosshair` de upstream daña cada frame precisamente por esto.
- Los XML de metadatos solo se escanean **al arrancar Wayfire**: instalar un
  plugin nuevo con la sesión abierta falla con "No such option".

---

## 6. Metodología: cómo probar esto (y cómo NO)

### Las capturas de pantalla ENGAÑAN

`grim` usa `wlr-screencopy`, que **fuerza un repintado completo del output**.
Por eso una captura puede mostrar el efecto perfecto mientras en pantalla se ve
recortado: la captura no reproduce el ciclo de damage normal. Durante esta
sesión eso me llevó a dos conclusiones erróneas seguidas.

→ Las capturas sirven para verificar **geometría y color** de lo que se dibuja;
**no** sirven para verificar nada relacionado con **damage o repintado**. Para
eso, la observación del usuario en pantalla es el único dato válido.

### Restar el ruido

El escritorio cambia solo (terminal, reloj). Para medir una diferencia hay que
capturar **dos bases consecutivas sin efecto**, marcar como ruido lo que cambie
entre ellas, y descontarlo. Sin esto, el bbox de la diferencia sale dominado por
la ventana del terminal. Mejor aún: colocar el puntero en una zona del
escritorio sin ventanas.

### Validar el aspecto visual sin gastar un cierre de sesión

Replicar las funciones de cairo del plugin en un `.c` aparte, compilarlo con
`gcc … $(pkg-config --cflags --libs cairo) -lm` y generar un PNG que componga la
animación en varios instantes sobre fondo claro y oscuro. Así se afinan grosores,
contraste y curvas de opacidad sin tocar la sesión. Fue como se detectó que el
anillo salía filiforme (§3.3).

### Guion de pruebas por IPC

Hay un helper de IPC de Wayfire en el scratchpad de la sesión
(`wfipc.py`: `uint32` LE de longitud + JSON `{method, data}`). Métodos útiles:

- `stipc/move_cursor` `{x, y}` — coordenadas de layout, **exacto** (verificado).
- `stipc/feed_key` `{key: "KEY_LEFTMETA", state: true|false}` — para combos.
- `window-rules/get_cursor_position`
- `window-rules/list-outputs` — para leer geometría lógica y deducir la escala.

Cuidado: tras muchos combos sintéticos, los modificadores se pueden quedar
"pegados" y los atajos dejan de dispararse. Si algo deja de responder de repente,
sospechar de eso antes que del plugin.

---

## 7. Próximos pasos

1. ~~Instalar y cerrar sesión para probar el arreglo de coordenadas de §4.~~
   **Hecho el 2026-07-23, confirmado por el usuario: la ráfaga se ve bien en
   toda la pantalla.**
2. ~~Repasar uno a uno spotlight, halo y ondas de clic.~~ **Hecho el
   2026-07-23: el usuario confirmó que se arreglaron todos con §3.9.** Como los
   cuatro efectos comparten el `overlay_hook`, el clip de damage mal calculado
   era la causa única — no hizo falta tocar ningún efecto por separado. Lección:
   ante varios síntomas en efectos distintos que comparten camino de render,
   arreglar el camino común **antes** de depurar los efectos uno a uno.
3. Versionar el plugin en git (5 ficheros: `src/`, `metadata/`, `meson.build`,
   `README.md`, este `NOTES.md`; el `build/` se autoexcluye con el `.gitignore`
   que genera meson), junto con los cambios ya pendientes en `install.sh` y
   `config/wayfire.ini`.
4. Pendiente para el PR a `wayfire-plugins-extra`:
   - `sudo apt install uncrustify` y pasarlo con el `uncrustify.ini` de Wayfire
     (`git ls-files | grep "hpp$\|cpp$" | xargs uncrustify -c uncrustify.ini --no-backup`).
   - Rebasar sobre `master` (ojo: master ya tiene `fisheye.cpp`, nuestra copia
     v0.10.0 no).
   - Preguntar **antes** en Matrix `#wayfire:matrix.org`, como pide su
     `CONTRIBUTING.md`.
   - El PR son 3 archivos: `src/showpointer.cpp`, `metadata/showpointer.xml` y
     las entradas en los dos `meson.build`. Este `NOTES.md` no va.
