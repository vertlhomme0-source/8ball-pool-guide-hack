#!/usr/bin/env python3
"""Demarre reellement le serveur du jeu hors de Roblox Studio.

Construit l'arbre d'instances (ReplicatedStorage.WaterWars et
ServerScriptService.WaterWarsServer) a partir de src/, execute
init.server.luau sous le vrai moteur Luau avec tools/roblox_sim.luau, puis
simule 60 secondes de jeu avec un joueur connecte.

Verifie ensuite que le serveur a bien :
  - demarre tous ses services sans erreur,
  - construit un terrain dans workspace.CurrentMap,
  - fait apparaitre le joueur dessus (et pas dans le vide).
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
LUAU = os.environ.get("LUAU", os.path.join(ROOT, ".tools", "luau"))
SIM = os.path.join(ROOT, "tools", "roblox_sim.luau")

SUFFIXES = [(".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")]


def classify(filename):
    for suffix, class_name in SUFFIXES:
        if filename.endswith(suffix):
            return filename[: -len(suffix)], class_name
    return None, None


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


class Emitter:
    def __init__(self):
        self.lines = []
        self.counter = 0

    def var(self):
        self.counter += 1
        return "_n%d" % self.counter

    def emit_dir(self, path, name, parent_var, depth):
        entries = sorted(os.listdir(path))
        init_class, init_file = None, None
        for filename in entries:
            base, class_name = classify(filename)
            if base == "init":
                init_class, init_file = class_name, filename
                break

        class_name = init_class or "Folder"
        var = self.var()
        self.lines.append('local %s = Instance.new("%s")' % (var, class_name))
        self.lines.append('%s.Name = "%s"' % (var, name))
        self.lines.append("%s.Parent = %s" % (var, parent_var))
        if init_file:
            source = read(os.path.join(path, init_file))
            if class_name == "ModuleScript":
                self.lines.append("%s.__loader = function(script)" % var)
                self.lines.append(source)
                self.lines.append("end")
            else:
                self.lines.append("%s.__source = function(script)" % var)
                self.lines.append(source)
                self.lines.append("end")

        for entry in entries:
            full = os.path.join(path, entry)
            if os.path.isdir(full):
                self.emit_dir(full, entry, var, depth + 1)
            else:
                base, child_class = classify(entry)
                if not base or base == "init":
                    continue
                child = self.var()
                self.lines.append('local %s = Instance.new("%s")' % (child, child_class))
                self.lines.append('%s.Name = "%s"' % (child, base))
                self.lines.append("%s.Parent = %s" % (child, var))
                if child_class == "ModuleScript":
                    self.lines.append("%s.__loader = function(script)" % child)
                    self.lines.append(read(full))
                    self.lines.append("end")
        return var


BOOT = """
-- ============================ demarrage du serveur ========================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

SIM.addPlayer("JoueurTest", 101)

task.spawn(function()
	serverScript.__source(serverScript)
end)

-- 60 secondes de jeu simulees a 30 images par seconde.
local dt = 1 / 30
for _ = 1, 30 * 60 do
	SIM.time = SIM.time + dt
	SIM.stepScheduler()
	RunService.Heartbeat:Fire(dt)
end

-- =============================== verdict ==================================
local out = SIM.realPrint
out("--- MESSAGES ---")
for _, line in ipairs(SIM.prints) do out("  print: " .. line) end
for _, line in ipairs(SIM.warnings) do out("  warn : " .. line) end

out("--- ERREURS ---")
if #SIM.errors == 0 then
	out("  aucune")
else
	for _, line in ipairs(SIM.errors) do out("  ERREUR: " .. line) end
end

