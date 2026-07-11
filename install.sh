#!/usr/bin/env bash
# =============================================================================
# Instalador de Caelestia + Wayfire para Ubuntu 26.04
# Replica el entorno de escritorio completo: compositor, shell, temas,
# fuentes, cursor, fondos de pantalla, MiniApps y scripts auxiliares.
#
# Uso:  ./install.sh [--skip-apt] [--skip-builds] [--only-dotfiles]
#
# Se ejecuta como usuario normal (pedirá sudo cuando haga falta).
# =============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${REPO}/.build"
BACKUP_DIR="${HOME}/.caelestia-wayfire-backup-$(date +%Y%m%d-%H%M%S)"

# Versiones fijadas (las mismas con las que se creó el entorno original)
WAYFIRE_REPO="https://github.com/WayfireWM/wayfire.git"
WAYFIRE_TAG="v0.10.1"
WF_PLUGINS_EXTRA_REPO="https://github.com/WayfireWM/wayfire-plugins-extra.git"
WF_PLUGINS_EXTRA_TAG="v0.10.0"
QUICKSHELL_REPO="https://git.outfoxxed.me/quickshell/quickshell.git"
QUICKSHELL_TAG="v0.3.0"
LIBCAVA_REPO="https://github.com/LukashonakV/cava.git"
LIBCAVA_TAG="0.10.7"
GSR_REPO="https://repo.dec05eba.com/gpu-screen-recorder"
GSR_COMMIT="e48be50"
WCM_REPO="https://github.com/WayfireWM/wcm.git"
WCM_TAG="v0.10.0"
CAELESTIA_CLI_REPO="https://github.com/caelestia-dots/cli.git"
CAELESTIA_CLI_COMMIT="eddee4dec"
NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/CascadiaCode.zip"

SKIP_APT=0 SKIP_BUILDS=0 ONLY_DOTFILES=0
for arg in "$@"; do
    case "$arg" in
        --skip-apt)      SKIP_APT=1 ;;
        --skip-builds)   SKIP_BUILDS=1 ;;
        --only-dotfiles) ONLY_DOTFILES=1; SKIP_APT=1; SKIP_BUILDS=1 ;;
        *) echo "Opción desconocida: $arg"; exit 1 ;;
    esac
done

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
    echo "Ejecuta este script como usuario normal, no como root."; exit 1
fi

if ! grep -q "Ubuntu" /etc/os-release; then
    warn "Este instalador está pensado para Ubuntu 26.04. Continuando bajo tu responsabilidad."
fi

# Copia de seguridad de un fichero/directorio de usuario antes de sobrescribirlo
backup() {
    local target="$1"
    if [ -e "$target" ]; then
        local rel="${target#"$HOME"/}"
        mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        cp -a "$target" "$BACKUP_DIR/$rel"
    fi
}

# Copia un fichero sustituyendo el marcador __HOME__ por el $HOME real
install_templated() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    backup "$dst"
    sed "s|__HOME__|$HOME|g" "$src" > "$dst"
}

# -----------------------------------------------------------------------------
# 1. Paquetes APT
# -----------------------------------------------------------------------------
if [ "$SKIP_APT" -eq 0 ]; then
    log "Instalando paquetes APT (runtime + compilación)"
    mapfile -t pkgs < <(grep -hv '^#' "$REPO/packages/apt-runtime.txt" "$REPO/packages/apt-build.txt" | grep -v '^$')
    sudo apt-get update
    sudo apt-get install -y "${pkgs[@]}"
fi

