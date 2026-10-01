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
--      required child part is ensured individually by deterministic Name:
--      if missing, it is created; if present AND owned (see below), its
--      class/anchoring/collision/size/position/attributes/tag are repaired
--      in place; if present but NOT owned (e.g. a user renamed a plain Part
--      into the container with a colliding Name), it is left untouched and
--      a warning is printed, exactly like the container-level collision
--      case. "Owned" for a child means the instance has the
--      `TrainingSceneOwned = true` attribute this service itself sets - so a
--      child this service created on a previous boot is always safely
--      repairable, while anything else is never touched.
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

local TrainingSceneBootstrap = {
	Priority = 15, -- after CombatService (0) / TrainingDummyService (10), before TrainingGroundService (20)
}

local function vec(v: TrainingSceneConfig.Vec3): Vector3
	return Vector3.new(v.X, v.Y, v.Z)
end

-- Thin marker parts (entrance/exit/return-spawn) are small, walkable, and
-- visually distinct placeholder colors only so a tester can find them; not
-- an art deliverable.
local MARKER_SIZE = Vector3.new(6, 1, 6)

-- Declarative spec for every child this service owns inside the container.
-- `standY` is the desired WALKABLE surface Y (ground level for that point);
-- the actual Part center Y is derived via TrainingSceneConfig.restingCenterY
-- so every part models its own half-height correctly instead of repeating
-- ad-hoc `- size.Y/2` arithmetic per call site.
type ChildSpec = {
	Name: string,
	Position: Vector3, -- standing-surface position (X/Z exact, Y = standY)
	Size: Vector3,
	Color: Color3,
	CanCollide: boolean,
	Tag: string?, -- CollectionService tag this part must carry, if any
	Attributes: { [string]: any }?,
}

local function buildChildSpecs(points: any): { ChildSpec }
	local platformSize = vec(TrainingSceneConfig.Platform.Size)
	local walkwaySize = vec(TrainingSceneConfig.Walkway.Size)

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
		},
		{
			Name = "TrainingEntrancePad",
			Position = Vector3.new(
				points.Entrance.X,
				TrainingSceneConfig.restingCenterY(TrainingSceneConfig.GroundLevelY, MARKER_SIZE.Y),
				points.Entrance.Z
			),
			Size = MARKER_SIZE,
			Color = Color3.fromRGB(70, 170, 90),
			CanCollide = true,
			Tag = "TrainingEntrance",
		},
		{
			Name = "TrainingExitPad",
			Position = Vector3.new(
				points.Exit.X,
				TrainingSceneConfig.restingCenterY(TrainingSceneConfig.GroundLevelY, MARKER_SIZE.Y),
				points.Exit.Z
			),
			Size = MARKER_SIZE,
			Color = Color3.fromRGB(170, 90, 70),
			CanCollide = true,
			Tag = "TrainingExit",
		},
		{
			Name = "TrainingReturnSpawnPad",
			Position = Vector3.new(
				points.ReturnSpawn.X,
				TrainingSceneConfig.restingCenterY(TrainingSceneConfig.GroundLevelY, MARKER_SIZE.Y),
				points.ReturnSpawn.Z
			),
			Size = MARKER_SIZE,
			Color = Color3.fromRGB(90, 120, 170),
			CanCollide = true,
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

-- Ensures exactly one child matching `spec` exists directly under
-- `container`: creates it if missing, repairs it in place if present and
-- owned, or leaves an unknown same-name object alone with a warning.
local function ensureChild(container: Folder, spec: ChildSpec)
	local existing = container:FindFirstChild(spec.Name)
	local part: BasePart

	if existing == nil then
		part = Instance.new("Part")
		part.Name = spec.Name
		part:SetAttribute("TrainingSceneOwned", true)
		part.Parent = container
	elseif existing:IsA("BasePart") and existing:GetAttribute("TrainingSceneOwned") == true then
		part = existing
	else
		warn(
			`[Combat] Training scene bootstrap found an unowned object named "{spec.Name}" under `
				.. `{TrainingSceneConfig.ContainerName}; leaving it unchanged and skipping repair for this child.`
		)
		return
	end

	part.Anchored = true
	part.CanCollide = spec.CanCollide
	part.Size = spec.Size
	part.Position = spec.Position
	part.Color = spec.Color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	if spec.Attributes then
		for key, value in spec.Attributes do
			part:SetAttribute(key, value)
		end
	end

	if spec.Tag then
		-- AddTag is itself idempotent (adding an already-present tag is a
		-- no-op), so repeated Start() calls never create duplicate tags.
		CollectionService:AddTag(part, spec.Tag)
	end
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
