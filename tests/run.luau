-- Unit tests for the pure (Roblox-API-free) modules.
-- Run from the repository root:  luau tests/run.luau

local Progression = require("../src/ReplicatedStorage/Shared/Progression")
local PlayerDataModel = require("../src/ReplicatedStorage/Shared/PlayerDataModel")
local RateLimiter = require("../src/ServerScriptService/Systems/RateLimiter")

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print(`FAIL  {name}\n      {err}`)
	end
end

local function eq(actual: any, expected: any, what: string?)
	if actual ~= expected then
		error(`{what or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

local settings = { BaseXp = 50, Growth = 1.25, MaxLevel = 5 }

-- Progression
test("xpToNextLevel grows by Growth each level", function()
	eq(Progression.xpToNextLevel(1, settings), 50)
	eq(Progression.xpToNextLevel(2, settings), 62)
	eq(Progression.xpToNextLevel(3, settings), 78)
end)

test("addXp below threshold keeps level", function()
	local level, xp, gained = Progression.addXp(1, 0, 49, settings)
	eq(level, 1, "level"); eq(xp, 49, "xp"); eq(gained, 0, "gained")
end)

test("addXp exactly at threshold levels up with 0 leftover", function()
	local level, xp, gained = Progression.addXp(1, 45, 5, settings)
	eq(level, 2, "level"); eq(xp, 0, "xp"); eq(gained, 1, "gained")
end)

test("addXp can gain several levels at once", function()
	local level, xp, gained = Progression.addXp(1, 0, 50 + 62 + 10, settings)
	eq(level, 3, "level"); eq(xp, 10, "xp"); eq(gained, 2, "gained")
end)

test("addXp caps at MaxLevel with 0 xp", function()
	local level, xp = Progression.addXp(1, 0, 1e9, settings)
	eq(level, 5, "level"); eq(xp, 0, "xp")
	level, xp = Progression.addXp(5, 0, 100, settings)
	eq(level, 5, "level at max"); eq(xp, 0, "xp at max")
end)

test("addXp rejects negative amounts", function()
	eq(pcall(Progression.addXp, 1, 0, -1, settings), false)
end)

-- PlayerDataModel
test("new returns defaults", function()
	local data = PlayerDataModel.new()
	eq(data.Version, PlayerDataModel.CURRENT_VERSION, "Version")
	eq(data.Coins, 0, "Coins"); eq(data.Level, 1, "Level"); eq(data.Stats.Actions, 0, "Actions")
end)

test("reconcile of nil / non-table gives defaults", function()
	eq(PlayerDataModel.reconcile(nil).Coins, 0)
	eq(PlayerDataModel.reconcile("junk").Level, 1)
end)

test("reconcile keeps valid stored values", function()
	local data, newer = PlayerDataModel.reconcile({ Version = 1, Coins = 42, Xp = 7, Level = 3, Stats = { Actions = 9 } })
	eq(data.Coins, 42, "Coins"); eq(data.Xp, 7, "Xp"); eq(data.Level, 3, "Level")
	eq(data.Stats.Actions, 9, "Actions"); eq(newer, false, "newer")
end)

test("reconcile repairs corrupt values", function()
	local data = PlayerDataModel.reconcile({ Coins = -5, Xp = 0 / 0, Level = 0, Stats = "bad" })
	eq(data.Coins, 0, "Coins"); eq(data.Xp, 0, "Xp"); eq(data.Level, 1, "Level"); eq(data.Stats.Actions, 0, "Actions")
	eq(PlayerDataModel.reconcile({ Coins = math.huge }).Coins, 0, "inf coins")
	eq(PlayerDataModel.reconcile({ Coins = 3.9 }).Coins, 3, "fractional coins")
end)

test("reconcile flags data from a newer version", function()
	local _, newer = PlayerDataModel.reconcile({ Version = PlayerDataModel.CURRENT_VERSION + 1 })
	eq(newer, true)
end)

-- RateLimiter
test("RateLimiter allows up to max per window, then blocks", function()
	local limiter = RateLimiter.new(3, 1)
	eq(limiter:allow("a", 0), true); eq(limiter:allow("a", 0.1), true); eq(limiter:allow("a", 0.2), true)
	eq(limiter:allow("a", 0.3), false, "4th request")
end)

test("RateLimiter resets after the window and is per key", function()
	local limiter = RateLimiter.new(1, 1)
	eq(limiter:allow("a", 0), true); eq(limiter:allow("a", 0.5), false)
	eq(limiter:allow("b", 0.5), true, "other key")
	eq(limiter:allow("a", 1.0), true, "next window")
end)

test("RateLimiter clear forgets a key", function()
	local limiter = RateLimiter.new(1, 10)
	limiter:allow("a", 0); limiter:clear("a")
	eq(limiter:allow("a", 1), true)
end)

-- Combat + progression core (Issue #6)
require("./combat_spec")(test, eq)

-- Training ground session isolation (Issue #23, Increment A)
require("./training_ground_spec")(test, eq)

-- Training ground lifecycle orchestration (Issue #23, corrective increment:
-- real CharacterRemoving wiring, character-generation ownership, and
-- disconnect-safe ruleset restoration)
require("./training_lifecycle_spec")(test, eq)

-- Training scene bootstrap placement/geometry math (Issue #23 increment:
-- training-scene-bootstrap)
require("./training_scene_config_spec")(test, eq)

-- Server Hit damage labels (Issue #23). Pure text only; no BillboardGui.
require("./damage_float_spec")(test, eq)

-- Temporary training presets (Issue #23). Pure ids, compatibility, and
-- in-memory hand replacement. No PlayerData writes and no Roblox instances.
require("./training_loadouts_spec")(test, eq)

print(`{passed} passed, {failed} failed`)
if failed > 0 then
	error("tests failed")
end
