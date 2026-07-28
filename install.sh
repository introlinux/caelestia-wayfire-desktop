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
WDISPLAYS_REPO="https://github.com/artizirk/wdisplays.git"
WDISPLAYS_TAG="1.1.3"
CAELESTIA_CLI_REPO="https://github.com/caelestia-dots/cli.git"
CAELESTIA_CLI_COMMIT="eddee4dec"
ONEKO_REPO="https://github.com/Abishek-Pechiappan/Oneko-Rust-Arch"
ONEKO_COMMIT="ed7a5312670c1cb9bd7b41647c7a4a6522db19d1"
FLAMESHOT_REPO="https://github.com/flameshot-org/flameshot.git"
FLAMESHOT_TAG="v14.0.0"
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
    # El marcador dnd_dwell en scale.xml distingue un 0.10.1 con nuestro parche
    # de scale (hover focus + drag-and-drop) de uno de stock.
    if /usr/local/bin/wayfire --version 2>/dev/null | grep -q "^0\.10\.1" &&
       grep -q dnd_dwell /usr/local/share/wayfire/metadata/scale.xml 2>/dev/null; then
        log "Wayfire 0.10.1 (parcheado) ya instalado en /usr/local — omitiendo"
    else
        log "Compilando Wayfire $WAYFIRE_TAG"
        rm -rf "$BUILD_DIR/wayfire"
        git clone --depth 1 --branch "$WAYFIRE_TAG" "$WAYFIRE_REPO" "$BUILD_DIR/wayfire"
        log "Aplicando parche de scale (hover focus + drag-and-drop)"
        git -C "$BUILD_DIR/wayfire" apply "$REPO/patches/wayfire-scale-hover-dnd.patch"
        log "Aplicando parche del cursor raíz de Xwayland (aspa en HiDPI)"
        git -C "$BUILD_DIR/wayfire" apply "$REPO/patches/wayfire-xwayland-root-cursor.patch"
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
    # El sello .annotate-grid-patched marca una instalación con el parche de
    # annotate (redimensionado de cuadrícula en caliente; sin él, cambiar
    # vwidth/vheight con la sesión abierta tira el compositor).
    if [ -f /usr/local/lib/x86_64-linux-gnu/wayfire/libview-shot.so ] &&
       [ -f /usr/local/share/wayfire/.annotate-grid-patched ]; then
        log "wayfire-plugins-extra (parcheado) ya instalado — omitiendo"
    else
        log "Compilando wayfire-plugins-extra $WF_PLUGINS_EXTRA_TAG"
        rm -rf "$BUILD_DIR/wayfire-plugins-extra"
        git clone --depth 1 --branch "$WF_PLUGINS_EXTRA_TAG" "$WF_PLUGINS_EXTRA_REPO" \
            "$BUILD_DIR/wayfire-plugins-extra"
        log "Aplicando parche de annotate (cuadrícula redimensionable)"
        git -C "$BUILD_DIR/wayfire-plugins-extra" apply \
            "$REPO/patches/wayfire-plugins-extra-annotate-grid.patch"
        # meson no detecta Boost solo-cabeceras (libboost-dev sin libs compiladas);
        # los headers están en /usr/include, que el compilador ya usa por defecto.
        sed -i "s/boost = dependency('boost')/boost = declare_dependency()/" \
            "$BUILD_DIR/wayfire-plugins-extra/src/extra-animations/meson.build"
        PKG_CONFIG_PATH=/usr/local/lib/x86_64-linux-gnu/pkgconfig meson setup \
            "$BUILD_DIR/wayfire-plugins-extra/build" "$BUILD_DIR/wayfire-plugins-extra" \
            --prefix=/usr/local --buildtype=release
        ninja -C "$BUILD_DIR/wayfire-plugins-extra/build"
        sudo ninja -C "$BUILD_DIR/wayfire-plugins-extra/build" install
        sudo touch /usr/local/share/wayfire/.annotate-grid-patched
    fi

    # --- shift-switcher (animación de raise estilo baraja de cartas, in-repo) --
    log "Compilando wayfire-shift-switcher"
    rm -rf "$BUILD_DIR/wayfire-shift-switcher"
    PKG_CONFIG_PATH=/usr/local/lib/x86_64-linux-gnu/pkgconfig meson setup \
        "$BUILD_DIR/wayfire-shift-switcher" "$REPO/wayfire-shift-switcher" \
        --prefix=/usr/local --buildtype=release
    ninja -C "$BUILD_DIR/wayfire-shift-switcher"
    sudo ninja -C "$BUILD_DIR/wayfire-shift-switcher" install

    # --- showpointer (efectos de atención sobre el puntero, in-repo) ----------
    log "Compilando wayfire-showpointer"
    rm -rf "$BUILD_DIR/wayfire-showpointer"
    PKG_CONFIG_PATH=/usr/local/lib/x86_64-linux-gnu/pkgconfig meson setup \
        "$BUILD_DIR/wayfire-showpointer" "$REPO/wayfire-showpointer" \
        --prefix=/usr/local --buildtype=release
    ninja -C "$BUILD_DIR/wayfire-showpointer"
    sudo ninja -C "$BUILD_DIR/wayfire-showpointer" install

    # --- ninjaslash (animación de cierre estilo corte de espada, in-repo) -----
    log "Compilando wayfire-ninjaslash"
    rm -rf "$BUILD_DIR/wayfire-ninjaslash"
    PKG_CONFIG_PATH=/usr/local/lib/x86_64-linux-gnu/pkgconfig meson setup \
        "$BUILD_DIR/wayfire-ninjaslash" "$REPO/wayfire-ninjaslash" \
        --prefix=/usr/local --buildtype=release
    ninja -C "$BUILD_DIR/wayfire-ninjaslash"
    sudo ninja -C "$BUILD_DIR/wayfire-ninjaslash" install

    # WCM construye el desplegable "Close animation" con los <desc> estaticos
    # de animate.xml (core), asi que un efecto registrado en runtime no sale
    # en la lista aunque funcione. Anadimos la entrada de ninjaslash tras cada
    # (re)instalacion de wayfire, que regenera ese XML. Idempotente.
    sudo python3 - <<'ANIMPATCH'
