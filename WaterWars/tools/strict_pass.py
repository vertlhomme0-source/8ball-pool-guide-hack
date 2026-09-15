#!/usr/bin/env python3
"""Passe stricte : detecte les noms de proprietes / membres Roblox invalides.

luau-lsp ne verifie les ecritures de proprietes qu'en mode strict. On ne peut
pas passer tout le projet en --!strict sans bruit, donc on recopie l'arbre src/
dans un dossier temporaire en ajoutant l'en-tete strict, on regenere une
sourcemap pour cette copie, et on ne retient que les diagnostics qui sont
toujours de vraies fautes de frappe sur l'API Roblox.
"""
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
WORK = os.path.join(ROOT, ".tools", "strict")
LSP = os.environ.get("LUAU_LSP", os.path.join(ROOT, ".tools", "luau-lsp"))
DEFS = os.path.join(ROOT, "tools", "globalTypes.d.luau")

# Diagnostics conserves : ce sont des erreurs meme dans du code dynamique.
KEEP = [
    re.compile(r"Key '[^']+' not found in class"),
    re.compile(r"Key '[^']+' not found in table 'Enum"),
    re.compile(r"Unknown global"),
    re.compile(r"Unknown require"),
    re.compile(r"is not a valid member of"),
]


def main():
    if not os.access(LSP, os.X_OK):
        print("   (luau-lsp introuvable, passe stricte ignoree)")
        return 0

    shutil.rmtree(WORK, ignore_errors=True)
    files = []
    for dirpath, _dirnames, filenames in os.walk(SRC):
        for filename in sorted(filenames):
            if not filename.endswith(".luau"):
                continue
            source_path = os.path.join(dirpath, filename)
            relative = os.path.relpath(source_path, ROOT)
            target_path = os.path.join(WORK, relative)
            os.makedirs(os.path.dirname(target_path), exist_ok=True)
            with open(source_path, encoding="utf-8") as handle:
                source = handle.read()
            if source.lstrip().startswith("--!"):
                source = "\n".join(source.split("\n")[1:])
            with open(target_path, "w", encoding="utf-8") as handle:
                handle.write("--!strict\n" + source)
            files.append(target_path)

    subprocess.run(
        [sys.executable, os.path.join(ROOT, "tools", "gen_sourcemap.py"), WORK],
        capture_output=True,
        check=True,
    )

    proc = subprocess.run(
        [
            LSP, "analyze",
            "--definitions=" + DEFS,
            "--sourcemap=" + os.path.join(WORK, "sourcemap.json"),
        ] + sorted(files),
        capture_output=True,
        text=True,
        cwd=WORK,
    )

    problems = []
    for line in (proc.stdout + proc.stderr).splitlines():
        if not any(pattern.search(line) for pattern in KEEP):
            continue
        match = re.match(r"^(.*?)\((\d+),(\d+)\):\s*(.*)$", line.strip())
        if not match:
            continue
        path = os.path.abspath(os.path.join(WORK, match.group(1)))
        relative = os.path.relpath(path, WORK) if path.startswith(WORK) else match.group(1)
        # -1 : on a ajoute la ligne --!strict en tete.
        problems.append("%s:%d %s" % (relative, int(match.group(2)) - 1, match.group(4)))

    shutil.rmtree(WORK, ignore_errors=True)
    if problems:
        for problem in problems:
            print("   ERREUR: " + problem)
        return 1
    print("   ok (%d fichiers)" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
