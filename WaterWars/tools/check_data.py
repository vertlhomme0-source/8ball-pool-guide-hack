#!/usr/bin/env python3
"""Verifications de coherence du contenu Water Wars.

1. Execute les modules de donnees (GameConfig / Weapons / Maps) sous le vrai
   moteur Luau avec un stub Roblox, et valide chaque champ.
2. Verifie que tous les require() du projet pointent vers un fichier existant.
3. Verifie que chaque remote utilise cote client existe cote serveur.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
RS = os.path.join(SRC, "ReplicatedStorage", "WaterWars")
LUAU = os.environ.get("LUAU", os.path.join(ROOT, ".tools", "luau"))
STUB = os.path.join(ROOT, "tools", "roblox_stub.luau")

errors = []
notes = []


def fail(msg):
    errors.append(msg)


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def module_chunk(rel_path, name):
    """Transforme un ModuleScript en fonction Luau inline."""
    source = read(os.path.join(RS, rel_path))
    return "local %s = (function()\n%s\nend)()\n" % (name, source)


def run_luau(script_body, extra_modules):
    """Assemble stub + modules + script de test, puis execute luau."""
    parts = [read(STUB), ""]
    parts.extend(extra_modules)
    parts.append(script_body)
    tmp = os.path.join(ROOT, ".tools", "_check_tmp.luau")
    with open(tmp, "w", encoding="utf-8") as handle:
        handle.write("\n".join(parts))
    proc = subprocess.run([LUAU, tmp], capture_output=True, text=True)
    os.remove(tmp)
    return proc


def check_luau_available():
    if not os.path.isfile(LUAU) or not os.access(LUAU, os.X_OK):
        notes.append("luau introuvable (%s) : tests d'execution ignores" % LUAU)
        return False
    return True


# --------------------------------------------------------------------------
# 1. Donnees : armes
# --------------------------------------------------------------------------
WEAPON_NUMERIC = [
    "damage", "fireRate", "burst", "tankSize", "tankCost", "reloadTime",
    "speed", "gravity", "lifetime", "spread", "pellets", "radius",
    "splashRadius", "splashDamage", "slow", "slowTime", "heal",
    "chargeTime", "chargeBonus", "headshot", "walkSpeedMul", "zoom", "price",
]

WEAPON_TEST = """
local expectedCount = 25
local fields = {%s}
local problems = {}
local function report(msg) table.insert(problems, msg) end

if Weapons.Count ~= expectedCount then
	report("Nombre d'armes = " .. tostring(Weapons.Count) .. " (attendu " .. expectedCount .. ")")
end

local seenNames = {}
for _, w in ipairs(Weapons.List) do
	local tag = tostring(w.id)
	if type(w.name) ~= "string" or #w.name == 0 then report(tag .. " : nom manquant") end
	if type(w.desc) ~= "string" or #w.desc < 10 then report(tag .. " : description trop courte") end
	if seenNames[w.name] then report(tag .. " : nom duplique (" .. tostring(w.name) .. ")") end
	seenNames[w.name] = true
	if Weapons.CategoryDefaults[w.category] == nil then report(tag .. " : categorie inconnue") end
	if Weapons.Rarity[w.rarity] == nil then report(tag .. " : rarete inconnue") end
	for _, field in ipairs(fields) do
		local v = w[field]
		if type(v) ~= "number" then
			report(tag .. " : champ '" .. field .. "' absent ou non numerique")
		elseif v < 0 then
			report(tag .. " : champ '" .. field .. "' negatif")
		end
	end
	if w.tankCost <= 0 then report(tag .. " : tankCost doit etre > 0") end
	if w.tankSize < w.tankCost then report(tag .. " : reservoir plus petit qu'un tir") end
	if w.fireRate <= 0 then report(tag .. " : fireRate doit etre > 0") end
	if w.pellets < 1 then report(tag .. " : pellets doit etre >= 1") end
	if w.damage <= 0 then report(tag .. " : damage doit etre > 0") end
	if w.speed <= 0 then report(tag .. " : speed doit etre > 0") end
	if w.lifetime <= 0 then report(tag .. " : lifetime doit etre > 0") end
	if type(w.color) ~= "table" or not w.color.__isColor3 then report(tag .. " : couleur invalide") end
	if type(w.accent) ~= "table" or not w.accent.__isColor3 then report(tag .. " : accent invalide") end
	if type(w.model) ~= "table" or type(w.model.barrel) ~= "number" then report(tag .. " : modele invalide") end
	if w.rarity == "Starter" and w.price ~= 0 then report(tag .. " : arme de depart payante") end
	if w.rarity ~= "Starter" and w.price <= 0 then report(tag .. " : prix nul hors arme de depart") end
	-- une arme ne doit pas pouvoir vider son reservoir en moins d'une demi-seconde
	local shots = w.tankSize / (w.tankCost * w.burst)
	if shots / w.fireRate < 0.5 then report(tag .. " : reservoir vide en moins de 0.5 s") end