# -----------------------------------------------------------------------------
# 2. Compilaciones desde fuente
# -----------------------------------------------------------------------------
if [ "$SKIP_BUILDS" -eq 0 ]; then
    mkdir -p "$BUILD_DIR"

    # --- Wayfire (compositor) --------------------------------------------------
    # Se instala en /usr/local, que tiene prioridad en el PATH de la sesión GDM
    # sobre el paquete de Ubuntu. Necesario para wayfire-plugins-extra (view-shot,
    # extra-animations), que no está empaquetado en Ubuntu.
    if /usr/local/bin/wayfire --version 2>/dev/null | grep -q "^0\.10\.1"; then
        log "Wayfire 0.10.1 ya instalado en /usr/local — omitiendo"
    else
        log "Compilando Wayfire $WAYFIRE_TAG"
        rm -rf "$BUILD_DIR/wayfire"
        git clone --depth 1 --branch "$WAYFIRE_TAG" "$WAYFIRE_REPO" "$BUILD_DIR/wayfire"
        meson setup "$BUILD_DIR/wayfire/build" "$BUILD_DIR/wayfire" \
            --prefix=/usr/local --buildtype=release \
            -Duse_system_wlroots=enabled -Duse_system_wfconfig=enabled -Dtests=disabled
        ninja -C "$BUILD_DIR/wayfire/build"
        sudo ninja -C "$BUILD_DIR/wayfire/build" install
        sudo ldconfig
        # El wayfire-portals.conf de upstream usa «default=wlr;*»: el comodín hace
        # que xdg-desktop-portal intente el backend de GNOME, que se cuelga sin
        # sesión GNOME (timeouts de 25 s por interfaz y apps que tardan minutos
        # en abrir). Se sobrescribe con la versión segura del port.
        sudo cp "$REPO/system/xdg-desktop-portal/wayfire-portals.conf" \
            /usr/local/share/xdg-desktop-portal/wayfire-portals.conf
    fi

    # --- wayfire-plugins-extra (view-shot para miniaturas, animaciones extra) --
    if [ -f /usr/local/lib/x86_64-linux-gnu/wayfire/libview-shot.so ]; then
        log "wayfire-plugins-extra ya instalado — omitiendo"
    else
        log "Compilando wayfire-plugins-extra $WF_PLUGINS_EXTRA_TAG"
        rm -rf "$BUILD_DIR/wayfire-plugins-extra"
        git clone --depth 1 --branch "$WF_PLUGINS_EXTRA_TAG" "$WF_PLUGINS_EXTRA_REPO" \
            "$BUILD_DIR/wayfire-plugins-extra"
        # meson no detecta Boost solo-cabeceras (libboost-dev sin libs compiladas);
        # los headers están en /usr/include, que el compilador ya usa por defecto.
        sed -i "s/boost = dependency('boost')/boost = declare_dependency()/" \
            "$BUILD_DIR/wayfire-plugins-extra/src/extra-animations/meson.build"
        PKG_CONFIG_PATH=/usr/local/lib/x86_64-linux-gnu/pkgconfig meson setup \
            "$BUILD_DIR/wayfire-plugins-extra/build" "$BUILD_DIR/wayfire-plugins-extra" \
            --prefix=/usr/local --buildtype=release
        ninja -C "$BUILD_DIR/wayfire-plugins-extra/build"
        sudo ninja -C "$BUILD_DIR/wayfire-plugins-extra/build" install
    fi

    # --- shift-switcher (animación de raise estilo baraja de cartas, in-repo) --
    log "Compilando wayfire-shift-switcher"
    rm -rf "$BUILD_DIR/wayfire-shift-switcher"
    PKG_CONFIG_PATH=/usr/local/lib/x86_64-linux-gnu/pkgconfig meson setup \
        "$BUILD_DIR/wayfire-shift-switcher" "$REPO/wayfire-shift-switcher" \
        --prefix=/usr/local --buildtype=release
    ninja -C "$BUILD_DIR/wayfire-shift-switcher"
    sudo ninja -C "$BUILD_DIR/wayfire-shift-switcher" install

    # --- WCM (Wayfire Config Manager) contra el wayfire de /usr/local ---------
    # El wcm de Ubuntu lleva compilada la ruta /usr/share/wayfire/metadata, así
    # que no ve los plugins del stack de /usr/local (shift-switcher, view-shot…).
    if strings /usr/local/bin/wcm 2>/dev/null | grep -q "/usr/local/share/wayfire/metadata"; then
        log "wcm ya instalado — omitiendo"
    else
        log "Compilando wcm $WCM_TAG"
        rm -rf "$BUILD_DIR/wcm"
        git clone --depth 1 --branch "$WCM_TAG" "$WCM_REPO" "$BUILD_DIR/wcm"
        PKG_CONFIG_PATH=/usr/local/lib/x86_64-linux-gnu/pkgconfig meson setup \
            "$BUILD_DIR/wcm/build" "$BUILD_DIR/wcm" \
            --prefix=/usr/local --buildtype=release
        ninja -C "$BUILD_DIR/wcm/build"
        sudo ninja -C "$BUILD_DIR/wcm/build" install
    fi

    # --- Quickshell -----------------------------------------------------------
    if /usr/local/bin/quickshell --version 2>/dev/null | grep -q "0\.3\.0"; then
        log "Quickshell 0.3.0 ya instalado — omitiendo"
    else
        log "Compilando Quickshell $QUICKSHELL_TAG (tardará varios minutos)"
        rm -rf "$BUILD_DIR/quickshell"
        git clone --depth 1 --branch "$QUICKSHELL_TAG" "$QUICKSHELL_REPO" "$BUILD_DIR/quickshell"
        cmake -S "$BUILD_DIR/quickshell" -B "$BUILD_DIR/quickshell/build" -G Ninja \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DCMAKE_INSTALL_PREFIX=/usr/local \
            -DCRASH_HANDLER=OFF \
            -DSERVICE_POLKIT=OFF \
            -DNETWORK=OFF \
            -DDISTRIBUTOR="caelestia-wayfire-desktop (self-built)"
        cmake --build "$BUILD_DIR/quickshell/build"
        sudo cmake --install "$BUILD_DIR/quickshell/build"
        sudo ln -sf /usr/local/bin/quickshell /usr/local/bin/qs
    fi

    # --- libcava (fork con cavacore, necesario para el plugin de Caelestia) ---
    if pkg-config --exists libcava 2>/dev/null; then
        log "libcava ya instalada — omitiendo"
    else
        log "Compilando libcava $LIBCAVA_TAG"
        rm -rf "$BUILD_DIR/libcava"
        git clone --depth 1 --branch "$LIBCAVA_TAG" "$LIBCAVA_REPO" "$BUILD_DIR/libcava"
        meson setup "$BUILD_DIR/libcava/build" "$BUILD_DIR/libcava" --prefix=/usr/local --buildtype=release
        ninja -C "$BUILD_DIR/libcava/build"
        sudo ninja -C "$BUILD_DIR/libcava/build" install
        sudo ldconfig
    fi

    # --- Plugin C++ de Caelestia (QML, se instala en /usr/lib/qt6/qml) --------
    log "Compilando el plugin C++ de Caelestia Shell"
    cmake -S "$REPO/shell" -B "$BUILD_DIR/shell-plugin" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/ \
        -DVERSION=0.0.1 -DGIT_REVISION=dev \
        -DENABLE_MODULES=plugin
    cmake --build "$BUILD_DIR/shell-plugin"
    sudo cmake --install "$BUILD_DIR/shell-plugin"

    # --- gpu-screen-recorder (grabación de pantalla eficiente) ----------------
    if command -v gpu-screen-recorder >/dev/null; then
        log "gpu-screen-recorder ya instalado — omitiendo"
    else
        log "Compilando gpu-screen-recorder ($GSR_COMMIT)"
        rm -rf "$BUILD_DIR/gpu-screen-recorder"
        git clone "$GSR_REPO" "$BUILD_DIR/gpu-screen-recorder"
        git -C "$BUILD_DIR/gpu-screen-recorder" checkout "$GSR_COMMIT"
        meson setup "$BUILD_DIR/gpu-screen-recorder/build" "$BUILD_DIR/gpu-screen-recorder" \
            --prefix=/usr --buildtype=release
        ninja -C "$BUILD_DIR/gpu-screen-recorder/build"
        sudo ninja -C "$BUILD_DIR/gpu-screen-recorder/build" install
        sudo setcap cap_sys_admin+ep /usr/bin/gsr-kms-server 2>/dev/null \
            || warn "No se pudo aplicar setcap a gsr-kms-server (la grabación KMS pedirá contraseña)"
    fi

    # --- CLI de Caelestia (python) ---------------------------------------------
    if command -v caelestia >/dev/null && [ -x /usr/local/bin/caelestia ]; then
        log "CLI de caelestia ya instalada — omitiendo"
    else
        log "Instalando la CLI de Caelestia (pip)"
        sudo pip install --break-system-packages \
            "git+${CAELESTIA_CLI_REPO}@${CAELESTIA_CLI_COMMIT}"
    fi
