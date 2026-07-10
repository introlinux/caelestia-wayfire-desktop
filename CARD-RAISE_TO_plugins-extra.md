# Plan: proponer el shift-switcher (→ card-raise) a wayfire-plugins-extra

Estado: **pendiente de arrancar** (plan escrito 2026-07-10).
Contexto: el plugin vive en `wayfire-shift-switcher/` de este repo, funciona en
producción (Wayfire 0.10.1 en /usr/local) y está confirmado por el usuario.

## Objetivo

Que el plugin se incorpore upstream para que sobreviva a futuras versiones de
Wayfire sin mantenerlo a mano, y de paso llegue a más gente. Destino correcto:
**wayfire-plugins-extra** (el CONTRIBUTING de wayfire core dice explícitamente
que el repo base es solo para funcionalidad común; los efectos van fuera).

Vía alternativa que ellos ya usan: mantener el plugin en repo propio y que
plugins-extra lo añada como *subproject* opcional de meson (así están pixdecor,
wayfire-shadows y focus-request). Útil si queremos conservar el control.

## Condiciones formales verificadas (2026-07-10)

- **uncrustify obligatorio**: el CI de plugins-extra (`.github/workflows/ci.yaml`,
  job `test_code_style`) descarga `uncrustify.ini` de wayfire master, usa el
  fork `ammen99/uncrustify`, formatea todos los .cpp/.hpp y falla si
  `git diff --exit-code` no queda limpio.
- **Compilar contra wayfire master** (no 0.10.1): el CI compila todo el árbol
  contra master en Alpine/musl (gcc y también job con Xwayland).
- Licencia MIT con cabecera de copyright real.
- XML de metadatos con `<_short>`/`<_long>` traducibles (ya cumplido).
- El plugin se integra en su `src/meson.build`, no como proyecto meson aparte
  (salvo vía subproject).
- Para features nuevas piden **abrir issue antes o hablar por Matrix**
  (`#wayfire:matrix.org`, puente IRC `#wayfire` en Libera.chat).

## Retoques necesarios antes de compartir

1. **Cuestión de diseño a negociar en la issue (lo más importante)**:
   el plugin sustituye `core.default_wm` por una subclase que intercepta
   `focus_raise_view()`. Motivo: el clic-para-enfocar NO pasa por ninguna señal
   interceptable (`wm.cpp check_focus_surface` llama directo al método virtual);
   `view_focus_request_signal` solo cubre peticiones de panels/IPC. El override
   funciona, pero es invasivo: dos plugins haciendo lo mismo chocan.
   Es probable que ammen99 prefiera añadir una señal interceptable
   (pre-raise, con `carried_out`) en `focus_raise_view()`/`view_bring_to_front()`
   en core. En ese caso la contribución se parte en dos:
   - mini-PR a wayfire core añadiendo la señal;
   - plugin limpio en plugins-extra que la usa.
   Preguntarlo abiertamente en la issue: ¿WM-override o señal en core?
2. **Bug pendiente (obligatorio para upstream)**: si se desconecta el output o
   la vista cambia de output con una animación en vuelo, el effect hook queda
   colgando. Cancelar la animación en `view_set_output_signal` y en la
   destrucción del output (además del `view_unmapped` ya cubierto).
3. **Renombrado**: "shift-switcher" confunde — el Shift Switcher de Compiz era
   el switcher Alt-Tab tipo cover-flow; esto es una animación de raise.
   Proponerlo ya renombrado a **card-raise** (o `raise-animation`), citando la
   inspiración Compiz en la descripción.
4. **Mecánico**: pasar uncrustify con el ini de wayfire master; compilar contra
   master y ajustar API si cambió (default_wm sigue siendo unique_ptr público
   en master a fecha del plan); cabecera de copyright con nombre/handle real
   (introlinux).

## Argumento de venta para la issue (en inglés cuando se redacte)

- Accesibilidad/usabilidad: con el raise instantáneo, los usuarios noveles (el
  caso real: un niño pequeño) pierden la pista de qué ventana fue a dónde al
  hacer clic. La animación de carta hace el cambio de apilamiento rastreable
  con la vista. No existe nada equivalente en Wayfire (verificado 2026-07-10).
- Detalles técnicos que gustarán: anima con `view_2d_transformer_t` estándar,
  el raise real ocurre en el ápice (t=0.5, curva sin(πt)), dirección calculada
  como el lado de menor recorrido para despejar la unión de ventanas que tapan,
  no interfiere con grabs activos (move/scale/expo/switcher), opciones
  duration/tilt/margin.
- **Grabar un GIF/vídeo corto de demo** con gpu-screen-recorder (ya instalado):
  2-3 ventanas solapadas, clics alternos. Los PRs de efectos se venden con demo.

## Pasos, en orden

1. [ ] Rama `upstream-card-raise` en este repo: renombrado + fix de outputs
       (retoque 2) + cabecera copyright.
2. [ ] Clonar wayfire master y wayfire-plugins-extra master; compilar el plugin
       contra master; integrarlo en su `src/meson.build` + `metadata/`.
3. [ ] Pasar uncrustify (fork ammen99) con el ini de master; verificar
       `git diff --exit-code`.
4. [ ] Grabar GIF de demo.
5. [ ] Redactar issue en inglés para wayfire-plugins-extra con la pregunta de
       diseño (WM-override vs señal en core) y el GIF. Abrirla (o Matrix).
6. [ ] Según respuesta: PR a plugins-extra tal cual, o mini-PR a core con la
       señal + plugin adaptado.

## Notas de mantenimiento mientras tanto

- El plugin instalado en /usr/local sigue siendo el de este repo (commit
  `e4712fa`); WCM compilado a medida lo muestra en Effects (commit `622fbba`).
- Si upstream lo acepta renombrado, actualizar aquí: nombre de sección en
  wayfire.ini, lista `plugins=`, install.sh y memoria del proyecto.