end

for _, id in ipairs(Weapons.StarterIds) do
	if not Weapons.Exists(id) then report("StarterIds : arme inconnue " .. tostring(id)) end
end
if not Weapons.Exists(Weapons.DefaultPrimary) then report("DefaultPrimary inconnu") end
if not Weapons.Exists(Weapons.DefaultSecondary) then report("DefaultSecondary inconnu") end

for _, cat in ipairs(Weapons.CategoryOrder) do
	if Weapons.CategoryDefaults[cat] == nil then report("CategoryOrder : categorie inconnue " .. cat) end
	if #Weapons.ByCategory(cat) == 0 then report("Categorie sans arme : " .. cat) end
end

if #problems == 0 then
	print("WEAPONS_OK " .. Weapons.Count)
else
	for _, p in ipairs(problems) do print("WEAPON_ERR " .. p) end
end
""" % (", ".join('"%s"' % f for f in WEAPON_NUMERIC))


def check_weapons():
    proc = run_luau(WEAPON_TEST, [module_chunk("Config/Weapons.luau", "Weapons")])
    if proc.returncode != 0:
        fail("Weapons.luau n'a pas pu etre execute :\n" + (proc.stderr or proc.stdout).strip())
        return
    for line in proc.stdout.splitlines():
        if line.startswith("WEAPON_ERR"):
            fail("armes : " + line[len("WEAPON_ERR "):])
        elif line.startswith("WEAPONS_OK"):
            notes.append("armes : %s armes valides" % line.split()[1])


# --------------------------------------------------------------------------
# 2. Donnees : maps
# --------------------------------------------------------------------------
MAP_TEST = """
local problems = {}
local function report(msg) table.insert(problems, msg) end

if #Maps.List ~= 6 then report("Nombre de maps = " .. tostring(#Maps.List) .. " (attendu 6)") end