fi

# -----------------------------------------------------------------------------
# 3. Fuentes
# -----------------------------------------------------------------------------
log "Instalando fuentes (Material Symbols, Rubik, CaskaydiaCove Nerd Font)"
mkdir -p "$HOME/.local/share/fonts"
cp -f "$REPO/themes/fonts/"*.ttf "$HOME/.local/share/fonts/"
if ! fc-list | grep -qi "CaskaydiaCove"; then
    tmpzip="$(mktemp --suffix=.zip)"
    if curl -fL "$NERD_FONT_URL" -o "$tmpzip"; then
        unzip -o "$tmpzip" '*.ttf' -d "$HOME/.local/share/fonts/" >/dev/null
        rm -f "$tmpzip"
    else
        warn "No se pudo descargar CaskaydiaCove Nerd Font — instálala a mano"
    fi
fi
fc-cache -f >/dev/null

# -----------------------------------------------------------------------------
# 4. Ficheros de usuario: shell, configs, scripts, temas, fondos, MiniApps
# -----------------------------------------------------------------------------
log "Copiando Caelestia Shell a ~/caelestia-wayfire"
backup "$HOME/caelestia-wayfire"
rsync -a --delete --exclude 'build*' "$REPO/shell/" "$HOME/caelestia-wayfire/"

