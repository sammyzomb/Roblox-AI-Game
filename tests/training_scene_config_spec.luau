-- Unit tests for TrainingSceneConfig (Task #23 increment:
-- fix-training-scene-reachability-ensure-dummy). Pure placement/geometry
-- math only; no Roblox services involved, matching this module's
-- Roblox-API-free design.
--
-- These tests specifically assert the REVISED walkable-entry geometry: a
-- single shared ground level with no floating platform, a walkway that
-- actually overlaps the platform footprint (no jump-across gap), and a
-- world-side (not training-local) return spawn. Several of these would FAIL
-- against the prior floating-platform-at-Y=10 layout with no walkway.

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	local TrainingSceneConfig = require("../src/ReplicatedStorage/Shared/Combat/TrainingSceneConfig")

	test("resolve uses the configured Origin by default", function()
		local points = TrainingSceneConfig.resolve()
		eq(points.Origin.X, TrainingSceneConfig.Origin.X, "Origin.X")
		eq(points.Origin.Y, TrainingSceneConfig.Origin.Y, "Origin.Y")
		eq(points.Origin.Z, TrainingSceneConfig.Origin.Z, "Origin.Z")
	end)

	test("resolve offsets entrance/exit/return-spawn/dummy from a custom origin", function()
		local origin = { X = 1000, Y = 0, Z = -1000 }
		local points = TrainingSceneConfig.resolve(origin)
		eq(points.Entrance.X, origin.X + TrainingSceneConfig.EntranceOffset.X, "Entrance.X")
		eq(points.Exit.X, origin.X + TrainingSceneConfig.ExitOffset.X, "Exit.X")
		eq(points.ReturnSpawn.X, origin.X + TrainingSceneConfig.ReturnSpawnOffset.X, "ReturnSpawn.X")
		eq(points.DummyMarker.Z, origin.Z + TrainingSceneConfig.DummyMarkerOffset.Z, "DummyMarker.Z")
	end)

	test("every walkable point (entrance, exit, return-spawn, dummy, walkway) shares one ground level", function()
		local points = TrainingSceneConfig.resolve()
		local y = TrainingSceneConfig.GroundLevelY
		eq(points.Entrance.Y, y, "Entrance.Y at ground level")
		eq(points.Exit.Y, y, "Exit.Y at ground level")
		eq(points.ReturnSpawn.Y, y, "ReturnSpawn.Y at ground level")
		eq(points.DummyMarker.Y, y, "DummyMarker.Y at ground level")
		eq(points.WalkwayCenter.Y, y, "WalkwayCenter.Y at ground level")
		-- This is the key reachability regression: the prior layout placed
		-- Origin (and everything derived from it) at Y=10, which would fail
		-- this assertion.
		eq(points.Origin.Y, y, "Origin.Y at ground level (no floating platform)")
	end)

	test("entrance and exit stay within the platform footprint", function()
		local points = TrainingSceneConfig.resolve()
		local platformSize = TrainingSceneConfig.Platform.Size
		eq(TrainingSceneConfig.pointInsideBox(points.Entrance, points.Origin, platformSize), true, "Entrance inside platform")
		eq(TrainingSceneConfig.pointInsideBox(points.Exit, points.Origin, platformSize), true, "Exit inside platform")
	end)

	test("return spawn is outside the platform footprint (world-side, not training-local)", function()
		local points = TrainingSceneConfig.resolve()
		local platformSize = TrainingSceneConfig.Platform.Size
		eq(
			TrainingSceneConfig.pointInsideBox(points.ReturnSpawn, points.Origin, platformSize),
			false,
			"ReturnSpawn should be outside the platform"
		)
	end)

	test("return spawn stays clear of a representative default spawn footprint", function()
		local points = TrainingSceneConfig.resolve()
		local defaultSpawnCenter = { X = 0, Y = 0, Z = 0 }
		local defaultSpawnSize = { X = 12, Y = 1, Z = 12 }
		eq(
			TrainingSceneConfig.pointInsideBox(points.ReturnSpawn, defaultSpawnCenter, defaultSpawnSize),
			false,
			"ReturnSpawn must not overlap a default SpawnLocation footprint"
		)
	end)

	test("the walkway footprint actually overlaps the platform footprint (no jump-across gap)", function()
		local points = TrainingSceneConfig.resolve()
		local platformSize = TrainingSceneConfig.Platform.Size
		local walkwaySize = TrainingSceneConfig.Walkway.Size
		eq(
			TrainingSceneConfig.boxesOverlap(points.WalkwayCenter, walkwaySize, points.Origin, platformSize),
			true,
			"walkway must overlap the platform so there is a continuous walkable path"
		)
	end)

	test("the walkway spans from near world origin toward the platform (reachable by ordinary walking)", function()
		local points = TrainingSceneConfig.resolve()
		local walkwaySize = TrainingSceneConfig.Walkway.Size
		-- The walkway's near edge (closest to world origin) must be close to
		-- X=0, not stranded far out near the platform only.
		local nearEdgeX = points.WalkwayCenter.X - walkwaySize.X / 2
		eq(nearEdgeX <= 20, true, "walkway near edge must be close to world origin (<=20 studs out)")
	end)

	test("scene origin never overlaps a representative default spawn footprint near world origin", function()
		local points = TrainingSceneConfig.resolve()
		-- A generous stand-in for a default SpawnLocation footprint/clear
		-- radius: a 40x40 box centered at world origin (0,0,0).
		local defaultSpawnCenter = { X = 0, Y = 0, Z = 0 }
		local defaultSpawnSize = { X = 40, Y = 1, Z = 40 }
		eq(
			TrainingSceneConfig.pointInsideBox(points.Origin, defaultSpawnCenter, defaultSpawnSize),
			false,
			"training scene origin must stay clear of the default spawn area"
		)
	end)

	test("entrance, exit, and return spawn are at distinct points", function()
		local points = TrainingSceneConfig.resolve()
		local function same(a, b)
			return a.X == b.X and a.Y == b.Y and a.Z == b.Z
		end
		eq(same(points.Entrance, points.Exit), false, "Entrance ~= Exit")
		eq(same(points.Entrance, points.ReturnSpawn), false, "Entrance ~= ReturnSpawn")
		eq(same(points.Exit, points.ReturnSpawn), false, "Exit ~= ReturnSpawn")
	end)

	test("restingCenterY models half-height correctly for a part's top surface", function()
		eq(TrainingSceneConfig.restingCenterY(0, 2), -1, "2-tall part resting at Y=0 centers at Y=-1")
		eq(TrainingSceneConfig.restingCenterY(10, 6), 7, "6-tall part resting at Y=10 centers at Y=7")
		eq(TrainingSceneConfig.restingCenterY(5, 1), 4.5, "1-tall part resting at Y=5 centers at Y=4.5")
	end)
end
