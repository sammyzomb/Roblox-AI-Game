--!strict
-- Task #23 increment: training-scene-bootstrap.
--
-- Pure (Roblox-API-free) placement/sizing constants and helpers for the
-- server-authored placeholder training scene. Kept separate from the
-- service that actually creates Instances so the geometry math (does the
-- platform overlap the default spawn? where do the three tagged parts sit
-- relative to each other?) can be unit tested without any Roblox services.
--
-- ALL NUMBERS HERE ARE AN EXPLICITLY MARKED DEV/PLACEHOLDER CONFIGURATION,
-- not an approved layout or art pass. per the pinned scope doc
-- ("未決參數使用明確標示的開發配置, 不能當成發布決策"), nothing here may be
-- read as a finalized balance or art decision. This only exists so a fresh
-- Studio place has *something* enterable without manual level-authoring.
--
-- Placement rationale (conservative, no overlap with default spawn):
--   Default Roblox `SpawnLocation` placement for a fresh baseplate-style
--   place is near the world origin. This scene is offset well away on the
--   X axis (see Origin below) so it can never overlap a default spawn part
--   regardless of that part's exact footprint, while still being a short,
--   obvious walk from it for a single-player Studio smoke test.

export type Vec3 = { X: number, Y: number, Z: number }

local TrainingSceneConfig = {}

-- Root container name in Workspace. Also used by the bootstrap service as
-- the idempotency marker: if this Folder already exists, no part is
-- recreated.
TrainingSceneConfig.ContainerName = "TrainingGroundScene"

-- Attribute written to the container so repeated server starts (and a
-- human inspecting the place) can see which config version produced it
-- without guessing from geometry.
TrainingSceneConfig.SceneVersion = 1

-- Center of the whole placeholder scene, offset away from world origin so
-- it cannot overlap a default SpawnLocation placed near (0, Y, 0).
TrainingSceneConfig.Origin = { X = 250, Y = 10, Z = 0 } :: Vec3

TrainingSceneConfig.Platform = {
	Size = { X = 60, Y = 2, Z = 60 } :: Vec3,
	-- Platform top sits at Origin.Y; the part itself is centered half its
	-- height below that so players standing on it stand at Origin.Y.
}

-- Entrance / exit / return-spawn are simple deterministic offsets from
-- Origin, all within the platform footprint (60x60) with margin.
TrainingSceneConfig.EntranceOffset = { X = -20, Y = 1, Z = 0 } :: Vec3
TrainingSceneConfig.ExitOffset = { X = 20, Y = 1, Z = 0 } :: Vec3
-- Return spawn is deliberately OUTSIDE the platform footprint (back toward
-- world origin) so exiting visibly returns the player to "the world" and
-- never re-lands them on the training platform itself.
TrainingSceneConfig.ReturnSpawnOffset = { X = -40, Y = 1, Z = 0 } :: Vec3

-- One stationary dummy marker point, used only to validate/park a tagged
-- CombatNPC if TrainingDummyService (or a future variant) can be bootstrapped
-- onto it. See TrainingSceneBootstrap.luau header for why this increment
-- does not itself spawn a dummy here.
TrainingSceneConfig.DummyMarkerOffset = { X = 0, Y = 1, Z = 20 } :: Vec3

local function add(a: Vec3, b: Vec3): Vec3
	return { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }
end

-- Resolves every named point as an absolute position, given the configured
-- Origin. Exposed as a pure function (no Instance creation) so tests can
-- assert exact coordinates and non-overlap without Roblox.
function TrainingSceneConfig.resolve(origin: Vec3?)
	local o = origin or TrainingSceneConfig.Origin
	return {
		Origin = o,
		Entrance = add(o, TrainingSceneConfig.EntranceOffset),
		Exit = add(o, TrainingSceneConfig.ExitOffset),
		ReturnSpawn = add(o, TrainingSceneConfig.ReturnSpawnOffset),
		DummyMarker = add(o, TrainingSceneConfig.DummyMarkerOffset),
	}
end

-- True if `point` falls within the horizontal (X/Z) footprint of an
-- axis-aligned box centered at `boxCenter` with the given full `boxSize`.
-- Used by tests to assert the configured points stay clear of a
-- representative default spawn footprint, and to assert the three tagged
-- points stay within (or deliberately outside, for ReturnSpawn) the
-- platform footprint.
function TrainingSceneConfig.pointInsideBox(point: Vec3, boxCenter: Vec3, boxSize: Vec3): boolean
	return math.abs(point.X - boxCenter.X) <= boxSize.X / 2
		and math.abs(point.Z - boxCenter.Z) <= boxSize.Z / 2
end

return TrainingSceneConfig