# El CLI `caelestia` habla con el shell vía `qs -c caelestia`, que busca una
# config LLAMADA "caelestia" en ~/.config/quickshell. Enlazamos el shell ahí y
# caelestia-wayfire-start lo arranca con ese mismo nombre.
mkdir -p "$HOME/.config/quickshell"
ln -sfn "$HOME/caelestia-wayfire" "$HOME/.config/quickshell/caelestia"

log "Instalando scripts en ~/.local/bin"
mkdir -p "$HOME/.local/bin"
for f in "$REPO/bin/"*; do
    install_templated "$f" "$HOME/.local/bin/$(basename "$f")"
    chmod +x "$HOME/.local/bin/$(basename "$f")"
done

log "Instalando configuraciones en ~/.config"
install_templated "$REPO/config/wayfire.ini"                      "$HOME/.config/wayfire.ini"
install_templated "$REPO/config/environment.d/50-local-bin.conf"  "$HOME/.config/environment.d/50-local-bin.conf"
install_templated "$REPO/config/environment.d/60-cursor.conf"     "$HOME/.config/environment.d/60-cursor.conf"
backup "$HOME/.config/caelestia";  mkdir -p "$HOME/.config/caelestia"
rsync -a "$REPO/config/caelestia/" "$HOME/.config/caelestia/"
backup "$HOME/.config/gtk-3.0/settings.ini"; mkdir -p "$HOME/.config/gtk-3.0"
cp -f "$REPO/config/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
backup "$HOME/.config/gtk-3.0/gtk.css"
cp -f "$REPO/config/gtk-3.0/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"
backup "$HOME/.config/gtk-4.0/gtk.css"; mkdir -p "$HOME/.config/gtk-4.0"
cp -f "$REPO/config/gtk-4.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
if [ -f "$REPO/config/mimeapps.list" ]; then
    backup "$HOME/.config/mimeapps.list"
    cp -f "$REPO/config/mimeapps.list" "$HOME/.config/mimeapps.list"
fi
backup "$HOME/.config/xdg-desktop-portal/wayfire-portals.conf"
mkdir -p "$HOME/.config/xdg-desktop-portal"
cp -f "$REPO/config/xdg-desktop-portal/wayfire-portals.conf" "$HOME/.config/xdg-desktop-portal/"
mkdir -p "$HOME/.config/systemd/user/xdg-desktop-portal.service.d"
cp -f "$REPO/config/systemd-user/xdg-desktop-portal.service.d/override.conf" \
      "$HOME/.config/systemd/user/xdg-desktop-portal.service.d/"
systemctl --user daemon-reload 2>/dev/null || true

log "Instalando tema de cursor clay-dark"
mkdir -p "$HOME/.local/share/icons"
rsync -a "$REPO/themes/icons/clay-dark/" "$HOME/.local/share/icons/clay-dark/"

PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Imágenes")"
log "Copiando fondos de pantalla a $PICTURES_DIR/Wallpapers"
mkdir -p "$PICTURES_DIR/Wallpapers"
rsync -a "$REPO/wallpapers/" "$PICTURES_DIR/Wallpapers/"

log "Instalando MiniApps en ~/MiniApps"
backup "$HOME/MiniApps"
rsync -a "$REPO/miniapps/" "$HOME/MiniApps/"

# Estado inicial de Caelestia: esquema de color y fondo actual
log "Sembrando estado inicial de Caelestia (colores + fondo)"
mkdir -p "$HOME/.local/state/caelestia/wallpaper"
[ -f "$HOME/.local/state/caelestia/scheme.json" ] \
    || cp "$REPO/state/caelestia/scheme.json" "$HOME/.local/state/caelestia/scheme.json"
[ -f "$HOME/.local/state/caelestia/wallpaper/path.txt" ] \
    || printf '%s' "$PICTURES_DIR/Wallpapers/lamari.jpg" > "$HOME/.local/state/caelestia/wallpaper/path.txt"