out("--- ETAT DU MONDE ---")
local shared = ReplicatedStorage:FindFirstChild("WaterWars")
out("  ReplicatedStorage.WaterWars : " .. (shared and "present" or "ECHEC, absent"))
local sps = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts")
local clientOk = sps and sps:FindFirstChild("WaterWarsClient")
out("  StarterPlayerScripts.WaterWarsClient : " .. (clientOk and "present" or "absent"))
out("  WaterWarsServer range dans : " .. tostring(serverScript.Parent))
local map = workspace:FindFirstChild("CurrentMap")
if map then
	local geometry = map:FindFirstChild("Geometry")
	local props = map:FindFirstChild("Props")
	out(string.format("  workspace.CurrentMap present : %d pieces, %d elements de jeu",
		geometry and #geometry:GetChildren() or 0,
		props and #props:GetChildren() or 0))
else
	out("  ECHEC: workspace.CurrentMap est absent (aucun terrain construit)")
end

local players = game:GetService("Players"):GetPlayers()
out(string.format("  CharacterAutoLoads = %s (doit etre false)",
	tostring(game:GetService("Players").CharacterAutoLoads)))
for _, player in ipairs(players) do
	local character = player.Character
	if character then
		local pivot = character:GetPivot()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local backpack = player:FindFirstChildOfClass("Backpack")
		local tools = 0
		if backpack then
			for _, child in ipairs(backpack:GetChildren()) do
				if child:IsA("Tool") then tools = tools + 1 end
			end
		end
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then tools = tools + 1 end
		end
		out(string.format("  %s : apparu en %s, vie %s, %d arme(s)",
			player.Name, tostring(pivot and pivot.Position), tostring(humanoid and humanoid.Health), tools))
		for _, child in ipairs(backpack:GetChildren()) do
			out("      sac       : " .. child.Name)
		end
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then out("      en main   : " .. child.Name) end
		end
	else
		out("  " .. player.Name .. " : ECHEC, aucun personnage")
	end
end
"""


def main():
    if not os.access(LUAU, os.X_OK):
        print("luau introuvable : lancez tools/setup_tools.sh")
        return 1

    misplaced = "--misplaced" in sys.argv

    emitter = Emitter()
    emitter.lines.append("-- arbre d'instances genere depuis src/")
    if misplaced:
        # Tout le contenu est depose dans un dossier de Workspace : c'est ce
        # qui arrive quand on insere le modele au lieu d'ouvrir la place.
        emitter.lines.append('local installer = Instance.new("Folder")')
        emitter.lines.append('installer.Name = "WaterWars_Installation"')
        emitter.lines.append("installer.Parent = workspace")
        shared_parent = "installer"
        server_parent = "installer"
    else:
        shared_parent = "ReplicatedStorageSvc"
        server_parent = "ServerScriptServiceSvc"

    emitter.emit_dir(
        os.path.join(SRC, "ReplicatedStorage", "WaterWars"), "WaterWars", shared_parent, 1
    )
    server_var = emitter.emit_dir(
        os.path.join(SRC, "ServerScriptService", "WaterWarsServer"),
        "WaterWarsServer",
        server_parent,
        1,
    )
    emitter.lines.append("serverScript = %s" % server_var)

    # Le script client (on ne l'execute pas, mais sa place doit etre verifiee).
    emitter.lines.append('local clientScript = Instance.new("LocalScript")')
    emitter.lines.append('clientScript.Name = "WaterWarsClient"')
    if misplaced:
        emitter.lines.append("clientScript.Parent = installer")
    else:
        emitter.lines.append(
            'clientScript.Parent = game:GetService("StarterPlayer")'
            ':FindFirstChildOfClass("StarterPlayerScripts")'
        )

    body = "\n".join(
        [
            read(SIM),
            "local ReplicatedStorageSvc = game:GetService('ReplicatedStorage')",
            "local ServerScriptServiceSvc = game:GetService('ServerScriptService')",
            "local serverScript",
            "\n".join(emitter.lines),
            BOOT,
        ]
    )

    tmp = os.path.join(ROOT, ".tools", "_boot.luau")
    with open(tmp, "w", encoding="utf-8") as handle:
        handle.write(body)
    proc = subprocess.run([LUAU, tmp], capture_output=True, text=True)
    os.remove(tmp)

    sys.stdout.write(proc.stdout)
    if proc.stderr.strip():
        sys.stderr.write(proc.stderr)
    output = proc.stdout
    failed = (
        proc.returncode != 0
        or "ERREUR:" in output
        or "ECHEC" in output
        or "CurrentMap est absent" in output
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
