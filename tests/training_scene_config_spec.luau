-- Unit tests for TrainingSceneConfig (Task #23 increment:
-- training-scene-bootstrap). Pure placement/geometry math only; no Roblox
-- services involved, matching this module's Roblox-API-free design.

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	local TrainingSceneConfig = require("../src/ReplicatedStorage/Shared/Combat/TrainingSceneConfig")

	test("resolve uses the configured Origin by default", function()
		local points = TrainingSceneConfig.resolve()
		eq(points.Origin.X, TrainingSceneConfig.Origin.X, "Origin.X")
		eq(points.Origin.Y, TrainingSceneConfig.Origin.Y, "Origin.Y")
		eq(points.Origin.Z, TrainingSceneConfig.Origin.Z, "Origin.Z")
	end)

	test("resolve offsets entrance/exit/return-spawn/dummy from a custom origin", function()
		local origin = { X = 1000, Y = 5, Z = -1000 }
		local points = TrainingSceneConfig.resolve(origin)
		eq(points.Entrance.X, origin.X + TrainingSceneConfig.EntranceOffset.X, "Entrance.X")
		eq(points.Exit.X, origin.X + TrainingSceneConfig.ExitOffset.X, "Exit.X")
		eq(points.ReturnSpawn.X, origin.X + TrainingSceneConfig.ReturnSpawnOffset.X, "ReturnSpawn.X")
		eq(points.DummyMarker.Z, origin.Z + TrainingSceneConfig.DummyMarkerOffset.Z, "DummyMarker.Z")
	end)

	test("entrance, exit, and dummy marker stay within the platform footprint", function()
		local points = TrainingSceneConfig.resolve()
		local platformSize = TrainingSceneConfig.Platform.Size
		eq(TrainingSceneConfig.pointInsideBox(points.Entrance, points.Origin, platformSize), true, "Entrance inside platform")
		eq(TrainingSceneConfig.pointInsideBox(points.Exit, points.Origin, platformSize), true, "Exit inside platform")
		eq(
			TrainingSceneConfig.pointInsideBox(points.DummyMarker, points.Origin, platformSize),
			true,
			"DummyMarker inside platform"
		)
	end)

	test("return spawn is deliberately outside the platform footprint", function()
		local points = TrainingSceneConfig.resolve()
		local platformSize = TrainingSceneConfig.Platform.Size
		eq(
			TrainingSceneConfig.pointInsideBox(points.ReturnSpawn, points.Origin, platformSize),
			false,
			"ReturnSpawn should be outside the platform"
		)
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
end