import re
path = "/usr/local/share/wayfire/metadata/animate.xml"
text = open(path).read()
if "ninjaslash" not in text:
    m = re.search(r'<option name="close_animation".*?(?=\t\t</option>)', text, re.S)
    desc = ('\t\t\t<desc>\n\t\t\t\t<value>ninjaslash</value>\n'
            '\t\t\t\t<_name>Ninja Slash</_name>\n\t\t\t</desc>\n')
    text = text[:m.end()] + desc + text[m.end():]
    open(path, "w").write(text)
ANIMPATCH

    # --- intro (telon negro + apertura cinematica al iniciar sesion, in-repo) -
    log "Compilando wayfire-intro"
    rm -rf "$BUILD_DIR/wayfire-intro"
    PKG_CONFIG_PATH=/usr/local/lib/x86_64-linux-gnu/pkgconfig meson setup \
        "$BUILD_DIR/wayfire-intro" "$REPO/wayfire-intro" \
        --prefix=/usr/local --buildtype=release
    ninja -C "$BUILD_DIR/wayfire-intro"
    sudo ninja -C "$BUILD_DIR/wayfire-intro" install

    # --- gtkdecor (adornos de ventana con aspecto GTK/Adwaita, in-repo) -------
    # Sustituye al plugin `decoration` del core: en plugins= va uno u otro,
    # nunca los dos (ambos decoran el mismo toplevel).
    log "Compilando wayfire-gtkdecor"
    rm -rf "$BUILD_DIR/wayfire-gtkdecor"
    PKG_CONFIG_PATH=/usr/local/lib/x86_64-linux-gnu/pkgconfig meson setup \
        "$BUILD_DIR/wayfire-gtkdecor" "$REPO/wayfire-gtkdecor" \
        --prefix=/usr/local --buildtype=release
    ninja -C "$BUILD_DIR/wayfire-gtkdecor"
    sudo ninja -C "$BUILD_DIR/wayfire-gtkdecor" install

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

    # --- wdisplays (configurador visual de pantallas, parcheado) --------------
    # El wdisplays de Ubuntu (1.1.3) solo pide la versión 1 del protocolo
    # wlr-output-management y no persiste nada: cada Apply se pierde al
    # reiniciar. El parche sube el bind a la versión 2 (eventos make/model/
    # serial_number, ya soportados por el wlroots de /usr/local) y, tras un
    # Apply exitoso, vuelca el layout aplicado a caelestia-save-layout (bin/),
    # que lo persiste en ~/.config/caelestia/output-layouts.json indexado por
    # identidad de panel. caelestia-auto-scale restaura ese layout completo
    # (modo+posición+transform+escala) en cada arranque/hotplug antes de caer
    # a su heurístico de escala por DPI. Se instala solo el binario en
    # ~/.local/bin (tiene prioridad en el PATH sobre /usr/bin/wdisplays);
    # no se toca el paquete de apt ni se hace `ninja install`.
    if strings "$HOME/.local/bin/wdisplays" 2>/dev/null | grep -q "caelestia-save-layout"; then
        log "wdisplays (parcheado) ya instalado — omitiendo"
    else
        log "Compilando wdisplays $WDISPLAYS_TAG"
        rm -rf "$BUILD_DIR/wdisplays"
        git clone --depth 1 --branch "$WDISPLAYS_TAG" "$WDISPLAYS_REPO" "$BUILD_DIR/wdisplays"
        log "Aplicando parche de persistencia de layout"
        git -C "$BUILD_DIR/wdisplays" apply "$REPO/patches/wdisplays-save-layout.patch"
        meson setup "$BUILD_DIR/wdisplays/build" "$BUILD_DIR/wdisplays" \
            --prefix=/usr/local --buildtype=release
        ninja -C "$BUILD_DIR/wdisplays/build"
        install -Dm755 "$BUILD_DIR/wdisplays/build/src/wdisplays" "$HOME/.local/bin/wdisplays"
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

    # --- oneko-rust (gato de escritorio que persigue el cursor) ---------------
    # Port a Wayfire del oneko de Hyprland: el parche sustituye `hyprctl
    # cursorpos` por el método window-rules/get_cursor_position del IPC de
    # Wayfire (requiere el plugin ipc-rules, ya en plugins= de wayfire.ini).
    # Se instala el binario precompilado del repo (x86_64, autónomo: el
    # backend Wayland de smithay es Rust puro y solo enlaza libc) para no
    # arrastrar rustc+cargo como dependencia de compilación.
    log "Instalando oneko-rust (binario precompilado)"
    install -Dm755 "$REPO/prebuilt/oneko-rust" "$HOME/.local/bin/oneko-rust"
    # Para compilarlo desde las fuentes (p. ej. en otra arquitectura),
    # instala rustc y cargo (sudo apt install rustc cargo) y sustituye el
    # install de arriba por:
    #   rm -rf "$BUILD_DIR/oneko-rust"
    #   git clone "$ONEKO_REPO" "$BUILD_DIR/oneko-rust"
    #   git -C "$BUILD_DIR/oneko-rust" checkout "$ONEKO_COMMIT"
    #   git -C "$BUILD_DIR/oneko-rust" apply "$REPO/patches/oneko-rust-wayfire.patch"
    #   cargo build --release --manifest-path "$BUILD_DIR/oneko-rust/Cargo.toml"
    #   install -Dm755 "$BUILD_DIR/oneko-rust/target/release/oneko-rust" \
    #       "$HOME/.local/bin/oneko-rust"

    # --- CLI de Caelestia (python) ---------------------------------------------
    # Se parchea para soportar fondos de vídeo (extensiones, fotograma vía
    # ffmpeg y previews para el selector). El marcador VIDEO_EXTENSIONS
    # distingue una CLI parcheada de una de stock: comprobar solo que el binario
    # existe daría por buena una instalación sin el parche.
    if python3 -c "import caelestia.utils.wallpaper as w; raise SystemExit(0 if hasattr(w, 'VIDEO_EXTENSIONS') else 1)" 2>/dev/null; then
        log "CLI de caelestia (parcheada) ya instalada — omitiendo"
    else
        log "Instalando la CLI de Caelestia (pip, con soporte de fondos animados)"
        rm -rf "$BUILD_DIR/caelestia-cli"
        git clone "$CAELESTIA_CLI_REPO" "$BUILD_DIR/caelestia-cli"
        git -C "$BUILD_DIR/caelestia-cli" checkout "$CAELESTIA_CLI_COMMIT"
        log "Aplicando parche de fondos animados (vídeo + ffmpeg + previews)"
        git -C "$BUILD_DIR/caelestia-cli" apply \
            "$REPO/patches/caelestia-cli-animated-wallpapers.patch"
        sudo pip install --break-system-packages "$BUILD_DIR/caelestia-cli"
    fi

    # --- Flameshot (capturas de pantalla, atajo Impr Pant) ---------------------
    # Ubuntu 26.04 solo empaqueta la 13.3.0; la 14 mejora el soporte de Wayland
    # y el escalado fraccionario, así que se compila desde el tag.
    # USE_WAYLAND_CLIPBOARD=ON copia al portapapeles vía KF6GuiAddons (protocolo
    # de wlroots); sin esa opción la copia solo funciona bajo XWayland. Es lo
    # único que añade dependencias de compilación: libkf6guiaddons-dev y su
    # arrastre, ~0,6 MB (el resto de Qt6 ya lo pide Quickshell).
    # KDSingleApplication va vendorizado en el repo (no es submódulo), así que
    # basta un clon --depth 1 sin --recurse-submodules.
    if /usr/local/bin/flameshot --version 2>/dev/null | grep -q "Flameshot v14"; then
        log "Flameshot 14 ya instalado en /usr/local — omitiendo"
    else
        log "Compilando Flameshot $FLAMESHOT_TAG"
        rm -rf "$BUILD_DIR/flameshot"
        git clone --depth 1 --branch "$FLAMESHOT_TAG" "$FLAMESHOT_REPO" "$BUILD_DIR/flameshot"
        cmake -S "$BUILD_DIR/flameshot" -B "$BUILD_DIR/flameshot/build" -G Ninja \
            -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
            -DUSE_WAYLAND_CLIPBOARD=ON -DDISABLE_UPDATE_CHECKER=ON
        ninja -C "$BUILD_DIR/flameshot/build"
        sudo ninja -C "$BUILD_DIR/flameshot/build" install
        # El árbol de compilación son ~300 MB de objetos que no hacen falta una
        # vez instalado (a diferencia de wayfire, aquí no se itera sobre fuentes).
        rm -rf "$BUILD_DIR/flameshot"
        # /usr/local/bin gana en el PATH, pero el paquete de APT dejaría además su
        # propio .desktop y su servicio de usuario apuntando a /usr/bin/flameshot.
        if dpkg-query -W -f='${Status}' flameshot 2>/dev/null | grep -q 'ok installed'; then
            warn "El paquete flameshot de APT sigue instalado: quítalo con 'sudo apt-get remove flameshot' para no tener dos versiones"
        fi
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
log "Copiando Caelestia Shell a ~/.caelestia/caelestia-wayfire"
mkdir -p "$HOME/.caelestia"
backup "$HOME/.caelestia/caelestia-wayfire"
rsync -a --delete --exclude 'build*' "$REPO/shell/" "$HOME/.caelestia/caelestia-wayfire/"

