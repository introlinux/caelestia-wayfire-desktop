#!/usr/bin/env python3
"""Recorta los márgenes en blanco de un PDF.

Recibe las cajas de contenido calculadas por Ghostscript (-sDEVICE=bbox) y
ajusta la caja de cada página a su contenido más el margen pedido.

Uso: recorta.py entrada.pdf salida.pdf margen_pt bboxes.txt
"""

import re
import sys

from pypdf import PdfReader, PdfWriter


def main():
    entrada, salida, margen, bbox_path = sys.argv[1:5]
    margen = float(margen)

    cajas = []
    with open(bbox_path) as f:
        for linea in f:
            m = re.match(r"%%HiResBoundingBox:\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)", linea)
            if m:
                cajas.append(tuple(float(v) for v in m.groups()))

    lector = PdfReader(entrada)
    escritor = PdfWriter()
    for i, pagina in enumerate(lector.pages):
        if i < len(cajas):
            x0, y0, x1, y1 = cajas[i]
            mb = pagina.mediabox
            # margen alrededor del contenido, sin salirse de la página
            x0 = max(float(mb.left), x0 - margen)
            y0 = max(float(mb.bottom), y0 - margen)
            x1 = min(float(mb.right), x1 + margen)
            y1 = min(float(mb.top), y1 + margen)
            if x1 > x0 and y1 > y0:
                pagina.mediabox.lower_left = (x0, y0)
                pagina.mediabox.upper_right = (x1, y1)
                pagina.cropbox.lower_left = (x0, y0)
                pagina.cropbox.upper_right = (x1, y1)
        escritor.add_page(pagina)

    with open(salida, "wb") as f:
        escritor.write(f)


if __name__ == "__main__":
    main()
