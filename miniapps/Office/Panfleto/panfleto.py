#!/usr/bin/env python3
"""Imposición de folleto: reordena las páginas de un PDF y las monta de dos en
dos en hojas apaisadas, de modo que al imprimir a doble cara (voltear por el
borde corto) y doblar por la mitad quede un cuadernillo.

Uso: panfleto.py entrada.pdf salida.pdf
"""

import sys

from pypdf import PdfReader, PdfWriter, PageObject, Transformation


def orden_folleto(n):
    """Secuencia de pares (izquierda, derecha) por cara, para n múltiplo de 4."""
    pares = []
    for i in range(n // 2):
        if i % 2 == 0:
            pares.append((n - 1 - i, i))
        else:
            pares.append((i, n - 1 - i))
    return pares


def main():
    entrada, salida = sys.argv[1], sys.argv[2]
    lector = PdfReader(entrada)
    paginas = list(lector.pages)

    ancho = float(paginas[0].mediabox.width)
    alto = float(paginas[0].mediabox.height)

    # Rellenar con páginas en blanco hasta múltiplo de 4.
    while len(paginas) % 4:
        paginas.append(None)

    escritor = PdfWriter()
    for izq, der in orden_folleto(len(paginas)):
        hoja = PageObject.create_blank_page(width=2 * ancho, height=alto)
        if paginas[izq] is not None:
            hoja.merge_transformed_page(paginas[izq], Transformation())
        if paginas[der] is not None:
            hoja.merge_transformed_page(paginas[der], Transformation().translate(tx=ancho, ty=0))
        escritor.add_page(hoja)

    with open(salida, "wb") as f:
        escritor.write(f)


if __name__ == "__main__":
    main()
