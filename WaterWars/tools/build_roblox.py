#!/usr/bin/env python3
"""Genere les fichiers importables dans Roblox Studio a partir de src/.

  build/WaterWars.rbxlx  place complete  -> Studio : Fichier > Ouvrir
  build/WaterWars.rbxmx  modele          -> Studio : clic droit > Insert from File

Les deux fichiers sont du XML Roblox standard : aucun outil externe n'est
necessaire pour les produire ni pour les ouvrir.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
BUILD = os.path.join(ROOT, "build")

SUFFIXES = [
    (".server.luau", "Script"),
    (".client.luau", "LocalScript"),
    (".luau", "ModuleScript"),
]

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


class Node:
    def __init__(self, name, class_name, source=None):
        self.name = name
        self.class_name = class_name
        self.source = source
        self.children = []


def classify(filename):
    for suffix, class_name in SUFFIXES:
        if filename.endswith(suffix):
            return filename[: -len(suffix)], class_name
    return None, None


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def build_node(path, name, depth):
    entries = sorted(os.listdir(path))
    init_class, init_file = None, None
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

    source = read(os.path.join(path, init_file)) if init_file else None
    node = Node(name, class_name, source)

    for entry in entries:
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            node.children.append(build_node(full, entry, depth + 1))
        else:
            base, child_class = classify(entry)
            if not base or base == "init":
                continue
            node.children.append(Node(base, child_class, read(full)))
    return node


# --------------------------------------------------------------------------
# Ecriture XML
# --------------------------------------------------------------------------
def escape(text):
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def cdata(text):
    """Emet une ou plusieurs sections CDATA, en coupant toute sequence ']]>'."""
    parts = text.split("]]>")
    chunks = []
    for index, part in enumerate(parts):
        if index < len(parts) - 1:
            chunks.append("<![CDATA[" + part + "]]]]><![CDATA[>]]>")
        else:
            chunks.append("<![CDATA[" + part + "]]>")
    return "".join(chunks)


SCRIPT_CLASSES = {"Script", "LocalScript", "ModuleScript"}


def _iter_scripts(nodes):
    for node in nodes:
        if node.source is not None:
            yield node
        for child in _iter_scripts(node.children):
            yield child


class Writer:
    def __init__(self):
        self.lines = []
        self.counter = 0

    def referent(self):
        self.counter += 1
        return "RBX%d" % self.counter

    def write_node(self, node, indent):
        pad = "\t" * indent
        self.lines.append('%s<Item class="%s" referent="%s">' % (pad, node.class_name, self.referent()))
        self.lines.append("%s\t<Properties>" % pad)
        self.lines.append('%s\t\t<string name="Name">%s</string>' % (pad, escape(node.name)))
        if node.class_name in SCRIPT_CLASSES:
            self.lines.append(
                '%s\t\t<ProtectedString name="Source">%s</ProtectedString>' % (pad, cdata(node.source or ""))
            )
            if node.class_name != "ModuleScript":
                self.lines.append('%s\t\t<bool name="Disabled">false</bool>' % pad)
        self.lines.append("%s\t</Properties>" % pad)
        for child in node.children:
            self.write_node(child, indent + 1)
        self.lines.append("%s</Item>" % pad)

    def document(self, roots):
        self.lines = [
            '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
        ]
        for root in roots:
            self.write_node(root, 1)
        self.lines.append("</roblox>")
        return "\n".join(self.lines) + "\n"



def verify(place_path, services):
    """Relit le XML produit et compare chaque Source au fichier d'origine."""
    import xml.etree.ElementTree as ET

    expected = {}

    def walk(node, path):
        full = path + "/" + node.name
        if node.source is not None:
            expected[full] = node.source
        for child in node.children:
            walk(child, full)

    for service in services:
        walk(service, "")

    found = {}

    def collect(item, path):
        props = item.find("Properties")
        name = props.find("string[@name='Name']").text
        full = path + "/" + name
        source = props.find("ProtectedString[@name='Source']")
        if source is not None:
            found[full] = source.text or ""
        for child in item.findall("Item"):
            collect(child, full)

    root = ET.parse(place_path).getroot()
    for item in root.findall("Item"):
        collect(item, "")

    problems = []
    if set(expected) != set(found):
        for missing in sorted(set(expected) - set(found)):
            problems.append("script absent du fichier genere : " + missing)
        for extra in sorted(set(found) - set(expected)):
            problems.append("script inattendu : " + extra)
    for path, source in expected.items():
        if path in found and found[path] != source:
            problems.append("source alteree : " + path)
    return problems


# --------------------------------------------------------------------------
def main():
    if not os.path.isdir(SRC):
        print("src/ introuvable", file=sys.stderr)
        return 1
    os.makedirs(BUILD, exist_ok=True)

    services = [
        build_node(os.path.join(SRC, entry), entry, 0)
        for entry in sorted(os.listdir(SRC))
        if os.path.isdir(os.path.join(SRC, entry))
    ]

    # ---- Place complete ---------------------------------------------------
    place_path = os.path.join(BUILD, "WaterWars.rbxlx")
    with open(place_path, "w", encoding="utf-8") as handle:
        handle.write(Writer().document(services))

    # ---- Modele a inserer dans une experience existante -------------------
    # Un dossier par destination, pour un glisser-deposer sans ambiguite.
    labels = {
        "ReplicatedStorage": "1 - A METTRE DANS ReplicatedStorage",
        "ServerScriptService": "2 - A METTRE DANS ServerScriptService",
        "StarterPlayer": "3 - A METTRE DANS StarterPlayer.StarterPlayerScripts",
    }
    model_roots = []
    for service in services:
        label = labels.get(service.name, "A METTRE DANS " + service.name)
        folder = Node(label, "Folder")
        if service.name == "StarterPlayer":
            # On remonte le contenu de StarterPlayerScripts d'un cran.
            for child in service.children:
                if child.name == "StarterPlayerScripts":
                    folder.children.extend(child.children)
                else:
                    folder.children.append(child)
        else:
            folder.children.extend(service.children)
        if folder.children:
            model_roots.append(folder)

    model_path = os.path.join(BUILD, "WaterWars.rbxmx")
    with open(model_path, "w", encoding="utf-8") as handle:
        handle.write(Writer().document(model_roots))

    problems = verify(place_path, services)
    if problems:
        for problem in problems:
            print("ERREUR: " + problem, file=sys.stderr)
        return 1

    def count(node):
        return 1 + sum(count(child) for child in node.children)

    total = sum(count(service) for service in services)
    print("build/WaterWars.rbxlx  %7.1f Ko  (%d instances)" % (os.path.getsize(place_path) / 1024, total))
    print("build/WaterWars.rbxmx  %7.1f Ko" % (os.path.getsize(model_path) / 1024))
    script_count = sum(1 for _ in _iter_scripts(services))
    print("verification : les %d scripts du XML sont identiques aux fichiers source." % script_count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
