#!/usr/bin/env python3
"""Genere sourcemap.json (format Rojo) a partir de src/.

La sourcemap permet a luau-lsp de resoudre les require() entre modules et donc
de typer le projet de bout en bout, exactement comme le ferait Rojo.
"""
import json
import os
import sys

ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")

# Classe Roblox de chaque dossier de premier niveau.
SERVICE_CLASSES = {
    "ReplicatedStorage": "ReplicatedStorage",
    "ServerScriptService": "ServerScriptService",
    "ServerStorage": "ServerStorage",
    "StarterPlayer": "StarterPlayer",
    "StarterGui": "StarterGui",
    "StarterPack": "StarterPack",
    "Workspace": "Workspace",
    "Lighting": "Lighting",
}
NESTED_CLASSES = {
    "StarterPlayerScripts": "StarterPlayerScripts",
    "StarterCharacterScripts": "StarterCharacterScripts",
}

SUFFIXES = [
    (".server.luau", "Script"),
    (".client.luau", "LocalScript"),
    (".luau", "ModuleScript"),
]


def classify(filename):
    for suffix, class_name in SUFFIXES:
        if filename.endswith(suffix):
            return filename[: -len(suffix)], class_name
    return None, None


def build_node(path, name, depth):
    entries = sorted(os.listdir(path))
    init_class = None
    init_file = None
    for filename in entries:
        base, class_name = classify(filename)
        if base == "init":
            init_class, init_file = class_name, filename
            break

    if depth == 0:
        class_name = SERVICE_CLASSES.get(name, "Folder")
    elif name in NESTED_CLASSES and init_class is None:
        class_name = NESTED_CLASSES[name]
    else:
        class_name = init_class or "Folder"

    node = {"name": name, "className": class_name}
    if init_file:
        node["filePaths"] = [os.path.relpath(os.path.join(path, init_file), ROOT).replace(os.sep, "/")]

    children = []
    for entry in entries:
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            children.append(build_node(full, entry, depth + 1))
        else:
            base, child_class = classify(entry)
            if not base or base == "init":
                continue
            children.append({
                "name": base,
                "className": child_class,
                "filePaths": [os.path.relpath(full, ROOT).replace(os.sep, "/")],
            })
    if children:
        node["children"] = children
    return node


def main():
    if not os.path.isdir(SRC):
        print("src/ introuvable", file=sys.stderr)
        return 1
    children = [
        build_node(os.path.join(SRC, entry), entry, 0)
        for entry in sorted(os.listdir(SRC))
        if os.path.isdir(os.path.join(SRC, entry))
    ]
    sourcemap = {"name": "WaterWars", "className": "DataModel", "children": children}
    target = os.path.join(ROOT, "sourcemap.json")
    with open(target, "w", encoding="utf-8") as handle:
        json.dump(sourcemap, handle, indent="\t")
        handle.write("\n")
    print("sourcemap.json genere (%d services)" % len(children))
    return 0


if __name__ == "__main__":
    sys.exit(main())