# El CLI `caelestia` habla con el shell vía `qs -c caelestia`, que busca una
# config LLAMADA "caelestia" en ~/.config/quickshell. Enlazamos el shell ahí y
# caelestia-wayfire-start lo arranca con ese mismo nombre.
mkdir -p "$HOME/.config/quickshell"
ln -sfn "$HOME/.caelestia/caelestia-wayfire" "$HOME/.config/quickshell/caelestia"

log "Instalando scripts en ~/.local/bin"
mkdir -p "$HOME/.local/bin"
for f in "$REPO/bin/"*; do
    install_templated "$f" "$HOME/.local/bin/$(basename "$f")"
    chmod +x "$HOME/.local/bin/$(basename "$f")"
done

# El control de frecuencia de CPU de la barra escribe en sysfs como root. La
# copia de /usr/local/bin (propiedad de root, NO editable por el usuario) es la
# única autorizada en sudoers; el shell la invoca con `sudo -n`. No apuntar
# nunca la regla a ~/.local/bin: sería escalada de privilegios trivial.
log "Instalando caelestia-cpufreq (helper root + regla sudoers)"
sudo install -o root -g root -m 755 "$REPO/bin/caelestia-cpufreq" /usr/local/bin/caelestia-cpufreq
printf '%s ALL=(root) NOPASSWD: /usr/local/bin/caelestia-cpufreq\n' "$USER" \
    | sudo tee /etc/sudoers.d/caelestia-cpufreq >/dev/null
