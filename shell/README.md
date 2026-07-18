# Caelestia-Wayfire

Port de [Caelestia Shell](https://github.com/caelestia-dots/shell) para Wayfire.
Objetivo: reemplazar toda la capa IPC de Hyprland por el IPC nativo de Wayfire
manteniendo intacta la estética QML/Material You.

**Entorno objetivo:** Ubuntu 26.04 LTS · Quickshell 0.2.1 · Wayfire 0.10.0

---

## Tabla de contenidos

1. [Estado actual](#1-estado-actual)
2. [Entorno de desarrollo](#2-entorno-de-desarrollo)
3. [Arquitectura IPC real implementada](#3-arquitectura-ipc-real-implementada)
4. [Scripts auxiliares](#4-scripts-auxiliares)
5. [Wayfire IPC — Protocolo y lecciones aprendidas](#5-wayfire-ipc--protocolo-y-lecciones-aprendidas)
6. [Funcionalidades implementadas](#6-funcionalidades-implementadas)
7. [Bugs pendientes y TODO](#7-bugs-pendientes-y-todo)
8. [Limitaciones conocidas del protocolo](#8-limitaciones-conocidas-del-protocolo)
9. [Plan de fases original (referencia)](#9-plan-de-fases-original-referencia)
10. [Sesión real GDM — configuración extra](#10-sesión-real-gdm--configuración-extra)

---

## 1. Estado actual

**Fase 1 completada.** El código QML está completamente libre de referencias a
`Quickshell.Hyprland`. La shell arranca y es funcional en Wayfire.

### Qué funciona

| Característica | Estado |
|---|---|
| TaskList en la barra (iconos de ventanas abiertas) | ✅ Funcional |
| Click izquierdo: activar / minimizar ventana | ✅ Funcional |
| Window controls (minimizar / maximizar / cerrar) | ✅ Funcional |
| Workspace indicator (muestra el workspace activo) | ✅ Funcional |
| Cambio de workspace con Ctrl+1…10 | ✅ Funcional |
| Notificación al indicador de workspace al cambiar | ✅ Funcional |
| Grabador de pantalla → guarda en `~/Vídeos/Recordings` | ✅ Funcional |
| Play / abrir carpeta en RecordingList | ✅ Funcional (via `xdg-open`) |
| Popup al hover sobre icono: icono + título de ventana | ✅ Funcional |
| Popup: botones de workspace (enviar ventana 1-5) | ⚠️ En investigación |
| Popup: botón Force Quit | ✅ Recibe click, pkill ejecuta |
| Atajos de teclado para drawers (Super+D/E/S/L/U/A) | ✅ Funcional |
| Scale / Expo con hotspot / atajo | ✅ Funcional |
| Launcher — listado y lanzamiento de apps | ✅ Funcional en sesión real |
| Launcher — foco automático al abrir (sin clic de ratón) | ✅ Funcional |
| Launcher — cerrar al pulsar fuera del panel | ✅ Funcional |
| Decoraciones CSD (apps con su propio estilo) | ✅ Activo — GTK4/Qt siguen Yaru automáticamente |
| Apps Qt con tema del sistema (Yaru) | ✅ via `QT_QPA_PLATFORMTHEME=gtk3` |
| Tooltips en TaskList | ✅ Funcional |
| DropArea en TaskList (drag-over 600ms → eleva ventana) | ✅ Implementado |

### Qué NO funciona (limitaciones estructurales)

| Característica | Por qué |
|---|---|
| Preview de ventana en popup (ScreencopyView) | No probado en sesión real; no funciona en Wayfire anidado |
| Indicador de ventanas por workspace (puntos) | `wlr-foreign-toplevel` no expone en qué workspace está cada ventana |
| Enviar ventana a workspace desde popup | Investigando: `stipc/feed_key` retorna 'ok' pero no confirmado que mueva la ventana |
| Barra de título en foot y apps sin CSD | foot no tiene CSD; se mueve con Alt+drag |
| Personalización de botones en decoración SSD | El plugin `decoration` de Wayfire los dibuja en código hardcodeado, sin temas |
| Squeezimize anima hacia el icono de la barra | Bug en Quickshell 0.2.1: `setRectangle` crashea en compositors no-Hyprland (ver §10) |

---

## 2. Entorno de desarrollo

### Configuración

El desarrollo se hace en **Wayfire anidado** dentro de Hyprland:

```bash
# Wayfire anidado en WAYLAND_DISPLAY=wayland-2
# IPC socket: /run/user/1000/wayfire-wayland-2-.socket
# Quickshell conectado a ese display

# Lanzar Wayfire anidado (desde terminal en Hyprland)
WAYLAND_DISPLAY=wayland-1 wayfire   # Wayfire se crea en wayland-2 automáticamente

# Lanzar Quickshell en la sesión anidada
WAYLAND_DISPLAY=wayland-2 WAYFIRE_SOCKET=/run/user/1000/wayfire-wayland-2-.socket \
  quickshell -c ~/.caelestia/caelestia-wayfire &
```

> **Nota:** El socket de Wayfire sigue el patrón `wayfire-${WAYLAND_DISPLAY}-.socket`.
> Si reinicias Wayfire, verifica con `ls /run/user/1000/wayfire*.socket` cuál es el
> socket activo antes de relanzar Quickshell. Con dos Wayfire corriendo puede haber
> dos sockets; el activo se puede confirmar con `ss -lx | grep wayfire`.

### Recarga en caliente

```
Super+F5  → pkill quickshell && quickshell -c ~/.caelestia/caelestia-wayfire &
```

> **IMPORTANTE:** El `command_reload_qs` en `wayfire.ini` NO pasa `WAYFIRE_SOCKET`
> al quickshell relanzado. Para que los scripts IPC funcionen desde Quickshell,
> relanzarlo siempre manualmente con ambas variables de entorno.

### Configuración de `~/.config/wayfire.ini`

Plugins obligatorios:
```ini
[core]
plugins = animate autostart command vswitch decoration expo fast-switcher \
  foreign-toplevel grid idle ipc move place resize scale stipc switcher \
  window-rules wm-actions wobbly wrot zoom
```

Sección `[vswitch]` — mover ventana enfocada al workspace N con Super+Shift+N:
```ini
[vswitch]
binding_win_1  = <super> <shift> KEY_1
# ... hasta binding_win_10 = <super> <shift> KEY_0
```

Workspace switching via script (para notificar a Quickshell):
```ini
[command]
binding_ws1 = <ctrl> KEY_1
command_ws1 = wayfire-ws-switch 1
# ... hasta binding_ws10 = <ctrl> KEY_0 → wayfire-ws-switch 10
```

Window rules — solo para ventanas con app-id no vacío (`.+` no `.*`):
```ini
[window-rules]
rule_001 = on created if app_id matches .+ then assign_decoration_mode server
```
> Usar `.+` en lugar de `.*` evita el error
> `Window-rules: Error while executing rule on created signal`
> que se produce cuando Quickshell crea superficies internas con app-id nulo.

---

## 3. Arquitectura IPC real implementada

En lugar del `WayfireService.qml` planificado originalmente, la implementación
real usa:

```
services/Hypr.qml   ← Singleton reescrito. Mismo nombre para no romper imports.
    │
    ├── ToplevelManager (Quickshell.Wayland)
    │     Protocolo: wlr-foreign-toplevel-management
    │     Proporciona: toplevels, activeToplevel, minimized, activate(), close()
    │
    ├── IpcHandler (target: "hypr")
    │     Recibe: setActiveWs(id), refreshDevices(), etc.
    │     Usado por: wayfire-ws-switch → qs-caelestia hypr setActiveWs N
    │
    └── Process (para queries IPC puntuales si necesario)

~/.local/bin/wayfire-ws-switch   ← Python. Cambia workspace + notifica a QML
~/.local/bin/wayfire-send-to-ws  ← Python. Mueve ventana enfocada a workspace N
~/.local/bin/qs-caelestia        ← Bash wrapper de `qs ipc --pid $pid call`
```

### `services/Hypr.qml` — propiedades expuestas

```qml
// Toplevels
readonly property var toplevels          // ScriptModel con todos los toplevels
readonly property var activeToplevel     // El toplevel activo/enfocado
property var hoveredToplevel             // El toplevel sobre el que está el ratón
                                         // (lo setea TaskList al hacer hover)

// Workspaces
readonly property int activeWsId         // 1-based (1..10), actualizado por setActiveWs()

// IPC
IpcHandler { target: "hypr"
    function setActiveWs(id: string): void    // llamado por wayfire-ws-switch
    function refreshDevices(): void           // stub
    function cycleSpecialWorkspace(): void    // stub
    function listSpecialWorkspaces(): string  // stub, retorna ""
}
```

---

## 4. Scripts auxiliares

Todos en `~/.local/bin/`. Deben tener `chmod +x`.

### `qs-caelestia`

```bash
#!/bin/bash
# Wrapper de `qs ipc` que encuentra el PID de Quickshell automáticamente
pid=$(pgrep -x quickshell | head -1)
[ -z "$pid" ] && exit 1
exec qs ipc --pid "$pid" call "$@"
```

### `wayfire-ws-switch N`

Cambia al workspace N (1-based) y notifica a Quickshell para actualizar el
indicador de workspace.

```python
#!/usr/bin/env python3
sock = os.environ.get('WAYFIRE_SOCKET', '/run/user/1000/wayfire-wayland-2-.socket')
ws_n = int(sys.argv[1])
x = (ws_n - 1) % 5
y = (ws_n - 1) // 5

for output_id in range(1, 10):
    result = ipc(sock, 'vswitch/set-workspace', {'x': x, 'y': y, 'output-id': output_id})
    if result.get('result') == 'ok':
        break

# Notifica a Quickshell para que actualice el indicador de workspace
subprocess.Popen(['qs-caelestia', 'hypr', 'setActiveWs', str(ws_n)], ...)
```

### `wayfire-send-to-ws N`

Mueve la ventana ENFOCADA al workspace N usando `stipc/feed_key` para inyectar
la combinación Super+Shift+N, que dispara `binding_win_N` en Wayfire.

```python
#!/usr/bin/env python3
sock = os.environ.get('WAYFIRE_SOCKET', '/run/user/1000/wayfire-wayland-2-.socket')
ws_n = int(sys.argv[1])
key = 'KEY_0' if ws_n == 10 else f'KEY_{ws_n}'

# Esperar a que activate() de QML sea procesado por el compositor
time.sleep(0.5)

# Inyectar Super+Shift+N
for ev in [
    ('KEY_LEFTMETA', True), ('KEY_LEFTSHIFT', True),
    (key, True), (key, False),
    ('KEY_LEFTSHIFT', False), ('KEY_LEFTMETA', False),
]:
    ipc(sock, 'stipc/feed_key', {'key': ev[0], 'state': ev[1]})
```

> **Estado actual:** `stipc/feed_key` retorna `{'result': 'ok'}` pero no hemos
> confirmado que `binding_win_N` se dispare efectivamente en Wayfire anidado.
> Ver sección §7 para el diagnóstico pendiente.

---

## 5. Wayfire IPC — Protocolo y lecciones aprendidas

### Protocolo del socket

**NO es líneas JSON delimitadas por `\n`.** Es un protocolo binario con
prefijo de longitud de 4 bytes little-endian:

```python
def ipc(sock_path, method, data=None):
    s = socket.socket(socket.AF_UNIX)
    s.connect(sock_path)
    payload = {'method': method}
    if data is not None:
        payload['data'] = data
    msg = json.dumps(payload).encode()
    s.send(struct.pack('<I', len(msg)) + msg)   # 4 bytes LE + JSON
    hdr = s.recv(4)
    n = struct.unpack('<I', hdr)[0]
    resp = b''
    while len(resp) < n:
        resp += s.recv(n - len(resp))
    s.close()
    return json.loads(resp)
```

### Métodos IPC disponibles (Wayfire 0.10 con stipc)

```
vswitch/set-workspace   {'x': int, 'y': int, 'output-id': int}  → {'result': 'ok'}
vswitch/send-view       {'view-id': uint64, 'x': int, 'y': int, 'output-id': int}
                        ⚠️  view-id NO es obtenible via IPC normal
stipc/feed_key          {'key': str, 'state': bool}  → {'result': 'ok'}
                        key = nombre XKB: 'KEY_LEFTMETA', 'KEY_1', etc.
                        state = True (press) / False (release)
stipc/run               {'cmd': str}  → {'result': 'ok', 'pid': int}
wm-actions/set-minimized    {'view_id': uint64, 'state': bool}
wm-actions/set-fullscreen   {'view_id': uint64, 'state': bool}
scale/toggle
expo/toggle
```

### Lección 1: `wtype` NO activa keybindings del compositor

`wtype` usa el protocolo `zwp_virtual_keyboard_v1`. Los compositores Wayland
(Wayfire incluido) deliberadamente NO procesan las teclas de este protocolo
como keybindings del compositor para evitar problemas de seguridad. Solo llegan
a la aplicación que tiene foco.

**Solución:** `stipc/feed_key` inyecta eventos directamente en el pipeline de
input de Wayfire, como si vinieran de un teclado físico real. Sí activa
keybindings.

### Lección 2: `vswitch/send-view` necesita view-id interno

`vswitch/send-view` requiere el `view-id` interno de Wayfire (uint64). Este ID
**no está disponible** a través de ningún método IPC estándar. No se puede
obtener desde `wlr-foreign-toplevel` ni desde ningún otro IPC del compositor.

La solución adoptada es indirecta: `stipc/feed_key` inyecta Super+Shift+N para
disparar el binding `[vswitch] binding_win_N`, que mueve la ventana **enfocada**.
Esto requiere llamar `activate()` antes para asegurar que la ventana esté enfocada.

### Lección 3: XDG_VIDEOS_DIR no está en el entorno de Quickshell

`os.getenv("XDG_VIDEOS_DIR")` y `Quickshell.env("XDG_VIDEOS_DIR")` devuelven
null. Las variables XDG están definidas en `~/.config/user-dirs.dirs`, no en el
entorno del proceso.

**Solución en `utils/Paths.qml`:**
```qml
Process {
    running: true
    command: ["bash", "-c", "source ~/.config/user-dirs.dirs && printf '%s\\n%s\\n' \"$XDG_VIDEOS_DIR\" \"$XDG_PICTURES_DIR\""]
    stdout: StdioCollector {
        onStreamFinished: {
            const lines = text.trim().split('\n');
            if (lines[0]) root.videos = lines[0];
            if (lines[1]) root.pictures = lines[1];
        }
    }
}
```

**Solución para el CLI `caelestia`:** wrapper en `~/.local/bin/caelestia` que
hace `source ~/.config/user-dirs.dirs && export XDG_VIDEOS_DIR ...` antes de
llamar al `/usr/local/bin/caelestia` real.

### Lección 4: Workspace grid 5×2

Wayfire usa una grilla 2D. Con `vwidth=5, vheight=2` hay 10 workspaces:
```
WS 1  WS 2  WS 3  WS 4  WS 5   (fila y=0)
WS 6  WS 7  WS 8  WS 9  WS 10  (fila y=1)
```
Conversión: `x = (N-1) % 5`, `y = (N-1) // 5`

### Lección 5: stipc plugin requerido para feed_key

El plugin `stipc` debe estar en la lista de plugins de `[core]`. Sin él,
`stipc/feed_key` no existe como método IPC.

---

## 6. Funcionalidades implementadas

### TaskList (`modules/bar/components/TaskList.qml`)

- Muestra iconos de todas las ventanas abiertas (via `ToplevelManager`)
- Click izquierdo: activa si no está activa, minimiza si está activa
- Sin menú de contexto (eliminado — era poco fluido con QtQuick.Controls.Menu)
- Hover → setea `Hypr.hoveredToplevel` (dispara el popup de preview)
- DropArea con timer 600ms para elevar ventana al arrastrar archivos encima

**Personalización de iconos:**
Los iconos usan tipografía Material Icons (catálogo: https://fonts.google.com/icons).
Se configuran en el archivo `~/.config/caelestia/shell.json`.
Ejemplo de configuración:

```json
    "bar": {
        "workspaces": {
            "windowIcons": [
                {
                    "icon": "public",
                    "name": "firefox"
                },
                {
                    "flags": "i",
                    "icon": "folder",
                    "regex": "nautilus"
                }
            ]
        }
    },
```

### Popup de ventana activa (`modules/bar/popouts/ActiveWindow.qml`)

- Se activa al hacer hover sobre cualquier icono del TaskList
- Muestra icono (via `Icons.getAppCategoryIcon`), título y appId
- ScreencopyView — presente pero no funciona en modo anidado (warning esperado)
- 5 botones de workspace (Tonal): envían la ventana al workspace 1-5
- Botón "Force Quit" (Filled, color error): mata el proceso con `pkill`

```qml
// Imports necesarios — asegurarse de que estén todos:
import qs.utils   // ← necesario para Icons; faltaba y causaba ReferenceError
```

**Force Quit:** usa `pkill -9 -i 'lastName'` (SIN `-x` para permitir coincidencia
parcial). Con `-x` (coincidencia exacta), `calculator` no mata `gnome-calculator`.

```qml
const cmd = "pkill -9 -i '" + lastName + "' 2>/dev/null || pkill -9 -f '" + target.appId + "' 2>/dev/null; true"
```

### Workspace indicator (`modules/bar/components/workspaces/`)

El indicador se actualiza cuando:
1. El usuario cambia workspace con Ctrl+N → `wayfire-ws-switch N` → llama
   `qs-caelestia hypr setActiveWs N` → `IpcHandler.setActiveWs()` en Hypr.qml
2. Quickshell llama internamente a `_switchWs()` (al hacer clic en el indicador)

**Hypr.qml** tiene un `IpcHandler` con `target: "hypr"` que expone `setActiveWs`:
```qml
IpcHandler {
    function setActiveWs(id: string): void { root._activeWsId = parseInt(id) }
    function refreshDevices(): void { }
    function cycleSpecialWorkspace(direction: string): void { }
    function listSpecialWorkspaces(): string { return ""; }
    target: "hypr"
}
```

### Grabador de pantalla

- `utils/Paths.qml`: lee `XDG_VIDEOS_DIR` desde `user-dirs.dirs` via Process
- `~/.local/bin/caelestia`: wrapper que exporta las vars XDG antes del CLI
- `modules/utilities/cards/RecordingList.qml`: usa `xdg-open` para reproducir
  y para abrir carpeta (en lugar de `Config.general.apps.playback/explorer`)

### Launcher (`modules/launcher/`, `modules/drawers/`)

- Listado y lanzamiento de apps con búsqueda en tiempo real
- **Foco automático al abrir:** cuando el launcher se activa, el campo de
  búsqueda recibe el foco de forma inmediata sin necesidad de hacer clic.
  Implementado con dos mecanismos:
  1. `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive` en
     `ContentWindow.qml` cuando `visibilities.launcher` es `true`.
     Esto fuerza a Wayfire a enrutar el teclado a la ventana de drawers
     en cuanto el launcher abre.
  2. `search.forceActiveFocus()` en `Content.qml` en `onLauncherChanged`
     y en `Window.onActiveChanged` como garantía adicional.
- **Cerrar al pulsar fuera del panel:** implementado con una ventana
  overlay independiente (`modules/drawers/DismissOverlay.qml`).

  **Por qué no funciona un `MouseArea` interno:** el `mask` del
  `ContentWindow` hace que el área del escritorio sea click-through
  (los clics pasan directamente al compositor sin llegar a la ventana).
  Un `MouseArea` interno con `z: -1` nunca los recibe.

  **Solución — `DismissOverlay`:** ventana `PanelWindow` pantalla completa,
  sin `mask` (toda la superficie es interactiva), en capa `WlrLayer.Top`.
  El `ContentWindow` usa `WlrLayer.Overlay`. La jerarquía fija del
  protocolo wlr-layer-shell (`Overlay > Top`) garantiza que:
  - Clics en el área del launcher → los recibe el ContentWindow (capa
    superior) porque esa zona está en su máscara interactiva.
  - Clics en el escritorio → pasan a través del ContentWindow (click-through
    allí por la máscara `Regions`) → los recibe el DismissOverlay (capa
    inferior) → cierra el drawer.

  `DismissOverlay` se instancia en `Drawers.qml` por cada pantalla y
  accede a las `visibilities` de su `ContentWindow` via alias expuesto.

---

## 7. Bugs pendientes y TODO

### Bug principal: botones de workspace del popup no mueven la ventana

**Síntoma:** Al clicar un botón de workspace en el popup, el script
`wayfire-send-to-ws` se ejecuta (confirmado), `stipc/feed_key` retorna `'ok'`
para todos los eventos, pero la ventana posiblemente no se mueve.

**Hipótesis más probable:** `activate()` del protocolo `wlr-foreign-toplevel`
puede que no cambie el foco de teclado en Wayfire anidado a tiempo (o en absoluto),
de modo que cuando se inyecta Super+Shift+N no hay ventana "enfocada" para mover.

**Diagnóstico pendiente:**
1. Probar `binding_win_N` manualmente (presionar Super+Shift+1 en Wayfire con
   una ventana enfocada) para confirmar que el binding funciona.
2. Si funciona manualmente, el problema es el timing de `activate()`.
3. Aumentar el `time.sleep` en `wayfire-send-to-ws` más allá de 0.5s.
4. O buscar una alternativa que no dependa de `activate()`: por ejemplo,
   registrar un binding temporal vía `command/register-binding` que mueva
   la ventana por appId en lugar de por foco.

**Alternativa a explorar:** `stipc/run` puede ejecutar comandos arbitrarios.
Si hay alguna herramienta CLI que pueda mover una ventana a un workspace
identificándola por app-id o título, se podría usar desde el script.

### Decoraciones SSD en GTK4 y Firefox

GTK4 ignora `assign_decoration_mode server` porque tiene CSD hardcodeado.
Firefox igual. Estas apps se mueven con Alt+drag (funcional). No hay solución
limpia con el protocolo estándar.

### `ScreencopyView` en modo anidado

Produce el warning `Capture source set to non captureable object` siempre en
Wayfire anidado. Esperado — Quickshell no puede capturar ventanas de un
compositor que corre dentro de otro. En instalación real (no anidada) podría
funcionar.

### `window-rules` error con app-id nulo

```
Window-rules: Error while executing rule on created signal
```

**Causa:** Quickshell crea superficies internas (tooltips, popups internos del
ScreencopyView...) con `app_id = null`. El patrón `.+` en la regla lo evita.
La regla actual en `wayfire.ini` ya usa `.+`:
```ini
rule_001 = on created if app_id matches .+ then assign_decoration_mode server
```

### `No free output buffer slot` (Wayfire anidado)

Error de rendering de Wayfire en modo anidado. Es cosmético. No afecta la
funcionalidad. Aparece bajo carga o cuando hay muchas superficies activas.

---

## 8. Limitaciones conocidas del protocolo

### `wlr-foreign-toplevel-management`

- **No expone la geometría** de las ventanas (posición, tamaño).
- **No expone en qué workspace** está cada ventana. Solo sabe si está
  `activated` o `minimized`.
- **No expone el PID** del proceso propietario de la ventana.
- `activate()` envía una solicitud al compositor, pero el compositor puede
  ignorarla (especialmente durante drag-and-drop o cuando hay otro cliente
  con foco exclusivo).

### Workspace occupancy

El indicador de workspace solo puede saber que un workspace está ocupado si
conoce qué workspaces hay. Sin información de qué workspace tiene cada ventana,
solo se puede resaltar el workspace ACTIVO correctamente.

### Minimizado y workspace assignment

`ToplevelHandle.minimized = true/false` funciona. Pero no hay forma de saber
en qué workspace estaba una ventana antes de minimizarla ni de restaurarla
al workspace original.

---

## 9. Plan de fases original (referencia)

> Esta sección conserva el plan de implementación original para referencia
> histórica. La mayoría de la Fase 1 ya está completada con una arquitectura
> diferente a la planificada (se mantiene `Hypr.qml` en lugar de crear
> `WayfireService.qml` + renombrar).

### Auditoría de dependencias Hyprland

#### Archivos reescritos completamente

| Archivo | Estado |
|---|---|
| `services/Hypr.qml` | ✅ Reescrito — ToplevelManager + Wayfire IPC |
| `modules/bar/components/TaskList.qml` | ✅ Reescrito — sin menú contextual, con hover |
| `modules/bar/popouts/ActiveWindow.qml` | ✅ Reescrito — con botones workspace y force quit |
| `modules/windowcontrols/Wrapper.qml` | ✅ Portado |
| `modules/bar/components/WindowControls.qml` | ✅ Portado |
| `components/misc/CustomShortcut.qml` | ✅ Stub vacío |
| `modules/bar/components/workspaces/Workspaces.qml` | ✅ Portado |
| `modules/bar/components/workspaces/Workspace.qml` | ✅ Portado |
| `modules/areapicker/Picker.qml` | ✅ Limpiado (eliminado hyprctl cursorpos) |
| `utils/Paths.qml` | ✅ XDG dirs via Process |

#### Archivos con stubs o desactivados

| Archivo | Estado |
|---|---|
| `modules/drawers/ContentWindow.qml` | ✅ HyprlandFocusGrab → DismissOverlay; foco exclusivo para launcher/sesión |
| `modules/drawers/DismissOverlay.qml` | ✅ **[NUEVO]** Overlay WlrLayer.Top que cierra drawers al pulsar fuera |
| `services/SpecialWorkspaces.qml` | ✅ Stub vacío (Item {}) |

### Mapa de equivalencias IPC

| Concepto Hyprland | Equivalente Wayfire implementado |
|---|---|
| `HyprlandToplevel` | `Quickshell.Wayland.ToplevelHandle` |
| `Hypr.toplevels` | `ToplevelManager.toplevels` |
| `Hypr.activeToplevel` | `ToplevelManager.activeToplevel` |
| `Hypr.activeWsId` | `Hypr._activeWsId` (actualizado via IPC + setActiveWs) |
| `toplevel.activate()` | `ToplevelHandle.activate()` |
| `toplevel.minimized = true/false` | `ToplevelHandle.minimized = true/false` |
| `toplevel.close()` | `ToplevelHandle.close()` |
| `dispatch("workspace N")` | `vswitch/set-workspace` via `wayfire-ws-switch N` |
| `dispatch("movetoworkspace N,address:...")` | `stipc/feed_key` Super+Shift+N via `wayfire-send-to-ws N` |
| `CustomShortcut` | Bindings en `[command]` de `wayfire.ini` |
| `IpcHandler` | Sin cambios — no depende de Hyprland |

---

## 10. Sesión real GDM — configuración extra

El desarrollo se hizo en **Wayfire anidado** dentro de Hyprland, donde muchos
problemas de entorno quedan ocultos porque la sesión de Hyprland ya tiene todo
configurado. Al arrancar Wayfire como sesión principal desde GDM aparecen dos
problemas que no ocurren en anidado.

### Problema 1: PATH incompleto

GDM arranca Wayfire con un PATH mínimo del sistema que **no incluye
`~/.local/bin/`**. Esto impide que Quickshell encuentre `app2unit`, y que los
bindings de teclado en `wayfire.ini` encuentren `qs-caelestia` y
`wayfire-ws-switch`.

**Síntoma en sesión anidada:** no existe — el PATH lo hereda del terminal de
Hyprland donde se lanzó todo manualmente.

**Arreglos aplicados:**

1. `~/.local/bin/caelestia-wayfire-start` — añadida la línea:
   ```bash
   export PATH="/home/minino/.local/bin:$PATH"
   ```
   Antes del `exec quickshell ...`, para que Quickshell vea los scripts auxiliares.

2. `~/.config/wayfire.ini` — todos los `command_*` que usan scripts de
   `~/.local/bin/` usan ahora la **ruta absoluta**:
   ```ini
   command_launcher = /home/minino/.local/bin/qs-caelestia drawers toggle launcher
   command_ws1      = /home/minino/.local/bin/wayfire-ws-switch 1
   # … etc.
   ```

3. `~/.config/environment.d/50-local-bin.conf` — fix permanente para futuros
   logins (leído por systemd/PAM al iniciar sesión):
   ```
   PATH=/home/minino/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
   ```

> **Nota para publicación en GitHub:** las rutas absolutas en `wayfire.ini` y
> `caelestia-wayfire-start` deben eliminarse antes de publicar. La solución
> limpia es un script `install.sh` que sustituya `$HOME` por la ruta real del
> sistema destino.

### Problema 2: xdg-desktop-portal usa el backend GNOME

`xdg-desktop-portal` es el servicio que proporciona a las apps acceso a diálogos
de archivo, configuración de tema, inhibición de pantalla, etc. Ubuntu instala
`xdg-desktop-portal-gnome` que requiere GNOME Shell — ausente en Wayfire.

**Síntoma en sesión anidada:** no existe — el portal lo gestiona la sesión de
Hyprland en la que Wayfire está anidado, y ya tiene su backend correcto activo.

**Síntoma en sesión real:** las apps GTK/libadwaita (GNOME Calculator, Nautilus,
etc.) tardan 1-3 minutos en arrancar. Cada interfaz del portal (Settings,
Background, Inhibit…) espera 25 segundos antes de fallar:
```
Cannot get portal org.freedesktop.portal.Settings version: Timeout was reached
```

**Diagnóstico:** el portal principal lee `wayfire-portals.conf` del sistema
(`/usr/share/xdg-desktop-portal/wayfire-portals.conf`) que dice `default=wlr;*`.
`wlr` no está instalado, y el comodín `*` incluye gnome como backend secundario.
El portal intenta activar todos los backends durante el arranque — gnome tarda 25
segundos en fallar para cada interfaz que reclama.

Revelado con:
```bash
G_MESSAGES_DEBUG=all /usr/libexec/xdg-desktop-portal 2>&1 | grep -E "Looking for|Using|Found"
```

**Arreglo:**

```bash
# 1. Instalar el backend correcto para compositores wlroots
sudo apt install xdg-desktop-portal-wlr

# 2. Eliminar el comodín * del archivo del sistema para que nunca se pruebe gnome
sudo tee /usr/share/xdg-desktop-portal/wayfire-portals.conf << 'EOF'
[preferred]
default=wlr;gtk;
org.freedesktop.impl.portal.Inhibit=none
org.freedesktop.impl.portal.Background=none
org.freedesktop.impl.portal.Wallpaper=none
EOF
```

Con esto:
- `wlr` maneja ScreenCast y Screenshot (diseñado para wlroots)
- `gtk` maneja Settings, FileChooser, Notification, etc.
- Las interfaces sin soporte (`Inhibit`, `Background`, `Wallpaper`) se deshabilitan
  explícitamente con `none` en lugar de intentar GNOME

**Override de systemd** — garantiza que el portal vea `XDG_CURRENT_DESKTOP=Wayfire`
incluso si arranca antes de que el autostart de Wayfire exporte la variable:

`~/.config/systemd/user/xdg-desktop-portal.service.d/override.conf`:
```ini
[Service]
Environment=XDG_CURRENT_DESKTOP=Wayfire
```

**Override de usuario** (refuerzo, por si se actualiza el paquete del sistema):

`~/.config/xdg-desktop-portal/wayfire-portals.conf`:
```ini
[preferred]
default=gtk;
org.freedesktop.impl.portal.Inhibit=none
org.freedesktop.impl.portal.Background=none
org.freedesktop.impl.portal.Wallpaper=none
```

> **Nota:** el archivo de usuario se busca en `~/.config/xdg-desktop-portal/`
> pero el portal **fusiona** todos los configs encontrados en lugar de usar solo
> el primero. Por eso el arreglo principal es eliminar el `*` del archivo del
> sistema — el override de usuario solo sirve como segunda línea de defensa.

### Autostart en `wayfire.ini` para sesión real

```ini
[autostart]
autostart_wf_shell = false
0_env    = dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY WAYFIRE_SOCKET XDG_CURRENT_DESKTOP=Wayfire XCURSOR_SIZE=48 QT_QPA_PLATFORMTHEME=gtk3
1_portal = systemctl --user restart xdg-desktop-portal.service
1_xhost  = xhost +si:localuser:root
2_qs     = /home/minino/.local/bin/caelestia-wayfire-start
```

- `1_portal` fuerza un reinicio del portal después de que `0_env` exporte
  `XDG_CURRENT_DESKTOP=Wayfire`, por si el portal arrancó antes del autostart
  con un desktop incorrecto.
- `1_xhost` permite lanzar apps gráficas con `sudo` sin tener que ejecutar
  `xhost +si:localuser:root` manualmente cada sesión.
- `foot` se eliminó del autostart una vez que el launcher funciona en sesión real.
  Sigue disponible con Super+Enter.

### Problema 3: Scroll direction

El sentido del scroll de touchpad en GDM es el inverso al habitual. Se corrige
en la sección `[input]` de `wayfire.ini`:

```ini
[input]
natural_scroll = true   # estilo móvil/Mac: contenido sigue el dedo
# natural_scroll = false  # estilo tradicional de escritorio
```

Wayfire recarga la configuración en caliente — no hace falta reiniciar.

### Problema 4: Apps GUI con sudo

Sin configuración extra, las apps gráficas lanzadas con `sudo` no pueden
conectarse al servidor X11 de la sesión. La entrada `1_xhost` del autostart
(ver arriba) lo resuelve permanentemente. Para activarlo en la sesión actual
sin reiniciar:

```bash
xhost +si:localuser:root
```

### Apariencia de apps Qt y temas del sistema

`qt6-gtk-platformtheme` ya está instalado en Ubuntu 26.04. Activarlo:

```bash
# Exportar en el entorno de sesión (ya incluido en 0_env del autostart):
QT_QPA_PLATFORMTHEME=gtk3
```

También añadido en `~/.config/environment.d/50-local-bin.conf` y en
`~/.local/bin/caelestia-wayfire-start` para que todas las apps lo hereden.

Con esto VLC, KDE apps y cualquier app Qt siguen automáticamente el tema GTK
activo (Yaru-wartybrown) — fuente, colores, iconos y diálogos de archivo.

### CSD vs SSD — decoraciones de ventana

El plugin `[decoration]` de Wayfire dibuja barras de título para apps que no
tienen la suya (SSD — server-side decorations). Sus botones son figuras
geométricas hardcodeadas en código, sin soporte de temas.

**Decisión adoptada: usar CSD** (client-side decorations) en lugar de SSD
global. Cada app dibuja su propia barra:

- Apps GTK4 (Calculator, Nautilus…): barra Adwaita idéntica a GNOME ✓
- Apps Qt con `QT_QPA_PLATFORMTHEME=gtk3`: siguen Yaru ✓
- VLC, Firefox, LibreOffice: sus propias CSD ✓
- **foot y apps sin CSD**: sin barra de título — mover con Alt+arrastrar

Configuración aplicada:

```ini
# wayfire.ini — [core]
preferred_decoration_mode = client

# [window-rules] — la regla SSD global está desactivada:
# rule_001 = on created if app_id matches .+ then assign_decoration_mode server
```

Si una app concreta necesita SSD, añadir una regla específica:
```ini
rule_foot = on created if app_id equals foot then assign_decoration_mode server
```

### Decoración SSD para apps sin CSD (HiDPI)

Para las apps que aún reciben SSD (si se reactiva la regla), los colores
extraídos directamente del tema GTK3 de Yaru-wartybrown:

```ini
[decoration]
active_color   = \#EBEBEBFF   # headerbar activo de Yaru-wartybrown (medido via GTK3)
inactive_color = \#D8D8D8FF   # headerbar inactivo
font_color     = \#3D3D3DFF   # texto oscuro (igual que GNOME)
font           = Ubuntu Bold 8
title_height   = 22
border_size    = 1
button_order   = minimize maximize close
```

**Nota HiDPI:** el plugin `decoration` renderiza la fuente a la densidad física
del display (276 DPI en pantalla 3000×2000). A escala 2×, 11pt físicos equivalen
visualmente a ~22pt — hay que usar aproximadamente la mitad del tamaño deseado.
En este equipo, `8` produce un resultado visualmente equivalente a 11pt en 96 DPI.

### Problema 5: Animación squeezimize sin apuntar al icono

El plugin `animate` de Wayfire incluye la animación `squeezimize`: al minimizar,
la ventana se comprime hacia un punto destino (`target_box`). Para que apunte al
icono correcto en la barra, el cliente debe enviar un *minimize hint* vía el
protocolo `wlr-foreign-toplevel-management` (`set_rectangle`). Sin ese hint,
`target_box` está vacío y la ventana se comprime hacia una posición por defecto.

**Configuración en `wayfire.ini`:**

```ini
[animate]
open_animation   = zoom
close_animation  = zoom
minimize_animation = squeezimize
```

El plugin está habilitado y la animación funciona, pero **no apunta al icono**.

#### Por qué no se puede enviar el hint con Quickshell 0.2.1

Quickshell expone `Toplevel.setRectangle(window, rect)` en el módulo
`Quickshell.Wayland`. Internamente hace:

```
ProxyWindowBase::forObject(window) → backingWindow()
  → ToplevelHandle::setRectangle(QWindow*, QRect)
    → set_rectangle en wlr-foreign-toplevel
```

El problema está en el binario de Ubuntu (`/usr/local/bin/quickshell`, versión
0.2.1): tiene el plugin Hyprland compilado **estáticamente**. Al llamar
`setRectangle`, Qt inicializa los plugins estáticos, incluyendo
`qt_plugin_instance_Quickshell_Hyprland__SurfaceExtensionsPlugin`. Ese plugin
busca el protocolo `hyprland_surface_v1`, que no existe en Wayfire, y **crashea**.

**Backtrace del crash:**
```
#0  qt_plugin_instance_Quickshell_Hyprland__SurfaceExtensionsPlugin() [clone .cold]
    offset: 0xc8ae2 in /usr/local/bin/quickshell
Segmentation fault at address 0x70  (null pointer + 112 bytes)
```

#### Intento: recompilar sin Hyprland

Se recompiló Quickshell desde `/home/minino/tmp/quickshell/` con:

```bash
cmake .. -DHYPRLAND=OFF
rm -f src/quickshell   # forzar reenlace
ninja
sudo ninja install     # instala en /usr/bin/quickshell
```

El nuevo binario no tiene `SurfaceExtensionsPlugin`, pero **crashea de otra
forma** al aparecer cualquier ventana nueva, incluso sin llamar `setRectangle`:

```
#0  FloatingWindowInterface::FloatingWindowInterface(QObject*) [clone .cold]
    offset: 0xc7e22 in /usr/bin/quickshell
Segmentation fault at address 0x70
```

Este crash es un bug en la versión compilada, no relacionado con Hyprland.
El binario de Ubuntu no tiene este problema porque usa una versión distinta del
código de `FloatingWindowInterface`.

#### Estado actual

- Se usa `/usr/local/bin/quickshell` (paquete Ubuntu 0.2.1), **sin** llamar
  `setRectangle`.
- `modules/bar/components/TaskList.qml`, `bar/Bar.qml`, `bar/BarWrapper.qml` y
  `drawers/ContentWindow.qml` **no** contienen ninguna referencia a
  `shellWindow` ni `setRectangle` (el código se eliminó para evitar el crash).
- La animación squeezimize está activa y funciona, pero la ventana se comprime
  hacia un punto central, no hacia el icono de la barra.

#### Caminos posibles a futuro

1. **Esperar fix upstream**: cuando el bug de `FloatingWindowInterface` se
   corrija en la rama de desarrollo de Quickshell, el binario compilado con
   `-DHYPRLAND=OFF` debería funcionar y `setRectangle` podrá llamarse sin crash.
2. **Parchear el binario Ubuntu**: modificar el código fuente de Quickshell para
   añadir un guard que compruebe si `hyprland_surface_v1` existe antes de
   inicializar `SurfaceExtensionsPlugin`. PR potencial upstream.
3. **Dejar squeezimize sin hint**: la animación sigue siendo visualmente
   agradable incluso sin apuntar al icono exacto.

## 11. Carga de traducciones y recursos Qt (Q_INIT_RESOURCE)

Para que las traducciones (`.qm`) u otros recursos Qt embebidos en el código C++ a través de `qt_add_translations` se carguen correctamente en un plugin QML o librería compartida, es necesario tener en cuenta el **"static initialization order fiasco"** de C++.

En Caelestia, si se utiliza un constructor estático (como `struct TranslationLoader { ... } s_loader;`) para instalar las traducciones en el momento de carga del plugin (`dlopen`), el sistema de recursos de Qt puede no haber inicializado aún el archivo `.qrc` correspondiente (ya que el orden de inicialización de los constructores estáticos entre distintos `.cpp` es indefinido). Si esto ocurre, la aplicación buscará `:/i18n/caelestia_es.qm` y fallará silenciosamente, mostrando la interfaz en el idioma original.

**Solución:**
Siempre se debe forzar la inicialización del recurso llamando explícitamente a `qInitResources_<nombre_del_recurso>()` antes de intentar usarlo:

```cpp
// Declaración de la función generada automáticamente por rcc (Qt Resource Compiler)
void qInitResources_caelestia_translations();

void installTranslations() {
    // Inicialización forzada del recurso antes de buscar los archivos .qm
    qInitResources_caelestia_translations(); 
    
    // ... carga del QTranslator normal ...
}
```
Esto garantiza que el archivo `.qm` empaquetado esté registrado y disponible en el sistema de archivos virtual de Qt (`:/`) para cuando `translator->load()` intente acceder a él.

---

## Referencias técnicas

- **Wayfire IPC socket**: `$WAYFIRE_SOCKET` — protocolo con prefijo 4 bytes LE
- **wlr-foreign-toplevel-management**: protocolo Wayland de wlroots
- **Quickshell docs**: `quickshell.outfoxxed.me`
- **Wayfire wiki**: `github.com/WayfireWM/wayfire/wiki`
- **stipc plugin**: `github.com/WayfireWM/wayfire/blob/master/plugins/stipc/`
