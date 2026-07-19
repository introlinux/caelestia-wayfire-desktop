# Caelestia + Wayfire Desktop

Entorno de escritorio Wayland completo para **Ubuntu 26.04**: el shell
[Caelestia](https://github.com/caelestia-dots/shell) (QML/Quickshell) portado de
Hyprland a **Wayfire**, con minimizado nativo, barra de tareas funcional,
dock de MiniApps estilo ROX-Filer y toda la apariencia clonada al detalle
(tema, iconos, cursor, fuentes y fondos de pantalla).

## ¿Qué incluye?

| Componente | Descripción |
|---|---|
| `shell/` | Caelestia Shell portado a Wayfire (sin dependencias de Hyprland) |
| `config/` | `wayfire.ini`, `shell.json`, portales XDG, GTK, environment.d |
| `bin/` | Scripts auxiliares (`wayfire-ws-switch`, `qs-caelestia`, arranque…) |
| `themes/` | Cursor **clay-dark** y fuentes Material Symbols + Rubik |
| `wallpapers/` | Fondos de pantalla |
| `miniapps/` | Dock de MiniApps (AppDirs ROX + lanzadores .desktop) |
| `packages/` | Listas de paquetes APT (runtime y compilación) |
| `install.sh` | Instalador completo para un Ubuntu recién instalado |

Se compilan desde fuente (versiones fijadas por el instalador):
[Quickshell](https://quickshell.outfoxxed.me/) v0.2.1, el plugin C++ de
Caelestia, [libcava](https://github.com/LukashonakV/cava),
[gpu-screen-recorder](https://git.dec05eba.com/gpu-screen-recorder/about/) y la
[CLI de Caelestia](https://github.com/caelestia-dots/cli).
La fuente CaskaydiaCove Nerd Font se descarga de las releases de
[nerd-fonts](https://github.com/ryanoasis/nerd-fonts) v3.4.0.

## Instalación

Sobre un Ubuntu 26.04 recién instalado (escritorio GNOME por defecto):

```bash
git clone https://github.com/introlinux/caelestia-wayfire-desktop.git
cd caelestia-wayfire-desktop
./install.sh
```

El script pide `sudo` cuando lo necesita y hace **copia de seguridad** de
cualquier fichero tuyo que vaya a sobrescribir (en
`~/.caelestia-wayfire-backup-FECHA`). La compilación de Quickshell tarda
varios minutos.

Opciones:

```
./install.sh --skip-apt        # no instalar paquetes APT
./install.sh --skip-builds     # no compilar nada (solo ficheros de usuario)
./install.sh --only-dotfiles   # solo configs, temas, scripts y MiniApps
```

Al terminar: cierra la sesión y en GDM elige la sesión **Wayfire** (icono del
engranaje). Caelestia arranca automáticamente.

## Atajos de teclado

| Atajo | Acción |
|---|---|
| `Super+D` | Lanzador (también tocando el borde inferior de la pantalla) |
| `Super+E` | Dashboard |
| `Super+S` | Barra lateral |
| `Super+U` | Utilidades (grabador, selector de color…) |
| `Super+L` | Bloquear sesión |
| `Super+Enter` | Terminal |
| `Ctrl+1..4` | Cambiar de workspace |
| `Super+Shift+1..4` | Enviar ventana al workspace N |
| `Super+Q` / `Alt+F4` | Cerrar ventana |
| `Super+F5` | Recargar el shell |

El **dock de MiniApps** se abre acercando el ratón a la esquina inferior
izquierda; acepta arrastrar y soltar archivos sobre sus herramientas.

## Notas técnicas / problemas conocidos

- **Portal XDG**: el instalador ajusta `/usr/share/xdg-desktop-portal/wayfire-portals.conf`
  a `default=wlr;gtk;` — sin esto, las apps tardan minutos en abrir diálogos
  (timeout de 25 s por interfaz al intentar el backend de GNOME).
- **Quickshell**: se usa v0.2.1 compilado desde fuente. El shell evita
  `Toplevel.setRectangle()` (crashea en Wayfire); por eso la animación de
  minimizado no apunta al icono de la barra.
- **wlr-foreign-toplevel** no expone geometría ni workspace por ventana:
  algunas funciones se aproximan (identificación de ventanas por sondeo).
- Apps GTK4 y Firefox rechazan la decoración del servidor: muévelas con
  `Super+arrastrar` si hace falta.
- Grabación de pantalla con `gpu-screen-recorder`; los vídeos van a
  `~/Vídeos/Recordings`.
- Gato de escritorio `oneko-rust` (persigue el cursor; port propio a Wayfire
  vía IPC). Arranca con la sesión y se puede encender/apagar con un clic en
  el gato de la sección Multimedia del dashboard. Opciones en
  `oneko-rust --help` (velocidad, radio, distancia de parada…).

## Créditos

- [caelestia-dots/shell](https://github.com/caelestia-dots/shell) — el shell original (GPLv3)
- [Quickshell](https://quickshell.outfoxxed.me/) — runtime QML para Wayland
- [Wayfire](https://wayfire.org/) — compositor
- [gpu-screen-recorder](https://git.dec05eba.com/gpu-screen-recorder/about/) — dec05eba
- [Oneko-Rust-Arch](https://github.com/Abishek-Pechiappan/Oneko-Rust-Arch) — oneko para Wayland (GPLv3), portado a Wayfire con `patches/oneko-rust-wayfire.patch`
- [nerd-fonts](https://github.com/ryanoasis/nerd-fonts) — CaskaydiaCove
- Tema de cursor **clay-dark** y tema GTK/iconos **Yaru-wartybrown** (Ubuntu)

La licencia del shell se mantiene (ver `shell/LICENSE`).
