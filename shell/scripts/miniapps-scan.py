#!/usr/bin/env python3
"""Escanea un árbol de MiniApps (AppDirs estilo ROX) y emite JSON en stdout.

Uso: miniapps-scan.py /ruta/a/MiniApps

Salida: objeto {ruta_relativa: [entradas]} para cada carpeta navegable, donde
"" es la raíz (las categorías). Cada entrada tiene:
  name     nombre visible (nombre de la carpeta, o GenericName/Name del .desktop)
  rel      ruta relativa a la raíz (clave para navegar si es "dir")
  path     ruta absoluta
  type     "app" (AppDir con AppRun), "desktop" (lanzador .desktop)
           o "dir" (carpeta navegable)
  icon     ruta absoluta al icono (.DirIcon o Icon= con ruta), o ""
  iconName nombre de icono de tema (Icon= sin ruta, solo .desktop), o ""
  summary  Summary de AppInfo.xml o Comment del .desktop, localizado, o ""

Las entradas cuyo nombre empieza por punto se omiten (convención ROX de
ocultación). Aparte de directorios solo se listan archivos .desktop.
"""

import json
import locale
import os
import sys
import xml.etree.ElementTree as ET

XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"


def summary_for(appinfo_path, lang):
    """Extrae el Summary de AppInfo.xml en el idioma pedido (fallback: sin lang)."""
    try:
        root = ET.parse(appinfo_path).getroot()
    except (OSError, ET.ParseError):
        return ""
    fallback = ""
    for el in root.iter("Summary"):
        text = " ".join((el.text or "").split())
        el_lang = el.get(XML_LANG)
        if el_lang is None:
            fallback = fallback or text
        elif el_lang == lang:
            return text
    return fallback


def parse_desktop(path, lang_full, lang):
    """Extrae los campos relevantes de la sección [Desktop Entry]."""
    fields = {}
    in_section = False
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line.startswith("["):
                    in_section = line == "[Desktop Entry]"
                    continue
                if not in_section or not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                fields[key.strip()] = value.strip()
    except OSError:
        return None
    if fields.get("Type", "Application") != "Application":
        return None
    if fields.get("Hidden", "").lower() == "true" or fields.get("NoDisplay", "").lower() == "true":
        return None

    def localized(key):
        return fields.get(f"{key}[{lang_full}]") or fields.get(f"{key}[{lang}]") or fields.get(key, "")

    name = localized("GenericName") or localized("Name")
    if not name:
        return None
    icon_value = fields.get("Icon", "")
    return {
        "name": name,
        "type": "desktop",
        "icon": icon_value if icon_value.startswith("/") else "",
        "iconName": "" if icon_value.startswith("/") else icon_value,
        "summary": localized("Comment"),
    }


def sort_key(name):
    try:
        return locale.strxfrm(name.casefold())
    except OSError:
        return name.casefold()


def scan(root_path):
    lang_full = (os.environ.get("LANG") or "en").split(".")[0]  # p.ej. es_ES
    lang = lang_full.split("_")[0]  # p.ej. es
    result = {}
    pending = [""]
    while pending:
        rel = pending.pop()
        abs_dir = os.path.join(root_path, rel) if rel else root_path
        entries = []
        try:
            names = os.listdir(abs_dir)
        except OSError:
            names = []
        for name in names:
            if name.startswith("."):
                continue
            path = os.path.join(abs_dir, name)
            entry_rel = f"{rel}/{name}" if rel else name
            if os.path.isdir(path):
                icon = os.path.join(path, ".DirIcon")
                if not os.path.exists(icon):
                    icon = ""
                if os.path.isfile(os.path.join(path, "AppRun")):
                    entries.append({
                        "name": name,
                        "rel": entry_rel,
                        "path": path,
                        "type": "app",
                        "icon": icon,
                        "iconName": "",
                        "summary": summary_for(os.path.join(path, "AppInfo.xml"), lang),
                    })
                else:
                    entries.append({
                        "name": name,
                        "rel": entry_rel,
                        "path": path,
                        "type": "dir",
                        "icon": icon,
                        "iconName": "",
                        "summary": "",
                    })
                    pending.append(entry_rel)
            elif name.endswith(".desktop") and os.path.isfile(path):
                entry = parse_desktop(path, lang_full, lang)
                if entry:
                    entry["rel"] = entry_rel
                    entry["path"] = path
                    entries.append(entry)
        # Orden alfabético por nombre visible (el de un .desktop
        # no coincide con su nombre de archivo)
        entries.sort(key=lambda e: sort_key(e["name"]))
        result[rel] = entries
    return result


def main():
    if len(sys.argv) != 2 or not os.path.isdir(sys.argv[1]):
        print(f"uso: {sys.argv[0]} /ruta/a/MiniApps", file=sys.stderr)
        return 1
    try:
        locale.setlocale(locale.LC_COLLATE, "")
    except locale.Error:
        pass
    json.dump(scan(sys.argv[1]), sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
