--!strict
-- Task #23 increment: fix-training-scene-reachability-ensure-dummy.
--
-- Creates/repairs the smallest server-authored placeholder scene needed for
-- the training ground to be enterable in a FRESH Studio place by ordinary
-- walking: a walkway connecting world origin to a platform, an entrance part
-- tagged "TrainingEntrance", an exit part tagged "TrainingExit", and a
-- return-spawn part tagged "TrainingReturnSpawn" (the exact CollectionService
-- tags TrainingGroundService.luau already listens for — unchanged by this
-- increment).
--
-- This service owns ONLY geometry creation/repair/idempotency. It does not
-- duplicate any combat, lifecycle, ruleset, or session logic.
--
-- Ownership correction (this increment): the prior version only checked
-- `Workspace:FindFirstChild(ContainerName)` by NAME and returned immediately,
-- which (a) could silently "adopt" an unrelated user-placed Folder that
-- happens to share the name, and (b) never repaired a partially-created or
-- hand-edited scene (missing a tag, wrong anchoring, etc.) on a later boot.
-- This version:
--   1. Finds-or-creates the container by Name AND an owning
--      `TrainingScene = true` attribute. A same-named Folder WITHOUT that
--      attribute is treated as an unknown user object: it is never deleted,
--      renamed, or written into. A warning is printed and this service
--      leaves it untouched (the training scene simply does not boot until
--      the collision is resolved by hand), rather than risking destroying
--      something a user placed.
--   2. Once an owned container exists (fresh or from a prior boot), each
--      required child is ensured individually by deterministic Name. A
--      missing child is created as a Part. An owned Part is repaired in
--      place. An owned child whose class is not Part is destroyed and
--      recreated as a Part, because class cannot change in place. An
--      unowned same-name object is left untouched and the warning says it
--      is unowned; it is never destroyed. "Owned" means
--      `TrainingSceneOwned = true`.
--      Scene-role tags are only {TrainingEntrance, TrainingExit,
--      TrainingReturnSpawn}. Each owned role pad keeps its own role and
--      loses the other two. Debug parts (walkway, platform, dummy marker)
--      keep none of the three. Tags outside that set are left in place.
--   3. Running :Start() twice (duplicate boot in one process, or a second
--      server start against the same saved Workspace) never duplicates
--      parts, tags, or connections: every owned child is looked up by Name
--      under the single owned container and repaired in place, not
--      recreated.
--
-- Dummy reuse (assignment item 3): TrainingDummyService.luau now spawns one
-- additional Studio-only dummy at this scene's configured DummyMarker point
-- (see that file), reusing its existing spawnDummy/CombatNPC/death-respawn
-- path unchanged. This service still only creates an informational
-- "TrainingDummyMarker" anchor Part (NOT one of the three CollectionService
-- tags TrainingGroundService listens for, and not attackable by itself) so
-- the marker position is visible/inspectable in Explorer independent of
-- whether a dummy happens to be spawned there in the current environment.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TrainingSceneConfig = require(ReplicatedStorage.Shared.Combat.TrainingSceneConfig)
local TrainingSceneRepair = require(ReplicatedStorage.Shared.Combat.TrainingSceneRepair)

local TrainingSceneBootstrap = {
	Priority = 15, -- after CombatService (0) / TrainingDummyService (10), before TrainingGroundService (20)
}

local function vec(v: TrainingSceneConfig.Vec3): Vector3
	return Vector3.new(v.X, v.Y, v.Z)
end

-- Declarative spec for every child this service owns inside the container.
-- Walkway and platform positions use restingCenterY so their tops stay at
-- ground level. The three role markers use roleMarkerVolume so they stand
-- on that surface instead of being embedded in it. Colors are placeholder
-- only, so a tester can tell the volumes apart.
type ChildSpec = {
	Name: string,
	Position: Vector3,
	Size: Vector3,
	Color: Color3,
	CanCollide: boolean,
	CanTouch: boolean,
	Transparency: number,
	Tag: string?, -- scene role this part must carry; nil strips all three roles
	Attributes: { [string]: any }?,
}

