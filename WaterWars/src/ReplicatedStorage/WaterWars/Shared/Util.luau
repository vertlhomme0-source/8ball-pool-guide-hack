--[[
	Util
	Petites fonctions partagees entre le serveur et le client.
]]

local Util = {}

function Util.Clamp(value, minimum, maximum)
	if value < minimum then
		return minimum
	elseif value > maximum then
		return maximum
	end
	return value
end

function Util.Lerp(a, b, alpha)
	return a + (b - a) * alpha
end

--- Formate un nombre de secondes en "M:SS".
function Util.FormatTime(seconds)
	local total = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

--- Formate un entier avec des espaces tous les 3 chiffres (1 234 567).
function Util.FormatNumber(value)
	local text = tostring(math.floor(value))
	local sign = ""
	if string.sub(text, 1, 1) == "-" then
		sign = "-"
		text = string.sub(text, 2)
	end
	local out = ""
	local count = 0
	for index = #text, 1, -1 do
		out = string.sub(text, index, index) .. out
		count = count + 1
		if count % 3 == 0 and index > 1 then
			out = " " .. out
		end
	end
	return sign .. out
end

--- Melange un tableau sur place (Fisher-Yates) et le renvoie.
function Util.Shuffle(list, rng)
	for index = #list, 2, -1 do
		local swap
		if rng then
			swap = rng:NextInteger(1, index)
		else
			swap = math.random(1, index)
		end
		list[index], list[swap] = list[swap], list[index]
	end
	return list
end

--- Renvoie un element au hasard, ou nil si la liste est vide.
function Util.Pick(list, rng)
	if #list == 0 then
		return nil
	end
	if rng then
		return list[rng:NextInteger(1, #list)]
	end
	return list[math.random(1, #list)]
end

--- Applique une dispersion conique (en degres) a une direction unitaire.
function Util.ApplySpread(direction, spreadDegrees, rng)
	if spreadDegrees <= 0 then
		return direction.Unit
	end
	local unit = direction.Unit
	-- Base orthonormee autour de la direction de tir.
	local reference = Vector3.new(0, 1, 0)
	if math.abs(unit:Dot(reference)) > 0.99 then
		reference = Vector3.new(1, 0, 0)
	end
	local right = unit:Cross(reference).Unit
	local up = right:Cross(unit).Unit

	local angle, radius
	if rng then
		angle = rng:NextNumber() * math.pi * 2
		radius = math.sqrt(rng:NextNumber()) * math.rad(spreadDegrees)
	else
		angle = math.random() * math.pi * 2
		radius = math.sqrt(math.random()) * math.rad(spreadDegrees)
	end
	local offset = (right * math.cos(angle) + up * math.sin(angle)) * math.tan(radius)
	return (unit + offset).Unit
end

--- Renvoie le Humanoid et le Model d'une piece touchee, ou nil.
function Util.GetCharacterFromPart(part)
	local current = part
	while current and current ~= workspace do
		if current:IsA("Model") then
			local humanoid = current:FindFirstChildOfClass("Humanoid")
			if humanoid then
				return current, humanoid
			end
		end
		current = current.Parent
	end
	return nil, nil
end

--- Cree une instance et applique un dictionnaire de proprietes.
function Util.Create(className, properties, children)
	local instance = Instance.new(className)
	if properties then
		for key, value in pairs(properties) do
			if key ~= "Parent" then
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = instance
		end
	end
	if properties and properties.Parent then
		instance.Parent = properties.Parent
	end
	return instance
end

--- Detruit une instance apres un delai, sans bloquer l'appelant.
function Util.DestroyAfter(instance, delaySeconds)
	task.delay(delaySeconds, function()
		if instance and instance.Parent then
			instance:Destroy()
		end
	end)
end

--- Somme des valeurs d'un dictionnaire numerique.
function Util.Sum(dictionary)
	local total = 0
	for _, value in pairs(dictionary) do
		total = total + value
	end
	return total
end

--- Copie profonde d'une table de donnees simples.
function Util.DeepCopy(original)
	if type(original) ~= "table" then
		return original
	end
	local copy = {}
	for key, value in pairs(original) do
		copy[key] = Util.DeepCopy(value)
	end
	return copy
end

--- Nombre d'entrees d'un dictionnaire.
function Util.CountKeys(dictionary)
	local count = 0
	for _ in pairs(dictionary) do
		count = count + 1
	end
	return count
end

return Util
