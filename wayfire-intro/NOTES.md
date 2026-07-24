# NOTES — wayfire-intro (en español, notas internas)

Telón negro desde el primer frame de la sesión + apertura cinematográfica
(`split` = mitades horizontales que se deslizan fuera; `iris` = círculo que
crece desde el centro). Escrito el 2026-07-24.

**Estado: escrito y compilando; PENDIENTE de `sudo ninja install` + logout +
prueba en vivo.**

## 1. La idea clave

No se captura nada: el escritorio se renderiza en vivo con normalidad y
encima va un **overlay opaco** que es lo que se anima. No hay destello por
construcción — los per-output instances enganchan el overlay hook en su
`init()`, antes del primer frame que ese output presente jamás.

## 2. Arquitectura

- Patrón showpointer: `per_output_plugin_t` + `intro_global_t` compartido vía
  `shared_data::ref_ptr_t`. **Sin shaders** (rects + una textura cairo), vale
  para cualquier renderer wlroots.
- Fases: `HOLD` (telón quieto) → `REVEAL` (animando) → `DONE` (hooks fuera,
  coste cero el resto de la sesión).
- **Disparo por IPC**: el global registra `intro/reveal` e `intro/replay` en
  el `method_repository_t` compartido
  (`<wayfire/plugins/ipc/ipc-method-repository.hpp>`,
  `shared_data::ref_ptr_t<wf::ipc::method_repository_t>`). Es un singleton
  inter-plugin: basta con que el plugin `ipc` esté en `plugins=` para que
  lleguen las llamadas del socket; no depende de ipc-rules. Los métodos se
  desregistran en el dtor.
- **Timeout de seguridad** (`wf::wl_timer<false>`, opción `timeout`, 10 s):
  si nadie llama a `intro/reveal` (shell roto), el telón se abre solo. Se lee
  UNA vez en el ctor (documentado en el XML).
- **Cursor**: `hide_cursor()`/`unhide_cursor()` del core son REFCONTADOS
  (`cursor.cpp`), así que van con guard `cursor_hidden` para mantener 1:1.
  Se oculta en HOLD, se restaura al terminar el reveal.

## 3. Render

- Overlay hook con las trampas de showpointer respetadas: damage a
  `add_rect`/`add_texture` SIEMPRE `wf::region_t{og}` en lógicas (jamás
  `get_swap_damage()`, que va en píxeles de búfer y rompe en HiDPI);
  `progress()` en vez de `running()`; y `progress()` devuelve 1.0 ANTES del
  primer `animate()`, por eso en HOLD no se consulta (manda el enum de fase).
- **Damage por frame SOLO durante REVEAL.** Durante HOLD no hace falta: el
  telón es opaco y estático; si un cliente repinta debajo, ese pass ya invoca
  nuestro overlay y el negro se redibuja sobre esa zona. Coste de la fase de
  espera ≈ 0.
- `split`: dos rects de media pantalla deslizándose fuera (el de arriba se
  lleva el píxel impar). Con `add_clipped_rect` porque los rects salen del
  output al avanzar (ojo: la lista `{x,y,w,h}` a pelo en `add_rect` es
  AMBIGUA entre `geometry_t` y `wlr_fbox` → construir `wf::geometry_t{...}`
  explícito).
- `iris`: el `bake_hole` del spotlight de showpointer (transparente hasta
  radius, feather hasta el color, `CAIRO_EXTEND_PAD` para las esquinas),
  horneado UNA vez a 1600 px por color y escalado por frame + 4 rects
  alrededor. La textura y los rects comparten la misma caja entera
  (`floor`/`ceil`) para no dejar la costura de 1 px (showpointer §3.7).
  Radio transparente = `p · semidiagonal`; la caja exterior se divide por
  `HOLE_INNER` (=0.7) para que el feather termine de salir justo al final.
- El feather del iris escala proporcional al círculo (casi duro al empezar,
  suave al final): es deliberado, un iris cinematográfico tiene borde duro.

## 4. El disparo desde el shell

`shell/modules/background/Wallpaper.qml` ya sabía el instante exacto en que
el fondo es visible (`root.current` se asigna con `Image.Ready`): ahí va un
`Quickshell.execDetached(["caelestia-intro-reveal"])` one-shot (guard
`revealSent`; hay una instancia por monitor y el plugin ignora repeticiones).
La pantalla de "Wallpaper missing?" también revela (Component.onCompleted del
sourceComponent). Si el background está deshabilitado del todo, nadie llama →
red de seguridad del timeout.

`bin/caelestia-intro-reveal`: python3 mínimo, socket de `WAYFIRE_SOCKET` (o
glob de `$XDG_RUNTIME_DIR/wayfire*.socket`), frame uint32 LE + JSON. Sale en
silencio si no hay socket. Es QML de `modules/**` sin `qsTr` nuevos → se
despliega solo con rsync, sin ciclo de traducción ni recompilar el plugin C++.

## 5. Cómo iterar

- Cambios de CÓDIGO: recompilar + `sudo ninja install` + **logout** (RTLD_GLOBAL,
  showpointer NOTES §5.2). El XML también exige logout la primera vez.
- Cambios de OPCIONES (`pattern`, `duration`, `color`, `hide_cursor`): en vivo
  editando wayfire.ini + **Super+F12** (`replay`) para verlo al momento. Esa
  es la vía barata de afinado; también `intro/replay` por IPC.
- Prueba real de arranque: cerrar sesión y entrar (es el único momento en que
  el flujo completo GDM→negro→wallpaper→reveal se ejecuta de verdad).

## 6. Deuda / ideas futuras

- El reveal es simultáneo en todos los outputs (evento global). Escalonarlo
  por output sería trivial (offset por índice) si algún día apetece.
- Posible sonido de apertura (patrón pw-play de ninjaslash) si el usuario lo
  pide.
