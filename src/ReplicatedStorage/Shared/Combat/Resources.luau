--!strict
-- Stamina / mana / energy pools. Pure module: callers pass the current time.
--
-- Pools are generic: any id in Config.Combat.Pools works ("Stamina", "Mana",
-- later "Rage", "Focus"...). Attacks and items reference pools by id.

local Types = require("./Types")

type PoolState = Types.PoolState

local Resources = {}

function Resources.newPool(max: number, regen: number, regenDelay: number): PoolState
	return { Current = max, Max = max, Regen = regen, RegenDelay = regenDelay, LastSpent = -math.huge }
end

function Resources.canSpend(pool: PoolState?, amount: number): boolean
	if amount <= 0 then
		return true
	end
	return pool ~= nil and pool.Current >= amount
end

-- Spends if affordable. Returns false (and spends nothing) otherwise.
function Resources.spend(pool: PoolState?, amount: number, now: number): boolean
	if amount <= 0 then
		return true
	end
	if pool == nil or pool.Current < amount then
		return false
	end
	pool.Current -= amount
	pool.LastSpent = now
	return true
end

-- Drains up to `amount`, returns how much was actually drained (block stamina).
function Resources.drain(pool: PoolState?, amount: number, now: number): number
	if pool == nil or amount <= 0 then
		return 0
	end
	local drained = math.min(pool.Current, amount)
	pool.Current -= drained
	pool.LastSpent = now
	return drained
end

function Resources.restore(pool: PoolState?, amount: number)
	if pool == nil or amount <= 0 then
		return
	end
	pool.Current = math.min(pool.Max, pool.Current + amount)
end

function Resources.regen(pool: PoolState, now: number, dt: number)
	if now - pool.LastSpent < pool.RegenDelay then
		return
	end
	pool.Current = math.min(pool.Max, pool.Current + pool.Regen * dt)
end

return table.freeze(Resources)
