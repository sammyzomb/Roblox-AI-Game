--!strict
-- Single place that knows remote names. Remotes themselves are declared as
-- files in ReplicatedStorage/Remotes so they exist before any script runs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.Names = table.freeze({
	RequestAction = "RequestAction", -- client -> server: (actionId: string)
	StateChanged = "StateChanged", -- server -> client: (state: ClientState)
	GetState = "GetState", -- client -> server, returns ClientState?
	CombatRequest = "CombatRequest", -- client -> server: (request: CombatRequest) see CombatService
	CombatEvent = "CombatEvent", -- server -> clients: (event: CombatEvent) presentation only
})

local remotes = ReplicatedStorage:WaitForChild("Remotes")

function Net.event(name: string): RemoteEvent
	return remotes:WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	return remotes:WaitForChild(name) :: RemoteFunction
end

return Net
