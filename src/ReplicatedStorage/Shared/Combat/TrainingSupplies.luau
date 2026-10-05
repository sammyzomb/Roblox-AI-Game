--!strict
-- Development-only in-memory training consumable stock.
--
-- Sessions are keyed by opaque player identity (the value itself, never
-- tostring and never a display name). Nothing here reads or writes
-- PlayerData. The quantity copied into a new session comes only from the
-- development table passed to `new`. That table is not permanent stock,
-- not a price, and not an approved balance.
--
-- Public API:
--   TrainingSupplies.HEALTH_POTION                 "health_potion"
--   TrainingSupplies.new(developmentStock) -> Store
--   Store:beginSession(id) -> boolean
--       The first call for an id copies a fresh grant and returns true.
--       Another call while that session exists returns false and does not
--       refill, even after some stock has been spent.
--   Store:hasSession(id) -> boolean
--   Store:count(id, itemId) -> number
--   TrainingSupplies.route(plan) -> Route
--   Store:planUse(id, itemId, training, healBlocked?) -> UsePlan
--       A training plan is never Persistent. healBlocked rejects before
--       any count change (full health). Outside training the plan is
--       Persistent and this store is not spent.
--   Store:finishUse(id, itemId, accepted) -> (boolean, string?)
--       Decrements one potion only when accepted is true. Cooldown and
--       any other rejection pass false and leave the count unchanged.
--   Store:clear(id)
--       Drops the session. Repeating it is a no-op. The next beginSession
--       can grant a fresh stock.

export type Id = unknown

export type Route = "Training" | "Persistent" | "Reject"

export type UsePlan = {
	Route: Route,
	Reason: string?,
}

local HEALTH_POTION = "health_potion"

local TrainingSupplies = {
	HEALTH_POTION = HEALTH_POTION,
}
TrainingSupplies.__index = TrainingSupplies

function TrainingSupplies.route(plan: UsePlan): Route
	local route = plan.Route
	if route == "Training" or route == "Persistent" or route == "Reject" then
		return route
	end
	error("Unknown training supply route")
end

export type Store = typeof(setmetatable({
	_grant = 0,
	_sessions = {} :: { [Id]: { [string]: number } },
}, TrainingSupplies))

local function grantCount(developmentStock: { [string]: number }?): number
	if type(developmentStock) ~= "table" then
		return 0
	end
	local count = developmentStock[HEALTH_POTION]
	if type(count) ~= "number" or count ~= count or count <= 0 or count == math.huge or count ~= math.floor(count) then
		return 0
	end
	return count
end

function TrainingSupplies.new(developmentStock: { [string]: number }?): Store
	return setmetatable({
		_grant = grantCount(developmentStock),
		_sessions = {} :: { [Id]: { [string]: number } },
	}, TrainingSupplies)
end

function TrainingSupplies.beginSession(self: Store, id: Id): boolean
	if self._sessions[id] ~= nil then
		return false
	end
	self._sessions[id] = { [HEALTH_POTION] = self._grant }
	return true
end

function TrainingSupplies.hasSession(self: Store, id: Id): boolean
	return self._sessions[id] ~= nil
end

function TrainingSupplies.count(self: Store, id: Id, itemId: string): number
	local session = self._sessions[id]
	if session == nil then
		return 0
	end
	return session[itemId] or 0
end

function TrainingSupplies.planUse(self: Store, id: Id, itemId: string, training: boolean, healBlocked: boolean?): UsePlan
	if not training then
		return { Route = "Persistent" }
	end
	if itemId ~= HEALTH_POTION then
		return { Route = "Reject", Reason = "TrainingItemUnsupported" }
	end
	local session = self._sessions[id]
	if session == nil or (session[HEALTH_POTION] or 0) <= 0 then
		return { Route = "Reject", Reason = "NoTrainingStock" }
	end
	if healBlocked == true then
		return { Route = "Reject", Reason = "FullHealth" }
	end
	return { Route = "Training" }
end

function TrainingSupplies.finishUse(self: Store, id: Id, itemId: string, accepted: boolean): (boolean, string?)
	if not accepted then
		return false, nil
	end
	local session = self._sessions[id]
	local plan = self:planUse(id, itemId, true, false)
	if session == nil or plan.Route ~= "Training" then
		return false, plan.Reason or "NoTrainingStock"
	end
	local left = (session[HEALTH_POTION] or 0) - 1
	session[HEALTH_POTION] = if left > 0 then left else 0
	return true, nil
end

function TrainingSupplies.clear(self: Store, id: Id)
	self._sessions[id] = nil
end

return TrainingSupplies