sudo chmod 440 /etc/sudoers.d/caelestia-cpufreq
if ! sudo visudo -cf /etc/sudoers.d/caelestia-cpufreq >/dev/null; then
    sudo rm -f /etc/sudoers.d/caelestia-cpufreq
    warn "Regla sudoers inválida — el control de frecuencia no tendrá permisos"
fi
# Ceba la caché del máximo real del hardware (ver comentario en el helper)
sudo /usr/local/bin/caelestia-cpufreq status >/dev/null

# El OSD de entrada (teclas/gestos para videotutoriales, Super+K) necesita leer
# los eventos de libinput, que requiere root. Mismo esquema que cpufreq: copia
# root en /usr/local/bin + regla NOPASSWD solo para esa copia.
log "Instalando caelestia-input-watch (helper root + regla sudoers)"
sudo install -o root -g root -m 755 "$REPO/bin/caelestia-input-watch" /usr/local/bin/caelestia-input-watch
printf '%s ALL=(root) NOPASSWD: /usr/local/bin/caelestia-input-watch\n' "$USER" \
    | sudo tee /etc/sudoers.d/caelestia-inputosd >/dev/null
sudo chmod 440 /etc/sudoers.d/caelestia-inputosd
if ! sudo visudo -cf /etc/sudoers.d/caelestia-inputosd >/dev/null; then
    sudo rm -f /etc/sudoers.d/caelestia-inputosd
    warn "Regla sudoers inválida — el OSD de entrada no tendrá permisos"