local function buildChildSpecs(points: any): { ChildSpec }
	local platformSize = vec(TrainingSceneConfig.Platform.Size)
	local walkwaySize = vec(TrainingSceneConfig.Walkway.Size)
	local surfaceTopY = TrainingSceneConfig.restingCenterY(
		TrainingSceneConfig.GroundLevelY,
		TrainingSceneConfig.Walkway.Size.Y
	) + TrainingSceneConfig.Walkway.Size.Y / 2
	local roleVolume = TrainingSceneConfig.roleMarkerVolume(surfaceTopY)
	local roleSize = vec(roleVolume.size)

	local function rolePosition(point: { X: number, Z: number }): Vector3
		return Vector3.new(point.X, roleVolume.centerY, point.Z)
	end

	return {
		{
			Name = "TrainingWalkway",
			Position = Vector3.new(
				points.WalkwayCenter.X,
				TrainingSceneConfig.restingCenterY(TrainingSceneConfig.GroundLevelY, TrainingSceneConfig.Walkway.Size.Y),
				points.WalkwayCenter.Z
			),
			Size = walkwaySize,
			Color = Color3.fromRGB(110, 110, 110),
			CanCollide = true,
			CanTouch = true,
			Transparency = 0,
		},
		{
			Name = "TrainingPlatform",
			Position = Vector3.new(
				points.Origin.X,
				TrainingSceneConfig.restingCenterY(TrainingSceneConfig.GroundLevelY, TrainingSceneConfig.Platform.Size.Y),
				points.Origin.Z
			),
			Size = platformSize,
			Color = Color3.fromRGB(120, 120, 130),
			CanCollide = true,
			CanTouch = true,
			Transparency = 0,
		},
		{
			Name = "TrainingEntrancePad",
			Position = rolePosition(points.Entrance),
			Size = roleSize,
			Color = Color3.fromRGB(70, 170, 90),
			CanCollide = roleVolume.canCollide,
			CanTouch = roleVolume.canTouch,
			Transparency = roleVolume.transparency,
			Tag = "TrainingEntrance",
		},
		{
			Name = "TrainingExitPad",
			Position = rolePosition(points.Exit),
			Size = roleSize,
			Color = Color3.fromRGB(170, 90, 70),
			CanCollide = roleVolume.canCollide,
			CanTouch = roleVolume.canTouch,
			Transparency = roleVolume.transparency,
			Tag = "TrainingExit",
		},
		{
			Name = "TrainingReturnSpawnPad",
			Position = rolePosition(points.ReturnSpawn),
			Size = roleSize,
			Color = Color3.fromRGB(90, 120, 170),
			CanCollide = roleVolume.canCollide,
			CanTouch = roleVolume.canTouch,
			Transparency = roleVolume.transparency,
			Tag = "TrainingReturnSpawn",
		},
		{
			Name = "TrainingDummyMarker",
			Position = Vector3.new(
				points.DummyMarker.X,
				TrainingSceneConfig.restingCenterY(TrainingSceneConfig.GroundLevelY, 0.2),
				points.DummyMarker.Z
			),
			Size = Vector3.new(3, 0.2, 3),
			Color = Color3.fromRGB(200, 170, 60),
			CanCollide = false,
			CanTouch = true,
			Transparency = 0,
			Attributes = { Purpose = "ReservedForStationaryDummy" },
		},
	}
end