# -----------------------------------------------------------------------------
# 5. Ajustes del sistema (portal XDG) y apariencia (gsettings)
# -----------------------------------------------------------------------------
if [ "$ONLY_DOTFILES" -eq 0 ]; then
    log "Configurando xdg-desktop-portal a nivel de sistema (evita cuelgues de 25 s)"
    sudo cp "$REPO/system/xdg-desktop-portal/wayfire-portals.conf" \
        /usr/share/xdg-desktop-portal/wayfire-portals.conf
fi

# El brillo (brightnessctl) escribe en /sys/class/backlight/*/brightness, que
# solo es escribible por root y el grupo "video". Sin pertenecer a ese grupo,
# Brightness.qml falla en silencio (Quickshell.execDetached no reporta el
# error) y el deslizador de brillo se mueve pero la pantalla no cambia.
NEEDS_RELOGIN_FOR_VIDEO=0
log "Comprobando permisos para el control de brillo (grupo 'video')"
if id -nG "$USER" | grep -qw video; then
    log "El usuario ya pertenece al grupo 'video' — el control de brillo debería funcionar"
else
    warn "El usuario no pertenece al grupo 'video': brightnessctl no podrá escribir el brillo. Añadiéndolo…"
    sudo usermod -aG video "$USER"
    NEEDS_RELOGIN_FOR_VIDEO=1
fi

log "Aplicando apariencia con gsettings (tema, iconos, cursor, fuente)"
if command -v gsettings >/dev/null && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}${XDG_RUNTIME_DIR:-}" ]; then
    gsettings set org.gnome.desktop.interface gtk-theme     'Yaru-wartybrown'  || true
    gsettings set org.gnome.desktop.interface icon-theme    'Yaru-wartybrown'  || true
    gsettings set org.gnome.desktop.interface cursor-theme  'clay-dark'        || true
    gsettings set org.gnome.desktop.interface cursor-size   48                 || true
    gsettings set org.gnome.desktop.interface font-name     'Adwaita Sans 11'  || true
else
    warn "gsettings no disponible — aplica el tema a mano o reejecuta dentro de una sesión gráfica"
fi

# -----------------------------------------------------------------------------
# 6. Comprobaciones finales
# -----------------------------------------------------------------------------
log "Comprobando la instalación"
ok=1
/usr/local/bin/quickshell --version 2>/dev/null || { warn "quickshell no responde"; ok=0; }
command -v wayfire >/dev/null || { warn "wayfire no está instalado"; ok=0; }
[ -f /usr/local/lib/x86_64-linux-gnu/wayfire/libview-shot.so ] || { warn "Falta view-shot (miniaturas de la barra degradarán a icono)"; ok=0; }
command -v caelestia >/dev/null || { warn "CLI caelestia no encontrada"; ok=0; }
[ -d /usr/lib/qt6/qml/Caelestia ] || { warn "Plugin QML Caelestia no instalado"; ok=0; }
[ -x "$HOME/.local/bin/caelestia-wayfire-start" ] || { warn "Falta caelestia-wayfire-start"; ok=0; }

# -----------------------------------------------------------------------------
# 7. Limpieza de archivos de compilación
# -----------------------------------------------------------------------------
if [ -d "$BUILD_DIR" ]; then
    log "Limpiando archivos de compilación temporales ($BUILD_DIR)"
    rm -rf "$BUILD_DIR"
fi

echo
if [ "$ok" -eq 1 ]; then
    printf '\033[1;32m✔ Instalación completada.\033[0m\n'
else
    printf '\033[1;33m⚠ Instalación terminada con avisos (revisa los mensajes anteriores).\033[0m\n'
fi
[ -d "$BACKUP_DIR" ] && echo "Copias de seguridad de tus ficheros previos en: $BACKUP_DIR"
if [ "$NEEDS_RELOGIN_FOR_VIDEO" -eq 1 ]; then
    warn "Se te añadió al grupo 'video' (control de brillo). Es IMPRESCINDIBLE cerrar sesión y volver a entrar para que se aplique."
fi
cat <<'EOF'

Siguientes pasos:
  1. Cierra la sesión.
  2. En la pantalla de GDM, pulsa el engranaje y elige la sesión «Wayfire».
  3. Inicia sesión: Caelestia arrancará automáticamente.

Atajos principales: Super+D lanzador · Super+E dashboard · Super+S barra lateral
                    Super+L bloquear · Ctrl+1..4 workspaces · Super+Enter terminal
EOF