fi

# En las Intel antiguas (gen6/gen7) el uso de GPU no se puede leer por fdinfo:
# el driver no publica contadores por motor, y la única vía es el PMU de i915.
# Sus eventos son de ámbito de CPU, que el kernel deniega con
# perf_event_paranoid >= 1 (Ubuntu trae 4). Bajarlo permite a cualquier proceso
# del equipo leer contadores de rendimiento, así que solo se toca donde sirve
# de algo: si no hay PMU de Intel (equipos NVIDIA/AMD) no se escribe nada.
if compgen -G "/sys/devices/i915*/events/*-busy" >/dev/null 2>&1 ||
   compgen -G "/sys/devices/xe*/events/*-busy" >/dev/null 2>&1; then
    log "Permitiendo la lectura del PMU de la GPU (perf_event_paranoid=0)"
    printf '# Uso de GPU Intel en el dashboard: el PMU de i915 usa eventos de\n# ámbito de CPU, denegados con perf_event_paranoid >= 1.\nkernel.perf_event_paranoid = 0\n' \
        | sudo tee /etc/sysctl.d/99-caelestia-perf.conf >/dev/null
    sudo sysctl -q --system 2>/dev/null || sudo sysctl -q kernel.perf_event_paranoid=0
else
    log "Sin PMU de GPU Intel — no se toca perf_event_paranoid"