-- Finds the owned container (Name + TrainingScene attribute), or creates it
-- fresh if absent. If a same-named instance exists WITHOUT the owning
-- attribute, it is an unknown user object: never touched, and this function
-- returns nil (caller aborts the whole bootstrap for safety).
local function findOrCreateOwnedContainer(): Folder?
	local existing = Workspace:FindFirstChild(TrainingSceneConfig.ContainerName)
	if existing then
		if existing:IsA("Folder") and existing:GetAttribute("TrainingScene") == true then
			return existing
		end
		warn(
			`[Combat] Training scene bootstrap found an existing "{TrainingSceneConfig.ContainerName}" that is not `
				.. `an owned TrainingScene container (class={existing.ClassName}); leaving it untouched and skipping `
				.. `scene bootstrap. Rename/remove the conflicting object to allow bootstrap to run.`
		)
		return nil
	end

	local container = Instance.new("Folder")
	container.Name = TrainingSceneConfig.ContainerName
	container:SetAttribute("TrainingScene", true)
	container:SetAttribute("SceneVersion", TrainingSceneConfig.SceneVersion)
	container:SetAttribute("Placeholder", true)
	container.Parent = Workspace
	return container
end

local function applyPartSettings(part: BasePart, spec: ChildSpec)
	part.Anchored = true
	part.CanCollide = spec.CanCollide
	part.CanTouch = spec.CanTouch
	part.Transparency = spec.Transparency
	part.Size = spec.Size
	part.Position = spec.Position
	part.Color = spec.Color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("TrainingSceneOwned", true)

	if spec.Attributes then
		for key, value in spec.Attributes do
			part:SetAttribute(key, value)
		end
	end

	-- Remove stale scene roles before adding the expected one. AddTag and
	-- RemoveTag are idempotent, so a second Start() does not duplicate tags.
	local plan = TrainingSceneRepair.reconcileRoleTags(CollectionService:GetTags(part), spec.Tag)
	for _, tag in plan.remove do
		CollectionService:RemoveTag(part, tag)
	end
	for _, tag in plan.add do
		CollectionService:AddTag(part, tag)
	end
end

-- Ensures exactly one child matching `spec` exists directly under
-- `container`. The repair action comes from TrainingSceneRepair so the
-- Part policy and warning reason can be tested without Instances.
local function ensureChild(container: Folder, spec: ChildSpec)
	local existing = container:FindFirstChild(spec.Name)
	local state: TrainingSceneRepair.ChildState? = nil
	if existing ~= nil then
		state = {
			className = existing.ClassName,
			owned = existing:GetAttribute("TrainingSceneOwned") == true,
		}
	end

	local decision = TrainingSceneRepair.decideChildRepair(spec.Name, container.Name, state)
	local action: TrainingSceneRepair.RepairAction = decision.action
	if action == "skip" then
		warn(decision.warning)
		return
	elseif action == "replace" then
		warn(decision.warning)
		if existing ~= nil then
			existing:Destroy()
		end
		existing = nil
	elseif action == "create" or action == "repair" then
		-- Create and in-place repair share the settings application below.
	else
		local unhandled: never = action
		error(`unhandled training scene child repair action "{unhandled}"`)
	end

	local part: BasePart
	if existing == nil then
		local created = Instance.new("Part")
		created.Name = spec.Name
		created.Parent = container
		part = created
	else
		part = existing :: BasePart
	end
	applyPartSettings(part, spec)
end

function TrainingSceneBootstrap:Init(_registry)
	-- No dependency on other services: this is pure geometry creation and
	-- must not require CombatService/TrainingGroundService to avoid any
	-- ordering coupling beyond Priority (which only controls Start order).
end

function TrainingSceneBootstrap:Start()
	local container = findOrCreateOwnedContainer()
	if container == nil then
		return
	end

	-- Keep attributes in sync even on an owned container from a prior
	-- boot/version (repair, not just create-once).
	container:SetAttribute("TrainingScene", true)
	container:SetAttribute("SceneVersion", TrainingSceneConfig.SceneVersion)
	container:SetAttribute("Placeholder", true)

	local points = TrainingSceneConfig.resolve()
	for _, spec in buildChildSpecs(points) do
		ensureChild(container, spec)
	end

	print(`[Combat] Training scene bootstrap ensured "{TrainingSceneConfig.ContainerName}" placeholder geometry`)
end

return TrainingSceneBootstrap
