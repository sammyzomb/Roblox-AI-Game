-- Unit tests for TrainingDecorLayout (P1b minimum visual pass). Pure layout
-- only. These tests create no Instances and do not prove how the
-- decorations look, that they stay non-colliding in the engine, or that the
-- signs are readable. Those remain Studio checks.

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	local Layout = require("../src/ReplicatedStorage/Shared/Combat/TrainingDecorLayout")
	local Config = require("../src/ReplicatedStorage/Shared/Combat/TrainingSceneConfig")
	local Attacker = require("../src/ReplicatedStorage/Shared/Combat/TrainingAttacker")
	local points = Config.resolve()

	test("decor uses its own container, not the owned training scene", function()
		eq(Layout.ContainerName ~= Config.ContainerName, true, "container names differ")
	end)

	test("lanterns stand in pairs outside the walkway and before the platform", function()
		local lanterns = Layout.lanterns()
		eq(#lanterns >= 4, true, "at least two pairs")
		eq(#lanterns % 2, 0, "pairs")
		local halfZ = Config.Walkway.Size.Z / 2
		local platformEdgeX = points.Origin.X - Config.Platform.Size.X / 2
		for _, lantern in lanterns do
			eq(math.abs(lantern.Z - points.WalkwayCenter.Z) > halfZ, true, "outside the walkway")
			eq(lantern.X < platformEdgeX, true, "before the platform")
			eq(lantern.Y, Config.GroundLevelY, "on the ground")
		end
	end)

	test("gate pillars clear the entrance and exit touch volumes", function()
		local gates = Layout.gates()
		eq(#gates, 2)
		eq(gates[1].Center.X, points.Entrance.X, "entrance gate over the entrance pad")
		eq(gates[2].Center.X, points.Exit.X, "exit gate over the exit pad")
		for _, gate in gates do
			eq(gate.HalfWidth > Config.RoleMarker.Size.Z / 2, true, "pillars outside the pad")
			eq(gate.Height >= 10, true, "tall enough to walk under")
		end
	end)

	test("block-practice ring matches the attacker's practice range", function()
		local ring = Layout.rings()[1]
		eq(ring.Id, "BlockPractice")
		eq(ring.Radius, Attacker.DEVELOPMENT_PRACTICE_RANGE, "radius")
		eq(ring.Center.X, points.DummyMarker.X)
		eq(ring.Center.Z, points.DummyMarker.Z)
	end)

	test("every passive dummy gets a calm ground ring", function()
		local rings = Layout.rings()
		eq(#rings, 1 + #Layout.PassiveDummies)
		for index, position in Layout.PassiveDummies do
			local ring = rings[index + 1]
			eq(ring.Tone, "Calm")
			eq(ring.Center.X, position.X)
			eq(ring.Center.Z, position.Z)
		end
	end)

	test("signs cover the route, both pads, the passive targets and block practice", function()
		local byId = {}
		for _, sign in Layout.signs() do
			eq(byId[sign.Id], nil, "unique id")
			byId[sign.Id] = sign
			eq(#sign.Title > 0 and #sign.Body > 0, true, "has text")
			eq(sign.Position.Y > 5, true, "above head height")
		end
		for _, id in { "Guide", "Entrance", "Exit", "Passive", "BlockPractice" } do
			eq(byId[id] ~= nil, true, id)
		end
		eq(byId.Entrance.Position.X, points.Entrance.X)
		eq(byId.Exit.Position.X, points.Exit.X)
		eq(byId.BlockPractice.Position.Z, points.DummyMarker.Z)
		eq(string.find(byId.BlockPractice.Body, "F", 1, true) ~= nil, true, "names the block key")
		eq(string.find(byId.Passive.Body, "不會還手", 1, true) ~= nil, true, "says passive targets do not attack")
	end)
end
