#!/usr/bin/env python3
"""Genere les fichiers importables dans Roblox Studio.

  build/WaterWars.rbxlx  place complete  -> Studio : Fichier > Ouvrir
  build/WaterWars.rbxmx  modele          -> Studio : Insert from File (n'importe ou)

La generation est deleguee a Rojo, l'outil de reference de l'ecosysteme
Roblox : c'est lui qui garantit que le XML produit est exactement celui que
Studio attend. Le script verifie ensuite que chaque script du fichier produit
est bien identique au fichier source.
"""
import os
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
BUILD = os.path.join(ROOT, "build")
ROJO = os.environ.get("ROJO", os.path.join(ROOT, ".tools", "rojo"))

SUFFIXES = [(".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")]


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def collect_sources():
    """Toutes les sources attendues, indexees par nom d'instance."""
    sources = {}
    for dirpath, _dirnames, filenames in os.walk(SRC):
        for filename in filenames:
            base = None
            for suffix, _class_name in SUFFIXES:
                if filename.endswith(suffix):
                    base = filename[: -len(suffix)]
                    break
            if base is None:
                continue
            name = os.path.basename(dirpath) if base == "init" else base
            sources.setdefault(name, []).append(read(os.path.join(dirpath, filename)))
    return sources


def verify(path, sources):
    """Chaque script du fichier produit doit correspondre a un fichier source."""
    root = ET.parse(path).getroot()
    problems = []
    checked = 0
    for item in root.iter("Item"):
        props = item.find("Properties")
        if props is None:
            continue
        source = props.find("string[@name='Source']")
        if source is None:
            source = props.find("ProtectedString[@name='Source']")
        if source is None:
            continue
        name_node = props.find("string[@name='Name']")
        name = name_node.text if name_node is not None else "?"
        text = source.text or ""
        checked += 1
        if name not in sources:
            problems.append("script inconnu dans le fichier produit : " + name)
        elif text not in sources[name]:
            problems.append("source alteree pour : " + name)
    return checked, problems


def build(project, output, label):
    proc = subprocess.run(
        [ROJO, "build", project, "--output", output],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        print(proc.stdout + proc.stderr, file=sys.stderr)
        return False
    print("%-24s %7.1f Ko   (%s)" % (os.path.relpath(output, ROOT), os.path.getsize(output) / 1024, label))
    return True


def main():
    if not (os.access(ROJO, os.X_OK) or shutil.which(ROJO)):
        print(
            "Rojo introuvable (%s).\nLancez : bash tools/setup_tools.sh" % ROJO,
            file=sys.stderr,
        )
        return 1
    os.makedirs(BUILD, exist_ok=True)

    place = os.path.join(BUILD, "WaterWars.rbxlx")
    model = os.path.join(BUILD, "WaterWars.rbxmx")
    if not build(os.path.join(ROOT, "default.project.json"), place, "place complete"):
        return 1
    if not build(os.path.join(ROOT, "model.project.json"), model, "modele auto-installable"):
        return 1

    sources = collect_sources()
    total_problems = []
    for path in (place, model):
        checked, problems = verify(path, sources)
        total_problems.extend(problems)
        if not problems:
            print("  %-22s %d scripts identiques aux fichiers source" % (os.path.basename(path), checked))
    if total_problems:
        for problem in total_problems:
            print("ERREUR: " + problem, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