fi

# Las apps gráficas lanzadas con sudo (gparted, synaptic...) pierden el tema y
# tamaño del cursor al limpiarse el entorno; conservamos solo esas dos vars.
log "Instalando regla sudoers del cursor (env_keep XCURSOR_*)"
printf 'Defaults env_keep += "XCURSOR_THEME XCURSOR_SIZE"\n' \
    | sudo tee /etc/sudoers.d/caelestia-cursor >/dev/null
sudo chmod 440 /etc/sudoers.d/caelestia-cursor
if ! sudo visudo -cf /etc/sudoers.d/caelestia-cursor >/dev/null; then
    sudo rm -f /etc/sudoers.d/caelestia-cursor
    warn "Regla sudoers del cursor inválida — descartada"
fi

# Las apps que se lanzan con pkexec necesitan dos cosas caras si se dejan
# permanentes: un `xhost +si:localuser:root` para hablar con Xwayland y un
# agente polkit residente (~95 MB de PSS, y se hincha a más de 200 de RSS en
# cuanto dibuja un diálogo). gui-pkexec monta ambas al vuelo y las desmonta al
# salir, así que ninguna está en el [autostart] de wayfire.ini.
#
# Los .desktop se generan a partir de los del sistema en vez de versionar una
# copia: así no se quedan atrás cuando el paquete actualice nombres, iconos o
# traducciones, y solo se crean si la app está instalada.
log "Generando lanzadores .desktop que pasan por gui-pkexec"
mkdir -p "$HOME/.local/share/applications"
# El comando va explícito y no se reutiliza el Exec del sistema: el de synaptic
# apunta a synaptic-pkexec, que haría un pkexec anidado dentro de gui-pkexec.
for entry in "gparted|/usr/sbin/gparted %f" "synaptic|/usr/sbin/synaptic"; do
    app="${entry%%|*}"; cmd="${entry#*|}"
    src="/usr/share/applications/$app.desktop"
    [ -f "$src" ] || continue
    dst="$HOME/.local/share/applications/$app.desktop"
    backup "$dst"
    sed "s|^Exec=.*|Exec=$HOME/.local/bin/gui-pkexec $cmd|" "$src" > "$dst"
done
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

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
# Flameshot: tinta la UI con el `primary` del esquema en vez del morado de
# fábrica. Va templated porque savePath lleva la ruta absoluta de $HOME.
install_templated "$REPO/config/flameshot/flameshot.ini" "$HOME/.config/flameshot/flameshot.ini"
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
python3 -c "import caelestia.utils.wallpaper as w; raise SystemExit(0 if hasattr(w, 'VIDEO_EXTENSIONS') else 1)" 2>/dev/null \
    || { warn "CLI caelestia sin el parche de fondos animados (los vídeos no funcionarán como fondo)"; ok=0; }
[ -x "$HOME/.local/bin/caelestia-window-watch" ] || { warn "Falta caelestia-window-watch (el fondo animado no se auto-pausará)"; ok=0; }
# El uso de GPU es informativo, no rompe nada: se avisa sin tocar $ok.
if [ -x "$HOME/.local/bin/caelestia-gpu-stats" ] &&
   "$HOME/.local/bin/caelestia-gpu-stats" 2>/dev/null | grep -q '"usage": *null'; then
    paranoid=$(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null || echo "?")
    if [ "$paranoid" != "0" ] && [ "$paranoid" != "-1" ]; then
        warn "El dashboard mostrará \"—\" en el uso de GPU: perf_event_paranoid=$paranoid lo impide (hace falta 0)"
    else
        warn "El dashboard mostrará \"—\" en el uso de GPU: este driver no expone la métrica"
    fi
fi
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
