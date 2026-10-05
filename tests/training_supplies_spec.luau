-- Pure tests for temporary training health-potion stock.
-- The production module is src/ReplicatedStorage/Shared/Combat/TrainingSupplies.luau.
-- These tests do not construct Roblox instances and do not read PlayerData.

local Config = require("../src/ReplicatedStorage/Shared/Config")
local TrainingSupplies = require("../src/ReplicatedStorage/Shared/Combat/TrainingSupplies")

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	local function fresh(grant: { [string]: number }?)
		return TrainingSupplies.new(grant or { health_potion = 2 })
	end

	test("development stock is a separate table from permanent starter consumables", function()
		local development = Config.Combat.DevelopmentTrainingStock
		local starter = Config.Combat.StarterConsumables
		eq(development ~= starter, true, "table identity")
		eq(development.health_potion, 2)
		eq(starter.health_potion, 3)
		eq(TrainingSupplies.HEALTH_POTION, "health_potion")
		local store = TrainingSupplies.new(development)
		local player = {}
		eq(store:beginSession(player), true)
		eq(store:count(player, "health_potion"), development.health_potion)
		eq(store:count(player, "health_potion") ~= starter.health_potion, true)
	end)

	test("opaque identities stay isolated even when their names match", function()
		local store = fresh()
		local first = { Name = "Same" }
		local second = { Name = "Same" }
		eq(store:beginSession(first), true)
		eq(store:beginSession(second), true)
		eq(store:finishUse(first, "health_potion", true), true)
		eq(store:count(first, "health_potion"), 1)
		eq(store:count(second, "health_potion"), 2)
		eq(store:hasSession(first), true)
		eq(store:hasSession(second), true)
	end)

	test("the first session grants stock and a repeated initialization does not refill", function()
		local store = fresh()
		local player = {}
		eq(store:hasSession(player), false)
		eq(store:beginSession(player), true)
		eq(store:count(player, "health_potion"), 2)
		eq(store:finishUse(player, "health_potion", true), true)
		eq(store:count(player, "health_potion"), 1)
		eq(store:beginSession(player), false)
		eq(store:count(player, "health_potion"), 1)
		eq(store:hasSession(player), true)
	end)

	test("only an accepted use decrements stock", function()
		local store = fresh()
		local player = {}
		store:beginSession(player)
		local plan = store:planUse(player, "health_potion", true, false)
		eq(plan.Route, "Training")
		eq(plan.Reason, nil)
		eq(store:count(player, "health_potion"), 2, "planning does not spend")
		eq(store:finishUse(player, "health_potion", false), false)
		eq(store:count(player, "health_potion"), 2, "rejection does not spend")
		local full = store:planUse(player, "health_potion", true, true)
		eq(full.Route, "Reject")
		eq(full.Reason, "FullHealth")
		eq(store:count(player, "health_potion"), 2, "full health does not spend")
		eq(store:finishUse(player, "health_potion", true), true)
		eq(store:count(player, "health_potion"), 1)
	end)

	test("exhaustion rejects further use and does not refill the same session", function()
		local store = fresh({ health_potion = 1 })
		local player = {}
		store:beginSession(player)
		eq(store:finishUse(player, "health_potion", true), true)
		eq(store:count(player, "health_potion"), 0)
		eq(store:hasSession(player), true)
		local again, why = store:finishUse(player, "health_potion", true)
		eq(again, false)
		eq(why, "NoTrainingStock")
		eq(store:count(player, "health_potion"), 0)
		eq(store:beginSession(player), false)
		eq(store:count(player, "health_potion"), 0)
		local blocked = store:planUse(player, "health_potion", true, false)
		eq(blocked.Route, "Reject")
		eq(blocked.Reason, "NoTrainingStock")
	end)

	test("clear is idempotent and a later session grants a fresh stock", function()
		local store = fresh()
		local player = {}
		store:beginSession(player)
		store:finishUse(player, "health_potion", true)
		store:clear(player)
		eq(store:hasSession(player), false)
		eq(store:count(player, "health_potion"), 0)
		store:clear(player)
		eq(store:hasSession(player), false)
		local missing = {}
		store:clear(missing)
		eq(store:beginSession(player), true)
		eq(store:count(player, "health_potion"), 2)
	end)

	test("training use never selects persistent stock, including unsupported and empty items", function()
		local store = fresh()
		local player = {}
		local before = store:planUse(player, "health_potion", true, false)
		eq(before.Route, "Reject")
		eq(before.Reason, "NoTrainingStock")
		store:beginSession(player)
		for _, itemId in { "mana_potion", "barrier_scroll", "not_an_item" } do
			local plan = store:planUse(player, itemId, true, false)
			eq(plan.Route, "Reject", itemId)
			eq(plan.Reason, "TrainingItemUnsupported", itemId)
			eq(store:count(player, "health_potion"), 2, itemId)
		end
		local outside = store:planUse(player, "health_potion", false, true)
		eq(outside.Route, "Persistent")
		eq(store:count(player, "health_potion"), 2, "outside training does not spend temporary stock")
		eq(store:finishUse(player, "mana_potion", true), false)
		eq(store:count(player, "health_potion"), 2)
	end)

	test("a non-positive development quantity grants an empty session instead of permanent stock", function()
		local store = TrainingSupplies.new({ health_potion = 0, mana_potion = 9 })
		local player = {}
		eq(store:beginSession(player), true)
		eq(store:count(player, "health_potion"), 0)
		eq(store:count(player, "mana_potion"), 0)
		local plan = store:planUse(player, "mana_potion", true, false)
		eq(plan.Route, "Reject")
		eq(plan.Reason, "TrainingItemUnsupported")
	end)
end
