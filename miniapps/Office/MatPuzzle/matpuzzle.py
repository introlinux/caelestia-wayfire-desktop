#!/usr/bin/env python3
"""Genera la ficha MatPuzzle en PDF (A4 apaisado).

Izquierda: tablero con el RESULTADO de cada operación en su celda.
Derecha: piezas de la imagen DESORDENADAS, cada una con su operación.
El alumno resuelve la operación de cada pieza, busca la celda con ese
resultado y pega la pieza ahí: si acierta, la imagen se recompone.

Uso: matpuzzle.py piezas_dir COLS FILAS "op1 op2 ..." TRUE|FALSE salida.pdf avisos.txt
     (piezas_dir contiene 0.png .. N-1.png en orden de lectura)
"""

import base64
import random
import re
import subprocess
import sys
from fractions import Fraction
from pathlib import Path

SUPER = {"⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
         "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9"}


def normaliza(op):
    """Pasa la notación escolar (x, ·, :, ², coma decimal) a expresión Python."""
    out = []
    prev_super = False
    for c in op:
        if c in SUPER:
            out.append(("" if prev_super else "^") + SUPER[c])
            prev_super = True
            continue
        prev_super = False
        if c in "xX·*":
            out.append("*")
        elif c == ":":
            out.append("/")
        elif c == ",":
            out.append(".")
        else:
            out.append(c)
    expr = "".join(out)
    if not re.fullmatch(r"[0-9.+\-*/()^]+", expr):
        raise ValueError(op)
    expr = expr.replace("^", "**")
    # los números se evalúan como fracciones exactas
    expr = re.sub(r"(\d+\.?\d*|\.\d+)", r'F("\1")', expr)
    return expr


def evalua(op):
    return eval(normaliza(op), {"__builtins__": None}, {"F": Fraction})


def formatea(valor, decimales):
    """Sin decimales: parte entera (como bc). Con decimales: hasta 2, con coma."""
    if valor.denominator == 1:
        return str(valor.numerator)
    if not decimales:
        return str(int(valor))  # trunca hacia cero
    txt = f"{float(valor):.2f}".rstrip("0").rstrip(".")
    return txt.replace(".", ",")


def main():
    piezas_dir, cols, filas, ops_txt, dec_txt, salida, avisos_path = sys.argv[1:8]
    cols, filas = int(cols), int(filas)
    decimales = dec_txt == "TRUE"
    ops = ops_txt.split()
    n = cols * filas
    if len(ops) != n:
        print(f"NUMOPS {len(ops)} {n}")
        sys.exit(2)

    try:
        resultados = [formatea(evalua(op), decimales) for op in ops]
    except (ValueError, ZeroDivisionError, SyntaxError) as e:
        print(f"BADOP {e}")
        sys.exit(3)

    # Aviso de resultados repetidos (harían ambiguo el puzzle)
    avisos = []
    for r in sorted(set(resultados)):
        iguales = [ops[i] for i in range(n) if resultados[i] == r]
        if len(iguales) > 1:
            avisos.append(f"= {r}:  " + "   ".join(iguales))
    Path(avisos_path).write_text("\n".join(avisos), encoding="utf-8")

    # ── SVG A4 apaisado ──────────────────────────────────────────────────
    W, H = 1052, 744
    margen, cab = 30, 90
    mitad = W // 2
    celda = min((mitad - 2 * margen) / cols, (H - cab - margen - 20 * filas) / filas)
    etiqueta = 20  # alto reservado bajo cada pieza para la operación

    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="297mm" height="210mm" '
           f'viewBox="0 0 {W} {H}" font-family="sans-serif">']
    svg.append(f'<text x="{margen}" y="40" font-size="22" font-weight="bold">MatPuzzle</text>')
    svg.append(f'<text x="{margen}" y="68" font-size="14">Nombre: ________________________'
               f'____________   Fecha: ____________</text>')

    # Tablero (izquierda): celdas con el resultado
    bx, by = margen, cab
    for i in range(n):
        c, f = i % cols, i // cols
        x, y = bx + c * celda, by + f * celda
        svg.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{celda:.1f}" height="{celda:.1f}" '
                   f'fill="none" stroke="#333" stroke-width="1.2"/>')
        svg.append(f'<text x="{x + celda / 2:.1f}" y="{y + celda / 2:.1f}" font-size="{celda / 3.2:.0f}" '
                   f'fill="#888" text-anchor="middle" dominant-baseline="central">{resultados[i]}</text>')

    # Piezas (derecha) en orden aleatorio, con su operación debajo
    orden = list(range(n))
    while True:
        random.shuffle(orden)
        if n == 1 or orden != list(range(n)):
            break
    px, py = mitad + margen, cab
    paso_y = celda + etiqueta
    for pos, i in enumerate(orden):
        c, f = pos % cols, pos // cols
        x, y = px + c * celda, py + f * paso_y
        datos = base64.b64encode(Path(piezas_dir, f"{i}.png").read_bytes()).decode()
        svg.append(f'<image x="{x:.1f}" y="{y:.1f}" width="{celda:.1f}" height="{celda:.1f}" '
                   f'href="data:image/png;base64,{datos}"/>')
        svg.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{celda:.1f}" height="{celda + etiqueta:.1f}" '
                   f'fill="none" stroke="#999" stroke-width="0.8" stroke-dasharray="4,3"/>')
        op = ops[i].replace("&", "&amp;").replace("<", "&lt;")
        svg.append(f'<text x="{x + celda / 2:.1f}" y="{y + celda + etiqueta - 6:.1f}" font-size="13" '
                   f'text-anchor="middle">{op}</text>')

    svg.append("</svg>")
    tmp_svg = Path(piezas_dir, "ficha.svg")
    tmp_svg.write_text("\n".join(svg), encoding="utf-8")
    subprocess.run(["rsvg-convert", "-f", "pdf", "-o", salida, str(tmp_svg)], check=True)


if __name__ == "__main__":
    main()