local seen = {}
for _, map in ipairs(Maps.List) do
	local tag = tostring(map.id)
	if seen[map.id] then report("id de map duplique : " .. tag) end
	seen[map.id] = true
	if type(map.name) ~= "string" or #map.name == 0 then report(tag .. " : nom manquant") end
	if type(map.description) ~= "string" or #map.description < 10 then report(tag .. " : description trop courte") end
	if type(map.build) ~= "function" then report(tag .. " : fonction build manquante") end
	if type(map.lighting) ~= "table" then report(tag .. " : reglages de lumiere manquants") end
	if type(map.controlPoint) ~= "table" or not map.controlPoint.__isVector3 then
		report(tag .. " : controlPoint invalide")
	end
	if type(map.refillStations) ~= "table" or #map.refillStations < 2 then
		report(tag .. " : il faut au moins 2 stations de recharge")
	end
	if type(map.powerupSpots) ~= "table" or #map.powerupSpots < 2 then
		report(tag .. " : il faut au moins 2 emplacements de bonus")
	end
	local spawns = map.spawns
	if type(spawns) ~= "table" then
		report(tag .. " : table spawns manquante")
	else
		for _, key in ipairs({"Blue", "Red", "FFA"}) do
			local list = spawns[key]
			if type(list) ~= "table" then
				report(tag .. " : spawns." .. key .. " manquant")
			elseif #list < 10 then
				report(tag .. " : spawns." .. key .. " n'a que " .. #list .. " points (10 minimum pour 20 joueurs)")
			else
				for i, pos in ipairs(list) do
					if type(pos) ~= "table" or not pos.__isVector3 then
						report(tag .. " : spawns." .. key .. "[" .. i .. "] n'est pas un Vector3")
					elseif pos.Y < 1 then
						report(tag .. " : spawns." .. key .. "[" .. i .. "] est sous le sol (Y=" .. pos.Y .. ")")
					end
				end
			end
		end
	end
end

if #problems == 0 then
	print("MAPS_OK " .. #Maps.List)
else
	for _, p in ipairs(problems) do print("MAP_ERR " .. p) end
end
"""


def check_maps():
    maps_dir = os.path.join(RS, "Config", "Maps")
    if not os.path.isdir(maps_dir):
        return
    map_files = sorted(f for f in os.listdir(maps_dir) if f.endswith(".luau") and f != "init.luau")
    if not map_files:
        return
    chunks = []
    names = []
    for index, filename in enumerate(map_files):
        var = "Map%d" % index
        names.append((filename, var))
        chunks.append(module_chunk(os.path.join("Config", "Maps", filename), var))
    listing = "local Maps = { List = { %s } }\n" % ", ".join(v for _, v in names)
    proc = run_luau(listing + MAP_TEST, chunks)
    if proc.returncode != 0:
        fail("Les maps n'ont pas pu etre executees :\n" + (proc.stderr or proc.stdout).strip())
        return
    for line in proc.stdout.splitlines():
        if line.startswith("MAP_ERR"):
            fail("maps : " + line[len("MAP_ERR "):])
        elif line.startswith("MAPS_OK"):
            notes.append("maps : %s maps valides" % line.split()[1])



BUILD_TEST = """
local problems = {}
local function report(msg) table.insert(problems, msg) end

for _, map in ipairs(Maps.List) do
	local container = Instance.new("Model")
	local builder = MapBuilder.new(container, 1234)
	local ok, err = pcall(map.build, builder)
	if not ok then
		report(tostring(map.id) .. " : build() a echoue -> " .. tostring(err))
	elseif builder.count < 40 then
		report(tostring(map.id) .. " : seulement " .. builder.count .. " pieces generees (map trop vide)")
	else
		print("BUILD_INFO " .. tostring(map.id) .. " " .. builder.count)
	end
end

if #problems == 0 then
	print("BUILD_OK")
else
	for _, p in ipairs(problems) do print("BUILD_ERR " .. p) end
end
"""


def check_map_builds():
    maps_dir = os.path.join(RS, "Config", "Maps")
    if not os.path.isdir(maps_dir):
        return
    map_files = sorted(f for f in os.listdir(maps_dir) if f.endswith(".luau") and f != "init.luau")
    if not map_files:
        return
    chunks = [module_chunk(os.path.join("Shared", "MapBuilder.luau"), "MapBuilder")]
    names = []
    for index, filename in enumerate(map_files):
        var = "BMap%d" % index
        names.append(var)
        chunks.append(module_chunk(os.path.join("Config", "Maps", filename), var))
    listing = "local Maps = { List = { %s } }\n" % ", ".join(names)
    proc = run_luau(listing + BUILD_TEST, chunks)
    if proc.returncode != 0:
        fail("La construction des maps a echoue :\n" + (proc.stderr or proc.stdout).strip())
        return
    total = 0
    for line in proc.stdout.splitlines():
        if line.startswith("BUILD_ERR"):
            fail("construction : " + line[len("BUILD_ERR "):])
        elif line.startswith("BUILD_INFO"):
            parts = line.split()
            total += int(parts[2])
            notes.append("map %s : %s pieces generees" % (parts[1], parts[2]))
    if total:
        notes.append("total geometrie : %d pieces" % total)


# --------------------------------------------------------------------------
# 3. Requires : chaque chemin doit exister dans l'arborescence
# --------------------------------------------------------------------------
def build_tree():
    """Reconstruit l'arborescence Roblox a partir des dossiers Rojo."""
    tree = {}
    for dirpath, _dirnames, filenames in os.walk(SRC):
        rel = os.path.relpath(dirpath, SRC).replace(os.sep, "/")
        for filename in filenames:
            if not filename.endswith(".luau"):
                continue
            base = filename
            for suffix in (".server.luau", ".client.luau", ".luau"):
                if base.endswith(suffix):
                    base = base[: -len(suffix)]
                    break
            path = rel if base == "init" else (rel + "/" + base)
            tree[path.lstrip("./")] = os.path.join(dirpath, filename)
    return tree


REQUIRE_RE = re.compile(r"require\(([^()]*(?:\([^()]*\)[^()]*)*)\)")


def check_requires(tree):
    known_paths = set(tree.keys())
    for dirpath, _dirnames, filenames in os.walk(SRC):
        for filename in filenames:
            if not filename.endswith(".luau"):
                continue
            full = os.path.join(dirpath, filename)
            source = read(full)
            rel = os.path.relpath(full, SRC).replace(os.sep, "/")
            for match in REQUIRE_RE.finditer(source):
                expr = match.group(1).strip()
                # On ne valide que les chemins statiques script.Parent... / Shared.X
                if "script" not in expr and "Modules" not in expr:
                    continue
                trail = re.findall(r"[.:]([A-Za-z_][A-Za-z0-9_]*)", expr)
                if not trail:
                    continue
                leaf = trail[-1]
                if leaf in ("WaitForChild", "FindFirstChild", "Parent"):
                    leaf = None
                    quoted = re.findall(r'"([^"]+)"', expr)
                    if quoted:
                        leaf = quoted[-1]
                if not leaf:
                    continue
                if not any(p == leaf or p.endswith("/" + leaf) for p in known_paths):
                    fail("%s : require vers un module introuvable ('%s')" % (rel, leaf))


# --------------------------------------------------------------------------
# 4. Remotes : le client ne doit utiliser que des remotes declares
# --------------------------------------------------------------------------
def check_remotes():
    net_path = os.path.join(RS, "Shared", "Net.luau")
    if not os.path.isfile(net_path):
        return
    net_source = read(net_path)
    declared = set(re.findall(r'^\s*(?:Event|Function)\s*\(\s*"([A-Za-z0-9_]+)"', net_source, re.M))
    declared |= set(re.findall(r'^\s*(?:EVENTS|FUNCTIONS)?\s*\{?\s*"([A-Za-z0-9_]+)"\s*,?\s*$', net_source, re.M))
    if not declared:
        return
    used = set()
    for dirpath, _dirnames, filenames in os.walk(SRC):
        for filename in filenames:
            if not filename.endswith(".luau"):
                continue
            full = os.path.join(dirpath, filename)
            if os.path.abspath(full) == os.path.abspath(net_path):
                continue
            for name in re.findall(r'Net[.:](?:Event|Function|Get|Fire\w*|Invoke\w*|On\w*)\s*\(\s*"([A-Za-z0-9_]+)"', read(full)):
                used.add(name)
    for name in sorted(used - declared):
        fail("remote '%s' utilise mais non declare dans Shared/Net.luau" % name)
    unused = sorted(declared - used)
    if unused:
        notes.append("remotes declares mais jamais utilises : %s" % ", ".join(unused))


def main():
    tree = build_tree()
    if check_luau_available():
        if os.path.isfile(os.path.join(RS, "Config", "Weapons.luau")):
            check_weapons()
        check_maps()
        check_map_builds()
    check_requires(tree)
    check_remotes()

    for note in notes:
        print("   - " + note)
    if errors:
        print("")
        for error in errors:
            print("   ERREUR: " + error)
        return 1
    print("   ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
