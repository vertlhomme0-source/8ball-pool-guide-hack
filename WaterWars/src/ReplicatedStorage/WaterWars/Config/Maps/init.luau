--[[
	Maps
	Index des 6 terrains. Pour ajouter une map : creer le module a cote de
	celui-ci puis l'ajouter a la liste ci-dessous. Le reste du jeu (vote,
	rotation, construction) s'adapte automatiquement.
]]

local Maps = {}

Maps.List = {
	require(script.Backyard),
	require(script.SplashBay),
	require(script.AquaPark),
	require(script.Rooftops),
	require(script.SunkenTemple),
	require(script.NeonArena),
}

Maps.ById = {}
for index, map in ipairs(Maps.List) do
	assert(Maps.ById[map.id] == nil, "Identifiant de map duplique : " .. tostring(map.id))
	map.order = index
	Maps.ById[map.id] = map
end

Maps.Count = #Maps.List

function Maps.Get(id)
	return Maps.ById[id]
end

--- Renvoie `count` maps au hasard, en excluant si possible `excludeId`.
function Maps.PickRandom(count, excludeId, rng)
	local pool = {}
	for _, map in ipairs(Maps.List) do
		if map.id ~= excludeId then
			table.insert(pool, map)
		end
	end
	if #pool == 0 then
		pool = table.clone(Maps.List)
	end
	for index = #pool, 2, -1 do
		local swap = rng and rng:NextInteger(1, index) or math.random(1, index)
		pool[index], pool[swap] = pool[swap], pool[index]
	end
	local chosen = {}
	for index = 1, math.min(count, #pool) do
		table.insert(chosen, pool[index])
	end
	return chosen
end

return Maps
