-- Unit tests for TrainingSceneConfig and the pure TrainingSceneRepair plan
-- (Task #23 scene correction). No Roblox services involved.
--
-- These tests do not create Instances. They do not prove CollectionService
-- tag calls, BasePart.Touched, CanCollide/CanTouch engine behavior,
-- Destroy/recreate of a live child, or that a tag listener observes a
-- configured Instance. Those remain Studio checks.
--
-- Class-replacement cases below are pure plans: they assert the tag list
-- a rebuilt Part should receive. They do not construct a Roblox Instance.
--
-- These tests specifically assert the REVISED walkable-entry geometry: a
-- single shared ground level with no floating platform, a walkway that
-- actually overlaps the platform footprint (no jump-across gap), and a
-- world-side (not training-local) return spawn. Several of these would FAIL
-- against the prior floating-platform-at-Y=10 layout with no walkway.

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	local TrainingSceneConfig = require("../src/ReplicatedStorage/Shared/Combat/TrainingSceneConfig")
	local TrainingSceneRepair = require("../src/ReplicatedStorage/Shared/Combat/TrainingSceneRepair")

	local function has(list, value): boolean
		for _, item in list do
			if item == value then
				return true
			end
		end
		return false
	end

	local function hasText(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	local function surfaceTop(fullHeightY: number): number
		return TrainingSceneConfig.restingCenterY(TrainingSceneConfig.GroundLevelY, fullHeightY) + fullHeightY / 2
	end

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

	test("walkway and platform tops stay on the shared ground as the walking surface", function()
		local walkwayTop = surfaceTop(TrainingSceneConfig.Walkway.Size.Y)
		local platformTop = surfaceTop(TrainingSceneConfig.Platform.Size.Y)
		eq(walkwayTop, TrainingSceneConfig.GroundLevelY, "walkway top stays at ground level")
		eq(platformTop, TrainingSceneConfig.GroundLevelY, "platform top stays at ground level")
		eq(walkwayTop, platformTop, "walkway and platform share one walking surface")
	end)

	test("role markers are visible non-colliding touch volumes above the walking surface", function()
		local walkwayTop = surfaceTop(TrainingSceneConfig.Walkway.Size.Y)
		local platformTop = surfaceTop(TrainingSceneConfig.Platform.Size.Y)
		local volume = TrainingSceneConfig.roleMarkerVolume(walkwayTop)
		eq(volume.bottom >= walkwayTop, true, "marker bottom is at or above the walkway top")
		eq(volume.bottom >= platformTop, true, "marker bottom is at or above the platform top")
		eq(volume.top > walkwayTop, true, "marker top is above the walkway top")
		eq(volume.top > platformTop, true, "marker top is above the platform top")
		eq(volume.canCollide, false, "CanCollide")
		eq(volume.canTouch, true, "CanTouch")
		eq(volume.transparency < 1, true, "transparency leaves the volume visible")
		local embeddedCenter = TrainingSceneConfig.restingCenterY(walkwayTop, volume.size.Y)
		eq(volume.centerY ~= embeddedCenter, true, "marker is not embedded under the surface")

		local points = TrainingSceneConfig.resolve()
		eq(points.Entrance.X, points.Origin.X + TrainingSceneConfig.EntranceOffset.X, "entrance X unchanged")
		eq(points.Entrance.Z, points.Origin.Z + TrainingSceneConfig.EntranceOffset.Z, "entrance Z unchanged")
		eq(points.Exit.X, points.Origin.X + TrainingSceneConfig.ExitOffset.X, "exit X unchanged")
		eq(points.ReturnSpawn.X, points.Origin.X + TrainingSceneConfig.ReturnSpawnOffset.X, "return spawn X unchanged")
		eq(points.ReturnSpawn.Z, points.Origin.Z + TrainingSceneConfig.ReturnSpawnOffset.Z, "return spawn Z unchanged")
	end)

	test("scene role set is exactly the three training tags", function()
		local roles = TrainingSceneRepair.SceneRoleTags
		eq(#roles, 3, "role count")
		eq(has(roles, "TrainingEntrance"), true, "entrance role")
		eq(has(roles, "TrainingExit"), true, "exit role")
		eq(has(roles, "TrainingReturnSpawn"), true, "return role")
	end)

	test("owned role repair keeps the expected tag, drops the other roles, and keeps a third-party tag", function()
		local current = { "TrainingExit", "TrainingEntrance", "PluginLight" }
		local plan = TrainingSceneRepair.reconcileRoleTags(current, "TrainingEntrance")
		eq(has(plan.add, "TrainingEntrance"), false, "expected tag is already present")
		eq(has(plan.remove, "TrainingExit"), true, "stale exit role is removed")
		eq(has(plan.remove, "TrainingEntrance"), false, "expected role is not removed")
		eq(has(plan.remove, "PluginLight"), false, "third-party tag is not removed")
		eq(has(plan.add, "PluginLight"), false, "third-party tag is not re-added")

		local repaired = TrainingSceneRepair.applyRoleTags(current, plan)
		eq(has(repaired, "TrainingEntrance"), true, "entrance remains")
		eq(has(repaired, "TrainingExit"), false, "exit is gone")
		eq(has(repaired, "PluginLight"), true, "third-party tag remains")

		local again = TrainingSceneRepair.reconcileRoleTags(repaired, "TrainingEntrance")
		eq(#again.add, 0, "second repair adds nothing")
		eq(#again.remove, 0, "second repair removes nothing")
	end)

	test("debug parts lose every scene role and keep unrelated tags", function()
		local current = { "TrainingEntrance", "TrainingExit", "TrainingReturnSpawn", "DebugBeacon" }
		local plan = TrainingSceneRepair.reconcileRoleTags(current, nil)
		eq(#plan.add, 0, "debug part gains no scene role")
		eq(has(plan.remove, "TrainingEntrance"), true, "entrance stripped")
		eq(has(plan.remove, "TrainingExit"), true, "exit stripped")
		eq(has(plan.remove, "TrainingReturnSpawn"), true, "return stripped")
		eq(has(plan.remove, "DebugBeacon"), false, "unrelated tag stays out of the remove list")

		local repaired = TrainingSceneRepair.applyRoleTags(current, plan)
		eq(has(repaired, "DebugBeacon"), true, "unrelated tag remains")
		eq(has(repaired, "TrainingEntrance"), false, "no entrance on a debug part")
		eq(has(repaired, "TrainingExit"), false, "no exit on a debug part")
		eq(has(repaired, "TrainingReturnSpawn"), false, "no return role on a debug part")

		local again = TrainingSceneRepair.reconcileRoleTags(repaired, nil)
		eq(#again.add, 0, "second debug repair adds nothing")
		eq(#again.remove, 0, "second debug repair removes nothing")
	end)

	test("a missing expected role is added without touching a third-party tag", function()
		local current = { "VendorBillboard" }
		local plan = TrainingSceneRepair.reconcileRoleTags(current, "TrainingReturnSpawn")
		eq(has(plan.add, "TrainingReturnSpawn"), true, "missing return role is added")
		eq(#plan.remove, 0, "nothing to remove")
		local repaired = TrainingSceneRepair.applyRoleTags(current, plan)
		eq(has(repaired, "VendorBillboard"), true, "third-party tag remains")
		eq(has(repaired, "TrainingReturnSpawn"), true, "return role present")
	end)

	test("reconcile rejects a tag outside the finite scene-role set", function()
		local ok = pcall(function()
			TrainingSceneRepair.reconcileRoleTags({}, "CombatNPC")
		end)
		eq(ok, false, "non-role tag is rejected")
	end)

	test("missing child is created, and an owned Part is repaired in place on repeat", function()
		local created = TrainingSceneRepair.decideChildRepair("TrainingEntrancePad", "TrainingGroundScene", nil)
		eq(created.action, "create", "missing child")
		eq(created.warning, nil, "create has no warning")

		local ownedPart = { className = "Part", owned = true }
		local repaired = TrainingSceneRepair.decideChildRepair("TrainingEntrancePad", "TrainingGroundScene", ownedPart)
		eq(repaired.action, "repair", "first repair")
		eq(repaired.warning, nil, "in-place repair has no warning")
		local repeated = TrainingSceneRepair.decideChildRepair("TrainingEntrancePad", "TrainingGroundScene", ownedPart)
		eq(repeated.action, "repair", "repeat repair does not replace a Part")
	end)

	test("owned wrong-class child is replaced as a Part, then later repairs stay in place", function()
		local folder = TrainingSceneRepair.decideChildRepair("TrainingEntrancePad", "TrainingGroundScene", {
			className = "Folder",
			owned = true,
		})
		eq(folder.action, "replace", "owned Folder is replaced")
		eq(hasText(folder.warning :: string, "owned"), true, "warning says owned")
		eq(hasText(folder.warning :: string, "unowned"), false, "owned rebuild is not called unowned")
		eq(hasText(folder.warning :: string, "Folder"), true, "warning names the actual class")
		eq(hasText(folder.warning :: string, "Part"), true, "warning names the required Part policy")
		eq(hasText(folder.warning :: string, "replacing"), true, "warning says it is replacing")

		local mesh = TrainingSceneRepair.decideChildRepair("TrainingExitPad", "TrainingGroundScene", {
			className = "MeshPart",
			owned = true,
		})
		eq(mesh.action, "replace", "owned MeshPart is replaced")
		eq(hasText(mesh.warning :: string, "MeshPart"), true, "warning names MeshPart")
		eq(hasText(mesh.warning :: string, "unowned"), false, "MeshPart rebuild is not called unowned")

		local after = TrainingSceneRepair.decideChildRepair("TrainingEntrancePad", "TrainingGroundScene", {
			className = "Part",
			owned = true,
		})
		eq(after.action, "repair", "rebuilt Part is repaired in place")
		local again = TrainingSceneRepair.decideChildRepair("TrainingEntrancePad", "TrainingGroundScene", {
			className = "Part",
			owned = true,
		})
		eq(again.action, "repair", "second pass still repairs in place")
	end)

	test("unowned same-name child is skipped and the warning says unowned", function()
		local part = TrainingSceneRepair.decideChildRepair("TrainingReturnSpawnPad", "TrainingGroundScene", {
			className = "Part",
			owned = false,
		})
		eq(part.action, "skip", "unowned Part is not repaired or destroyed")
		eq(hasText(part.warning :: string, "unowned"), true, "warning says unowned")
		eq(hasText(part.warning :: string, "replacing"), false, "skip does not claim a rebuild")
		eq(hasText(part.warning :: string, "Part"), true, "warning names the actual class")
		eq(hasText(part.warning :: string, "leaving it unchanged"), true, "warning says the object is left unchanged")

		local folder = TrainingSceneRepair.decideChildRepair("TrainingWalkway", "TrainingGroundScene", {
			className = "Folder",
			owned = false,
		})
		eq(folder.action, "skip", "unowned wrong class is still not destroyed")
		eq(hasText(folder.warning :: string, "unowned"), true, "reason is the missing ownership")
		eq(hasText(folder.warning :: string, "replacing"), false, "unowned folder is not described as a replace")
		eq(hasText(folder.warning :: string, "Folder"), true, "warning names Folder")
	end)

	local function sameTags(actual: { string }, expected: { string }, what: string)
		eq(#actual, #expected, `{what} count`)
		for index, tag in expected do
			eq(actual[index], tag, `{what} tag {index}`)
		end
	end

	local function requireReplacementTags(plan: any): { string }
		local tags = plan.tags
		if tags == nil then
			error("class replacement plan is missing its tag list", 2)
		end
		return tags
	end

	-- Pure plan only. No Instance, Destroy, or CollectionService call.
	test("owned wrong-class role rebuild keeps third-party tags and only the expected role", function()
		local snapshot = { "TrainingExit", "PluginLight", "VendorBillboard", "PluginLight" }
		local plan = TrainingSceneRepair.planClassReplacement("TrainingEntrancePad", "TrainingGroundScene", {
			className = "Folder",
			owned = true,
		}, snapshot, "TrainingEntrance")
		eq(plan.action, "replace", "owned Folder is a replacement")
		eq(hasText(plan.warning :: string, "owned"), true, "warning says owned")
		eq(hasText(plan.warning :: string, "unowned"), false, "owned rebuild is not called unowned")
		local tags = requireReplacementTags(plan)
		sameTags(tags, { "PluginLight", "VendorBillboard", "TrainingEntrance" }, "role replacement")
		eq(has(tags, "TrainingExit"), false, "wrong entrance-pad role is not copied")
		eq(has(tags, "TrainingReturnSpawn"), false, "return role is not copied")
		eq(snapshot[1], "TrainingExit", "snapshot itself is not rewritten")

		local repeated = TrainingSceneRepair.planClassReplacement("TrainingEntrancePad", "TrainingGroundScene", {
			className = "Folder",
			owned = true,
		}, snapshot, "TrainingEntrance")
		sameTags(requireReplacementTags(repeated), tags, "planning the same snapshot twice")
	end)

	-- Pure plan only. No Instance, Destroy, or CollectionService call.
	test("owned wrong-class debug rebuild keeps third-party tags and drops every scene role", function()
		local snapshot = { "TrainingEntrance", "DebugBeacon", "TrainingExit", "TrainingReturnSpawn" }
		local plan = TrainingSceneRepair.planClassReplacement("TrainingDummyMarker", "TrainingGroundScene", {
			className = "MeshPart",
			owned = true,
		}, snapshot, nil)
		eq(plan.action, "replace", "owned debug MeshPart is a replacement")
		local tags = requireReplacementTags(plan)
		sameTags(tags, { "DebugBeacon" }, "debug replacement")
		eq(has(tags, "TrainingEntrance"), false, "debug rebuild drops entrance")
		eq(has(tags, "TrainingExit"), false, "debug rebuild drops exit")
		eq(has(tags, "TrainingReturnSpawn"), false, "debug rebuild drops return")
	end)

	-- Pure plan only. The second call stands in for a later boot after the
	-- replacement Part already carries the planned tags. It does not create
	-- an Instance.
	test("a repeated class repair does not add another tag change", function()
		local roleTags = requireReplacementTags(TrainingSceneRepair.planClassReplacement("TrainingExitPad", "TrainingGroundScene", {
			className = "Folder",
			owned = true,
		}, { "TrainingEntrance", "PluginLight" }, "TrainingExit"))
		local roleAgain = TrainingSceneRepair.planClassReplacement("TrainingExitPad", "TrainingGroundScene", {
			className = "Part",
			owned = true,
		}, roleTags, "TrainingExit")
		eq(roleAgain.action, "repair", "rebuilt role Part stays in place")
		eq(roleAgain.tags, nil, "in-place repair has no replacement tag list")
		local roleDelta = TrainingSceneRepair.reconcileRoleTags(roleTags, "TrainingExit")
		eq(#roleDelta.add, 0, "second role repair adds nothing")
		eq(#roleDelta.remove, 0, "second role repair removes nothing")
		sameTags(TrainingSceneRepair.replacementTags(roleTags, "TrainingExit"), roleTags, "role tags stay stable")

		local debugTags = requireReplacementTags(TrainingSceneRepair.planClassReplacement("TrainingWalkway", "TrainingGroundScene", {
			className = "Folder",
			owned = true,
		}, { "TrainingReturnSpawn", "DebugBeacon" }, nil))
		local debugAgain = TrainingSceneRepair.planClassReplacement("TrainingWalkway", "TrainingGroundScene", {
			className = "Part",
			owned = true,
		}, debugTags, nil)
		eq(debugAgain.action, "repair", "rebuilt debug Part stays in place")
		eq(debugAgain.tags, nil, "debug in-place repair has no replacement tag list")
		local debugDelta = TrainingSceneRepair.reconcileRoleTags(debugTags, nil)
		eq(#debugDelta.add, 0, "second debug repair adds nothing")
		eq(#debugDelta.remove, 0, "second debug repair removes nothing")
		eq(has(debugTags, "DebugBeacon"), true, "debug third-party tag survived")
		eq(has(debugTags, "TrainingReturnSpawn"), false, "debug role stayed off")
	end)

	-- Pure plan only. Unowned objects are not given a tag rewrite, which is
	-- the plan-level stand-in for leaving the live object untouched.
	test("unowned name collisions are not given a replacement tag plan", function()
		local roleSnapshot = { "TrainingExit", "PluginLight" }
		local unownedPart = TrainingSceneRepair.planClassReplacement("TrainingReturnSpawnPad", "TrainingGroundScene", {
			className = "Part",
			owned = false,
		}, roleSnapshot, "TrainingReturnSpawn")
		eq(unownedPart.action, "skip", "unowned Part is not replaced")
		eq(unownedPart.tags, nil, "unowned Part has no replacement tags")
		eq(hasText(unownedPart.warning :: string, "unowned"), true, "warning says unowned")
		eq(hasText(unownedPart.warning :: string, "leaving it unchanged"), true, "warning leaves it unchanged")
		sameTags(roleSnapshot, { "TrainingExit", "PluginLight" }, "unowned part snapshot")

		local debugSnapshot = { "TrainingEntrance", "DebugBeacon", "TrainingExit" }
		local unownedFolder = TrainingSceneRepair.planClassReplacement("TrainingDummyMarker", "TrainingGroundScene", {
			className = "Folder",
			owned = false,
		}, debugSnapshot, nil)
		eq(unownedFolder.action, "skip", "unowned wrong class is not replaced")
		eq(unownedFolder.tags, nil, "unowned folder has no replacement tags")
		eq(hasText(unownedFolder.warning :: string, "replacing"), false, "unowned folder is not a replace")
		sameTags(debugSnapshot, { "TrainingEntrance", "DebugBeacon", "TrainingExit" }, "unowned folder snapshot")
	end)
end
