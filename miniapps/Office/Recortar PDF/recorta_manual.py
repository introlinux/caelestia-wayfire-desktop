#!/usr/bin/env python3
"""Recorte manual de PDF al estilo pdf-quench: se ajusta con el ratón un
rectángulo sobre la vista previa de una página y ESE MISMO recorte (en
proporción) se aplica a todas las páginas del documento de una sola vez.

GTK4 nativo (PyGObject): sigue el tema del sistema y usa los cursores
correctos bajo Wayland, sin depender de Qt5 (krop) ni de Tk (aspecto tosco,
cursores heredados de X11).

Uso: recorta_manual.py entrada.pdf salida.pdf
Sale con 0 si el usuario confirma el recorte, 1 si cancela.
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402

Gtk.init()

from pypdf import PdfReader, PdfWriter  # noqa: E402

LANG = os.environ.get("LANG", "")
if LANG.startswith("es"):
    T = dict(
        title="Recortar PDF (manual)",
        info="Arrastre el rectángulo o sus bordes para ajustar el recorte. Se aplicará a las {n} páginas.",
        page="Página {p} de {n}",
        prev="◀ Anterior",
        next="Siguiente ▶",
        crop="Recortar",
        cancel="Cancelar",
        reset="Restablecer",
        dims="Recorte: {w:.0f} × {h:.0f} mm",
    )
elif LANG.startswith("gl"):
    T = dict(
        title="Recortar PDF (manual)",
        info="Arrastre o rectángulo ou os seus bordos para axustar o recorte. Aplicarase ás {n} páxinas.",
        page="Páxina {p} de {n}",
        prev="◀ Anterior",
        next="Seguinte ▶",
        crop="Recortar",
        cancel="Cancelar",
        reset="Restablecer",
        dims="Recorte: {w:.0f} × {h:.0f} mm",
    )
else:
    T = dict(
        title="Crop PDF (manual)",
        info="Drag the rectangle or its edges to adjust the crop. It will be applied to all {n} pages.",
        page="Page {p} of {n}",
        prev="◀ Previous",
        next="Next ▶",
        crop="Crop",
        cancel="Cancel",
        reset="Reset",
        dims="Crop: {w:.0f} × {h:.0f} mm",
    )

HANDLE = 8  # radio en píxeles para detectar borde/esquina bajo el ratón


def tamano_maximo_pantalla():
    """Tamaño (px) para que la vista previa quepa de entrada en la pantalla,
    dejando sitio a la barra de navegación, las etiquetas y los botones. El
    ScrolledWindow sigue actuando de red de seguridad si algo no encaja."""
    display = Gdk.Display.get_default()
    if display is not None and display.get_monitors().get_n_items() > 0:
        geo = display.get_monitors().get_item(0).get_geometry()
        return max(300, min(geo.width - 120, geo.height - 320))
    return 700


def render_page(pdf_path, reader, page, tmpdir, max_px):
    """Renderiza una página a PNG con pdftoppm y devuelve su ruta y ppp usados."""
    for f in Path(tmpdir).glob("pagina*.png"):
        f.unlink()
    mb = reader.pages[page].mediabox
    w_pt, h_pt = float(mb.width), float(mb.height)
    dpi = min(200, max_px * 72 / w_pt, max_px * 72 / h_pt)
    prefix = os.path.join(tmpdir, "pagina")
    subprocess.run(
        ["pdftoppm", "-png", "-r", str(dpi), "-f", str(page + 1), "-l", str(page + 1), pdf_path, prefix],
        check=True, capture_output=True,
    )
    (png,) = Path(tmpdir).glob("pagina*.png")
    return str(png), dpi


CURSORES = {
    "nw": "nwse-resize", "se": "nwse-resize",
    "ne": "nesw-resize", "sw": "nesw-resize",
    "n": "ns-resize", "s": "ns-resize",
    "e": "ew-resize", "w": "ew-resize",
    "move": "move",
}


class Recortador(Gtk.Window):
    def __init__(self, pdf_path):
        super().__init__(title=f"{T['title']} — {os.path.basename(pdf_path)}")
        self.pdf_path = pdf_path
        self.reader = PdfReader(pdf_path)
        self.n_pages = len(self.reader.pages)
        self.page = 0
        self.tmpdir = tempfile.mkdtemp(prefix="recorta_")
        self.accepted = False
        self.loop = GLib.MainLoop()
        self.max_px = tamano_maximo_pantalla()
        # fracción del recorte relativa a la página (izda, abajo, dcha, arriba; 0..1)
        self.frac = (0.03, 0.03, 0.97, 0.97)

        self.set_default_size(-1, -1)
        self.connect("close-request", self._on_close_request)

        raiz = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        raiz.set_margin_top(10); raiz.set_margin_bottom(10)
        raiz.set_margin_start(10); raiz.set_margin_end(10)
        self.set_child(raiz)

        raiz.append(Gtk.Label(label=T["info"].format(n=self.n_pages)))

        nav = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6, halign=Gtk.Align.CENTER)
        self.btn_prev = Gtk.Button(label=T["prev"])
        self.btn_prev.connect("clicked", lambda _b: self.pagina_anterior())
        self.lbl_pagina = Gtk.Label()
        self.btn_next = Gtk.Button(label=T["next"])
        self.btn_next.connect("clicked", lambda _b: self.pagina_siguiente())
        nav.append(self.btn_prev); nav.append(self.lbl_pagina); nav.append(self.btn_next)
        raiz.append(nav)

        self.area = Gtk.DrawingArea()
        self.area.set_draw_func(self._on_draw)
        self.area.set_cursor(Gdk.Cursor.new_from_name("crosshair"))

        drag = Gtk.GestureDrag()
        drag.connect("drag-begin", self._on_drag_begin)
        drag.connect("drag-update", self._on_drag_update)
        drag.connect("drag-end", self._on_drag_end)
        self.area.add_controller(drag)
        self._drag = drag

        motion = Gtk.EventControllerMotion()
        motion.connect("motion", self._on_motion)
        self.area.add_controller(motion)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.set_child(self.area)
        scroll.set_vexpand(True); scroll.set_hexpand(True)
        # que la ventana se ajuste al tamaño de la página (ya limitado a la
        # pantalla); si aun así no cabe, esto sigue permitiendo desplazarse.
        scroll.set_propagate_natural_width(True)
        scroll.set_propagate_natural_height(True)
        raiz.append(scroll)

        self.lbl_dims = Gtk.Label()
        raiz.append(self.lbl_dims)

        botones = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6, halign=Gtk.Align.CENTER)
        btn_reset = Gtk.Button(label=T["reset"])
        btn_reset.connect("clicked", lambda _b: self.restablecer())
        btn_cancel = Gtk.Button(label=T["cancel"])
        btn_cancel.connect("clicked", lambda _b: self.cancelar())
        btn_crop = Gtk.Button(label=T["crop"])
        btn_crop.add_css_class("suggested-action")
        btn_crop.connect("clicked", lambda _b: self.confirmar())
        botones.append(btn_reset); botones.append(btn_cancel); botones.append(btn_crop)
        raiz.append(botones)

        self.pixbuf = None
        self.img_w = self.img_h = 0
        self.rect_px = None
        self.drag_mode = None
        self.drag_origin = None  # rect_px al iniciar el arrastre
        self.drag_start = None   # punto (x, y) donde empezó el arrastre

        self.mostrar_pagina()

    # ---- ejecución (equivalente a mainloop) ------------------------------

    def ejecutar(self):
        self.present()
        self.loop.run()
        return self.accepted

    def _on_close_request(self, _win):
        self.cancelar()
        return False

    # ---- carga y navegación de páginas ------------------------------------

    def mostrar_pagina(self):
        png, dpi = render_page(self.pdf_path, self.reader, self.page, self.tmpdir, self.max_px)
        self.scale = dpi / 72.0
        self.pixbuf = GdkPixbuf.Pixbuf.new_from_file(png)
        self.img_w, self.img_h = self.pixbuf.get_width(), self.pixbuf.get_height()
        self.area.set_content_width(self.img_w)
        self.area.set_content_height(self.img_h)
        self.lbl_pagina.set_label(T["page"].format(p=self.page + 1, n=self.n_pages))
        self.btn_prev.set_sensitive(self.page > 0)
        self.btn_next.set_sensitive(self.page < self.n_pages - 1)
        self.rect_px = self._frac_a_px(self.frac)
        self._actualizar_dims()
        self.area.queue_draw()

    def pagina_anterior(self):
        if self.page > 0:
            self.page -= 1
            self.mostrar_pagina()

    def pagina_siguiente(self):
        if self.page < self.n_pages - 1:
            self.page += 1
            self.mostrar_pagina()

    # ---- conversión entre fracción de página y píxeles de pantalla -------

    def _frac_a_px(self, frac):
        left, bottom, right, top = frac
        x0 = left * self.img_w
        x1 = right * self.img_w
        y0 = (1 - top) * self.img_h
        y1 = (1 - bottom) * self.img_h
        return x0, y0, x1, y1

    def _px_a_frac(self, x0, y0, x1, y1):
        left = x0 / self.img_w
        right = x1 / self.img_w
        top = 1 - (y0 / self.img_h)
        bottom = 1 - (y1 / self.img_h)
        return left, bottom, right, top

    # ---- dibujo (cairo) -----------------------------------------------------

    def _on_draw(self, _area, cr, _w, _h):
        Gdk.cairo_set_source_pixbuf(cr, self.pixbuf, 0, 0)
        cr.paint()
        if not self.rect_px:
            return
        x0, y0, x1, y1 = self.rect_px
        cr.set_source_rgba(0, 0, 0, 0.45)
        for rx0, ry0, rx1, ry1 in (
            (0, 0, self.img_w, y0),
            (0, y1, self.img_w, self.img_h),
            (0, y0, x0, y1),
            (x1, y0, self.img_w, y1),
        ):
            cr.rectangle(rx0, ry0, rx1 - rx0, ry1 - ry0)
            cr.fill()
        cr.set_source_rgb(0.898, 0.224, 0.208)  # #e53935
        cr.set_line_width(2)
        cr.rectangle(x0, y0, x1 - x0, y1 - y0)
        cr.stroke()
        for hx, hy in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)):
            cr.rectangle(hx - 4, hy - 4, 8, 8)
            cr.fill()

    def _actualizar_dims(self):
        x0, y0, x1, y1 = self.rect_px
        w_mm = (x1 - x0) / self.scale * 25.4 / 72
        h_mm = (y1 - y0) / self.scale * 25.4 / 72
        self.lbl_dims.set_label(T["dims"].format(w=w_mm, h=h_mm))

    # ---- interacción con el ratón: crear, mover y redimensionar ----------

    def _cerca(self, a, b):
        return abs(a - b) <= HANDLE

    def _hit_test(self, x, y):
        x0, y0, x1, y1 = self.rect_px
        left, right = self._cerca(x, x0), self._cerca(x, x1)
        top, bottom = self._cerca(y, y0), self._cerca(y, y1)
        dentro_x, dentro_y = x0 - HANDLE <= x <= x1 + HANDLE, y0 - HANDLE <= y <= y1 + HANDLE
        if left and top: return "nw"
        if right and top: return "ne"
        if left and bottom: return "sw"
        if right and bottom: return "se"
        if left and dentro_y: return "w"
        if right and dentro_y: return "e"
        if top and dentro_x: return "n"
        if bottom and dentro_x: return "s"
        if x0 < x < x1 and y0 < y < y1: return "move"
        return None

    def _clamp(self, x, y):
        return max(0.0, min(x, self.img_w)), max(0.0, min(y, self.img_h))

    def _normaliza(self, x0, y0, x1, y1):
        x0, x1 = sorted((max(0.0, min(x0, self.img_w)), max(0.0, min(x1, self.img_w))))
        y0, y1 = sorted((max(0.0, min(y0, self.img_h)), max(0.0, min(y1, self.img_h))))
        return x0, y0, x1, y1

    def _on_motion(self, _ctrl, x, y):
        if self.drag_mode is None:  # no cambiar el cursor a mitad de un arrastre
            modo = self._hit_test(x, y)
            self.area.set_cursor(Gdk.Cursor.new_from_name(CURSORES.get(modo, "crosshair")))

    def _on_drag_begin(self, _gesture, start_x, start_y):
        self.drag_start = (start_x, start_y)  # sin recortar: los offsets se suman a esto
        x, y = self._clamp(start_x, start_y)
        self.drag_mode = self._hit_test(x, y) or "new"
        self.drag_origin = self.rect_px
        if self.drag_mode == "new":
            self.rect_px = (x, y, x, y)
        self.area.queue_draw()

    def _on_drag_update(self, _gesture, offset_x, offset_y):
        sx, sy = self.drag_start
        x, y = self._clamp(sx + offset_x, sy + offset_y)
        x0, y0, x1, y1 = self.drag_origin
        m = self.drag_mode
        if m == "new":
            nx0, ny0 = self._clamp(sx, sy)
            nx1, ny1 = x, y
        elif m == "move":
            w, h = x1 - x0, y1 - y0
            nx0 = min(max(x0 + offset_x, 0), self.img_w - w)
            ny0 = min(max(y0 + offset_y, 0), self.img_h - h)
            nx1, ny1 = nx0 + w, ny0 + h
        else:
            nx0, ny0, nx1, ny1 = x0, y0, x1, y1
            if "w" in m: nx0 = x
            if "e" in m: nx1 = x
            if "n" in m: ny0 = y
            if "s" in m: ny1 = y
        self.rect_px = self._normaliza(nx0, ny0, nx1, ny1)
        self._actualizar_dims()
        self.area.queue_draw()

    def _on_drag_end(self, _gesture, _offset_x, _offset_y):
        x0, y0, x1, y1 = self.rect_px
        if x1 - x0 < 10 or y1 - y0 < 10:
            self.rect_px = self._frac_a_px(self.frac)  # arrastre ínfimo: descartar
        else:
            self.frac = self._px_a_frac(*self.rect_px)
        self.drag_mode = None
        self._actualizar_dims()
        self.area.queue_draw()

    # ---- botones -----------------------------------------------------------

    def restablecer(self):
        self.frac = (0.03, 0.03, 0.97, 0.97)
        self.rect_px = self._frac_a_px(self.frac)
        self._actualizar_dims()
        self.area.queue_draw()

    def cancelar(self):
        self.accepted = False
        self.loop.quit()
        self.destroy()

    def confirmar(self):
        self.accepted = True
        self.loop.quit()
        self.destroy()


def _frac_visual_a_cruda(frac, rotacion):
    """La fracción que el usuario ajusta es la que VE en la vista previa, que
    ya viene rotada según /Rotate (igual que pdftoppm o cualquier lector la
    muestran). mediabox/cropbox, en cambio, se definen siempre en el sistema
    de coordenadas SIN rotar. Sin esta conversión, en páginas con /Rotate el
    recorte queda desplazado 90/180/270° respecto a lo que se seleccionó."""
    left, bottom, right, top = frac
    rotacion = rotacion % 360
    if rotacion == 90:
        return (1 - top, left, 1 - bottom, right)
    if rotacion == 180:
        return (1 - right, 1 - top, 1 - left, 1 - bottom)
    if rotacion == 270:
        return (bottom, 1 - right, top, 1 - left)
    return frac


def aplicar_recorte(pdf_path, out_path, frac):
    """Aplica la misma fracción de recorte (tal como se ve en la vista
    previa) a todas las páginas del documento."""
    reader = PdfReader(pdf_path)
    writer = PdfWriter()
    for pagina in reader.pages:
        left, bottom, right, top = _frac_visual_a_cruda(frac, pagina.rotation)
        mb = pagina.mediabox
        w, h = float(mb.width), float(mb.height)
        x0 = float(mb.left) + left * w
        y0 = float(mb.bottom) + bottom * h
        x1 = float(mb.left) + right * w
        y1 = float(mb.bottom) + top * h
        if x1 > x0 and y1 > y0:
            pagina.mediabox.lower_left = (x0, y0)
            pagina.mediabox.upper_right = (x1, y1)
            pagina.cropbox.lower_left = (x0, y0)
            pagina.cropbox.upper_right = (x1, y1)
        writer.add_page(pagina)
    with open(out_path, "wb") as f:
        writer.write(f)


def main():
    pdf_path, out_path = sys.argv[1:3]
    app = Recortador(pdf_path)
    accepted = app.ejecutar()
    if not accepted:
        sys.exit(1)
    aplicar_recorte(pdf_path, out_path, app.frac)
    sys.exit(0)


if __name__ == "__main__":
    main()
