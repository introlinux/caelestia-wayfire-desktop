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
QUICKSHELL_REPO="https://git.outfoxxed.me/quickshell/quickshell.git"
QUICKSHELL_TAG="v0.2.1"
LIBCAVA_REPO="https://github.com/LukashonakV/cava.git"
LIBCAVA_TAG="0.10.7"
GSR_REPO="https://repo.dec05eba.com/gpu-screen-recorder"
GSR_COMMIT="e48be50"
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

    # --- Quickshell -----------------------------------------------------------
    if /usr/local/bin/quickshell --version 2>/dev/null | grep -q "0\.2\.1"; then
        log "Quickshell 0.2.1 ya instalado — omitiendo"
    else
        log "Compilando Quickshell $QUICKSHELL_TAG (tardará varios minutos)"
        rm -rf "$BUILD_DIR/quickshell"
        git clone --depth 1 --branch "$QUICKSHELL_TAG" "$QUICKSHELL_REPO" "$BUILD_DIR/quickshell"
        cmake -S "$BUILD_DIR/quickshell" -B "$BUILD_DIR/quickshell/build" -G Ninja \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DCMAKE_INSTALL_PREFIX=/usr/local \
            -DCRASH_REPORTER=OFF \
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

log "Instalando scripts en ~/.local/bin"
mkdir -p "$HOME/.local/bin"
for f in "$REPO/bin/"*; do
    install_templated "$f" "$HOME/.local/bin/$(basename "$f")"
    chmod +x "$HOME/.local/bin/$(basename "$f")"
done

log "Instalando configuraciones en ~/.config"
install_templated "$REPO/config/wayfire.ini"                      "$HOME/.config/wayfire.ini"
install_templated "$REPO/config/environment.d/50-local-bin.conf"  "$HOME/.config/environment.d/50-local-bin.conf"
backup "$HOME/.config/caelestia";  mkdir -p "$HOME/.config/caelestia"
rsync -a "$REPO/config/caelestia/" "$HOME/.config/caelestia/"
backup "$HOME/.config/gtk-3.0/settings.ini"; mkdir -p "$HOME/.config/gtk-3.0"
cp -f "$REPO/config/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
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
command -v caelestia >/dev/null || { warn "CLI caelestia no encontrada"; ok=0; }
[ -d /usr/lib/qt6/qml/Caelestia ] || { warn "Plugin QML Caelestia no instalado"; ok=0; }
[ -x "$HOME/.local/bin/caelestia-wayfire-start" ] || { warn "Falta caelestia-wayfire-start"; ok=0; }

echo
if [ "$ok" -eq 1 ]; then
    printf '\033[1;32m✔ Instalación completada.\033[0m\n'
else
    printf '\033[1;33m⚠ Instalación terminada con avisos (revisa los mensajes anteriores).\033[0m\n'
fi
[ -d "$BACKUP_DIR" ] && echo "Copias de seguridad de tus ficheros previos en: $BACKUP_DIR"
cat <<'EOF'

Siguientes pasos:
  1. Cierra la sesión.
  2. En la pantalla de GDM, pulsa el engranaje y elige la sesión «Wayfire».
  3. Inicia sesión: Caelestia arrancará automáticamente.

Atajos principales: Super+D lanzador · Super+E dashboard · Super+S barra lateral
                    Super+L bloquear · Ctrl+1..4 workspaces · Super+Enter terminal
EOF
