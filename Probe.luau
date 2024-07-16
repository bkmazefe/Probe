--[[
	https://github.com/bkmazefe/Probe/tree/main
]]
--[=[
	RemoteEvent, RemoteFunction and UnreliableRemoteEvent handler for Roblox.

	@class Probe
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Promise = require(ReplicatedStorage.Packages.Promise)
local IsServer = RunService:IsServer()

--[=[
	@within Probe
	@interface Probe
	.Fire (self: Probe, event_name: string, player_or_arg1: Player | any, ...any) -> ()
	.FireAll (self: Probe, event_name: string, ...any) -> ()
	.Invoke (self: Probe, event_name: string, player_or_arg1: Player | any, ...any) -> any
	.OnEvent (self: Probe, event_name: string, callback: (...any) -> ()) -> ()
	.OnInvoke (self: Probe, event_name: string, callback: (...any) -> any) -> ()
	.NewSettings (settings: Settings) -> Settings
	.getSettings (self: Probe) -> Settings
	.setSettings (self: Probe, settings: Settings) -> ()
	.resetSettings (self: Probe) -> ()
	.withSettings (self: Probe, settings: Settings) -> ShortProbe
	URE ShortProbe
]=]
export type Probe = {
	NewSettings: (settings: Settings) -> Settings,
	OnEvent: (self: Probe, event_name: string, callback: (...any) -> ()) -> (),
	OnInvoke: (self: Probe, event_name: string, callback: (...any) -> any) -> (),
	Fire: (self: Probe, event_name: string, player_or_arg1: Player | any, ...any) -> (),
	FireAll: (self: Probe, event_name: string, ...any) -> (),
	Invoke: (self: Probe, event_name: string, player_or_arg1: Player | any, ...any) -> any,
	getSettings: (self: Probe) -> Settings,
	setSettings: (self: Probe, settings: Settings) -> (),
	resetSettings: (self: Probe) -> (),
	withSettings: (self: Probe, settings: Settings) -> ShortProbe,
	URE: ShortProbe,
}

--[=[
	@within Probe
	@interface Settings
	.Type "URE" | "RE"
]=]
export type Settings = {
	Type: "URE" | "RE",
}

type ProbeInternal = Probe & any

type ProbeFire = (self: ShortProbe | any, event_name: string, player_or_arg1: Player | any, ...any) -> ()
type ProbeFireAll = (self: ShortProbe | any, event_name: string, ...any) -> ()

--[=[
	@within Probe
	@interface ShortProbe
	.Fire (self: ShortProbe, event_name: string, player_or_arg1: Player | any, ...any) -> ()
	.FireAll (self: ShortProbe, event_name: string, ...any) -> ()
]=]
type ShortProbe = {
	Fire: ProbeFire,
	FireAll: ProbeFireAll,
}

local isSetup = false

local SETTINGS = {
	DoUntilOutOfScope = 50,
}

local ProbeProxy = newproxy(true)
local Probe = getmetatable(ProbeProxy)
Probe._Probes = {
	event = nil,
	func = nil,
	ure = nil,
}
Probe.Bindings = {}
Probe.settings = {
	Type = "RE",
}
Probe.__newindex = function()
	error("Can't modify the Probe object")
end

local function variadic(...)
	return ...
end

local function OverrideSettings(selfSettings, settings)
	for name, v in selfSettings do
		if settings[name] == nil then
			settings[name] = v
		end
	end
	return settings
end

--[=[
	Called on Client, connects to the remote events and functions.
	This method is called from the ._setup method
	@within Probe
	@method _client
	@return nil
	@private
]=]
function Probe._client(self: ProbeInternal)
	-- remoteevent
	self._Probes.event.OnClientEvent:Connect(function(event_name: string, args: { any })
		for i = 1, SETTINGS.DoUntilOutOfScope do
			if self.Bindings[event_name] ~= nil then
				for _, callback in self.Bindings[event_name] do
					Promise.new(function(resolve, reject)
						callback(table.unpack(args))
						resolve()
					end):catch(function(err)
						warn(err)
					end)
				end

				break
			end

			task.wait()
		end

		if not self.Bindings[event_name] then
			warn("{" .. script.Name .. "}: " .. event_name .. " has no listeners on client")
		end
	end)
	self._Probes.ure.OnClientEvent:Connect(function(event_name: string, args: { any })
		for i = 1, SETTINGS.DoUntilOutOfScope do
			if self.Bindings[event_name] ~= nil then
				for _, callback in self.Bindings[event_name] do
					Promise.new(function(resolve, reject)
						callback(table.unpack(args))
						resolve()
					end):catch(function(err)
						warn(err)
					end)
				end

				break
			end

			if time() < 10 then
				task.wait(0.1)
			else
				task.wait()
			end
		end

		if not self.Bindings[event_name] then
			warn("{" .. script.Name .. "}: " .. event_name .. " has no listeners on client")
		end
	end)
	self._Probes.func.OnClientInvoke = function(event_name: string, ...: any)
		for i = 1, SETTINGS.DoUntilOutOfScope do
			local callback = self.Bindings["_" .. event_name][1]
			if callback ~= nil then
				return callback(...)
			end

			task.wait()
		end
		error("No listeners has been found for [" .. event_name .. "]")
	end
end

--[=[
	Called on Server, connects to the remote events and functions.
	This method is called from the ._setup method
	@within Probe
	@method _server
	@return nil
	@private
]=]
function Probe._server(self: ProbeInternal)
	self._Probes.event.OnServerEvent:Connect(function(player: Player, event_name: string, args: { any })
		if self.Bindings[event_name] ~= nil then
			for _, callback in self.Bindings[event_name] do
				Promise.new(function(resolve, reject)
					callback(player, table.unpack(args))
					resolve()
				end):catch(function(err)
					warn(err)
				end)
			end
		else
			warn("{" .. script.Name .. "}: " .. event_name .. " has no listeners on server")
		end
	end)
	self._Probes.func.OnServerInvoke = function(player: Player, event_name: string, args: { any })
		local callback = self.Bindings["_" .. event_name][1]
		if callback ~= nil then
			return callback(player, table.unpack(args))
		else
			error("No listeners has been found for [" .. event_name .. "]")
		end
	end
end

--[=[
	Initializes the Probe object and creates the remote event and function objects.
	This method is automatically called when the probe object is required by a script.
	Gets called only once on both server and client.
	@within Probe
	@method _setup
	@return Promise
	@private
]=]
function Probe._setup(self: ProbeInternal): any | unknown
	return Promise.new(function(resolve, reject)
		if IsServer == true then
			self._Probes.event = Instance.new("RemoteEvent")
			self._Probes.event.Parent = script
			self._Probes.func = Instance.new("RemoteFunction")
			self._Probes.func.Parent = script
			self._Probes.ure = Instance.new("UnreliableRemoteEvent")
			self._Probes.ure.Parent = script
			self:_server()
			resolve()
		else
			for i = 1, SETTINGS.DoUntilOutOfScope do
				self._Probes.event = script:FindFirstChild("RemoteEvent")
				self._Probes.func = script:FindFirstChild("RemoteFunction")
				self._Probes.ure = script:FindFirstChild("UnreliableRemoteEvent")

				if self._Probes.event and self._Probes.func and self._Probes.ure then
					self:_client()
					resolve()
					break
				end
				task.wait()
			end

			reject("Promise has fallen out of scope")
		end
	end):catch(function(err)
		warn(err)
	end)
end

--[=[
	Connect to a remote event.
	@within Probe
	@method OnEvent
	@param event_name string
	@param callback (...any) -> ()
	@return nil
]=]
function Probe.OnEvent(self: ProbeInternal, event_name: string, callback: (...any) -> ())
	if self.Bindings[event_name] == nil then
		self.Bindings[event_name] = {}
	end
	table.insert(self.Bindings[event_name], callback)
end

--[=[
	Connect to a remote function.
	@within Probe
	@method OnInvoke
	@param event_name string
	@param callback (...any) -> any
	@return nil
	@error "Can't assign more than one functions for each invokeable event. [event_name]: " .. event_name	
]=]
function Probe.OnInvoke(self: ProbeInternal, event_name: string, callback: (...any) -> any): never?
	if self.Bindings["_" .. event_name] == nil then
		error("Can't assign more than one functions for each invokeable event. [event_name]: " .. event_name)
	end
	self.Bindings["_" .. event_name] = { callback }
	return
end

--[=[
	Fires a remote or unreliable remote event.
	@within Probe
	@method Fire
	@param event_name string
	@param player_or_arg1 Player | any
	@param ... any
	@return nil
]=]
function Probe.Fire(self: ProbeInternal, event_name: string, player_or_arg1: Player | any, ...: any)
	if IsServer == true then
		if self.settings.Type == "URE" then
			self._Probes.ure:FireClient(player_or_arg1, event_name, table.pack(...))
		else
			self._Probes.event:FireClient(player_or_arg1, event_name, table.pack(...))
		end
	else
		if self.settings.Type == "URE" then
			self._Probes.ure:FireServer(event_name, table.pack(variadic(player_or_arg1, ...)))
		else
			self._Probes.event:FireServer(event_name, table.pack(variadic(player_or_arg1, ...)))
		end
	end
end

--[=[
	Fires a remote or unreliable remote event to all clients.
	@within Probe
	@method FireAll
	@param event_name string
	@param ... any
	@return nil
	@error "Can't run :FireAll on Client"
]=]
function Probe.FireAll(self: ProbeInternal, event_name: string, ...: any): never?
	assert(IsServer, "Can't run :FireAll on Client")
	local setType = self.settings.Type
	if setType == "URE" then
		self._Probes.ure:FireAllClients(event_name, table.pack(...))
	else
		self._Probes.event:FireAllClients(event_name, table.pack(...))
	end
	setType = nil
	return
end

--[=[
	Invokes a remote function.
	@within Probe
	@method Invoke
	@param event_name string
	@param player_or_arg1 Player | any
	@param ... any
	@return any
]=]
function Probe.Invoke(self: ProbeInternal, event_name: string, player_or_arg1: Player | any, ...: any): any
	if IsServer == true then
		return self._Probes.func:InvokeClient(player_or_arg1, event_name, table.pack(...))
	else
		return self._Probes.func:InvokeServer(event_name, table.pack(variadic(player_or_arg1, ...)))
	end
end

--[=[
	Sets a new set of settings to the default settings.
	@within Probe
	@method setSettings
	@param settings Settings
	@return nil
]=]
function Probe.setSettings(self: ProbeInternal, settings: Settings)
	if self.settings.Type ~= settings.Type then
		self.settings.Type = settings.Type
	end
end

--[=[
	Returns the current settings.
	@within Probe
	@method getSettings
	@return Settings
]=]
function Probe.getSettings(self: ProbeInternal): Settings
	return self.settings
end

--[=[
	Resets the settings to the default settings.
	@within Probe
	@method resetSettings
	@return nil
]=]
function Probe.ResetSettings(self: ProbeInternal)
	self.settings = {
		Type = "RE",
	}
end

--[=[
	Creates a new set of settings.
	@within Probe
	@param settings Settings
	@return Settings
]=]
function Probe.NewSettings(settings: Settings): Settings
	return {
		Type = settings.Type or "RE",
	}
end

--[=[
	Creates a new proxy Probe object with the given settings.
	@within Probe
	@method withSettings
	@param settings Settings
	@return ShortProbe
	@error "Settings must be a table"
]=]
function Probe.withSettings(self: ProbeInternal, settings: Settings): { Fire: ProbeFire, FireAll: ProbeFireAll }
	assert(type(settings) == "table", "Settings must be a table")
	return {
		_Probes = self._Probes,
		Fire = self.Fire,
		FireAll = self.FireAll,
		settings = OverrideSettings(self.settings, settings),
	}
end

Probe.URE = Probe:withSettings({
	Type = "URE",
})

if not isSetup then
	Probe:_setup():await()
end
return Probe :: Probe
