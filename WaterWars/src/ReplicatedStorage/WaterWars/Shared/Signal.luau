--[[
	Signal
	Mini implementation d'evenement, plus legere qu'un BindableEvent et qui
	conserve les references d'instances (un BindableEvent serialise ses
	arguments, ce qui casserait le passage d'objets Player).
]]

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if self._disconnected then
		return
	end
	self._disconnected = true
	local handlers = self._signal._handlers
	local index = table.find(handlers, self)
	if index then
		table.remove(handlers, index)
	end
end

function Signal.new(name)
	return setmetatable({ _handlers = {}, _name = name or "Signal" }, Signal)
end

function Signal:Connect(callback)
	assert(type(callback) == "function", "Signal:Connect attend une fonction")
	local connection = setmetatable({ _signal = self, _callback = callback, _disconnected = false }, Connection)
	table.insert(self._handlers, connection)
	return connection
end

function Signal:Fire(...)
	-- Copie : un handler peut se deconnecter pendant l'iteration.
	local snapshot = table.clone(self._handlers)
	for _, connection in ipairs(snapshot) do
		if not connection._disconnected then
			local ok, err = pcall(connection._callback, ...)
			if not ok then
				warn(string.format("[WaterWars] Erreur dans un handler de %s : %s", self._name, tostring(err)))
			end
		end
	end
end

function Signal:DisconnectAll()
	for _, connection in ipairs(table.clone(self._handlers)) do
		connection:Disconnect()
	end
end

return Signal
