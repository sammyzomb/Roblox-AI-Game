--!strict
-- Task #23 increment: fix-training-scene-reachability-ensure-dummy.
--
-- Pure (Roblox-API-free) placement/sizing constants and helpers for the
-- server-authored placeholder training scene. Kept separate from the
-- service that actually creates Instances so the geometry math (does the
-- walkway reach the platform without a gap? does any point overlap the
-- default spawn footprint? what is each part's resting Y given its own
-- half-height?) can be unit tested without any Roblox services.
--
-- ALL NUMBERS HERE ARE AN EXPLICITLY MARKED DEV/PLACEHOLDER CONFIGURATION,
-- not an approved layout or art pass, per the pinned scope doc ("未決參數
-- 使用明確標示的開發配置, 不能當成發布決策").
--
-- Reachability correction (this increment): the prior layout put the whole
-- scene on a platform raised to Y=10 with nothing connecting it to a fresh
-- Baseplate's ground level (Y=0), so reaching it required a jump/teleport
-- that is not "ordinary walking" from a default spawn. This revision keeps
-- EVERYTHING — walkway, platform top, every marker part's walkable surface —
-- at one shared ground level (`GroundLevelY`), so an ordinary R15/R6
-- Humanoid can walk the entire path with zero steps/gaps/jumps. A
-- `Walkway` strip explicitly spans from near world origin (reachable by
-- walking off a default SpawnLocation) to the platform edge, with enough
-- overlap into the platform footprint that there is no seam.
--
-- Part resting math: for any part of full height `size.Y` whose TOP surface
-- must sit at ground level `y`, the part's CENTER must be at
-- `y - size.Y / 2` (a half-height below the desired top surface). All
-- offsets below are expressed as the desired FOOT/STANDING Y (ground
-- level), and `restingCenterY` performs that half-height conversion so
-- callers never hand-subtract it inconsistently.

export type Vec3 = { X: number, Y: number, Z: number }

local TrainingSceneConfig = {}

-- Root container name in Workspace. Also the attribute-owned identity
-- marker: the bootstrap service finds-or-creates a Folder with this Name
-- AND the `TrainingScene = true` attribute (see TrainingSceneBootstrap),
-- rather than trusting Name alone.
TrainingSceneConfig.ContainerName = "TrainingGroundScene"

-- Attribute written to the container so repeated server starts (and a
-- human inspecting the place) can see which config version produced it.
-- Version 3 raises the three role markers into above-surface touch volumes.
TrainingSceneConfig.SceneVersion = 3

-- Shared ground level every walkable surface in this scene sits at. A
-- fresh Baseplate's top surface and a default SpawnLocation's standing
-- surface are both Y=0; keeping the whole training path at the same Y
-- means no jump, ramp, or teleport is ever required to reach it.
TrainingSceneConfig.GroundLevelY = 0

-- Center of the training platform proper, offset away from world origin on
-- X only (Z=0, same as a default spawn's typical Z) so the whole scene can
-- be reached by walking in a straight line, while staying far enough away
-- that its footprint cannot overlap a default SpawnLocation regardless of
-- that part's exact size.
TrainingSceneConfig.Origin = { X = 120, Y = TrainingSceneConfig.GroundLevelY, Z = 0 } :: Vec3

TrainingSceneConfig.Platform = {
	Size = { X = 60, Y = 2, Z = 60 } :: Vec3,
}

-- Walkway: a long, flat strip connecting world origin's walkable area to the
-- platform, at the same ground level. Centered halfway between X=0 and the
-- platform's near edge, wide enough to comfortably walk without sidestepping
-- off the edge. Its far end deliberately overlaps a few studs into the
-- platform footprint so there is no seam/gap between the two parts.
TrainingSceneConfig.Walkway = {
	Size = { X = TrainingSceneConfig.Origin.X - TrainingSceneConfig.Platform.Size.X / 2 + 6, Y = 1, Z = 10 } :: Vec3,
}
-- Walkway part is centered between X=0 and the platform edge (minus a small
-- overlap margin so it is pulled slightly toward the platform, guaranteeing
-- overlap rather than relying on exact edge math).
TrainingSceneConfig.WalkwayCenterOffset = {
	X = -(TrainingSceneConfig.Platform.Size.X / 2 + (TrainingSceneConfig.Walkway.Size.X / 2) - 6),
	Y = 0,
	Z = 0,
} :: Vec3

-- Entrance / exit are simple deterministic offsets from Origin, within the
-- platform footprint (60x60) with margin. Their Y remains the walk-surface
-- stand point. The trigger volume that sits on that point is RoleMarker,
-- not an embedded copy of the walkway.
TrainingSceneConfig.EntranceOffset = { X = -20, Y = 0, Z = 0 } :: Vec3
TrainingSceneConfig.ExitOffset = { X = 20, Y = 0, Z = 0 } :: Vec3

-- Visible non-colliding touch volume for TrainingEntrance, TrainingExit,
-- and TrainingReturnSpawn. The bottom rests on the walkable surface and the
-- top is above it, so the pad is no longer buried inside the walkway or
-- platform. Horizontal size stays 6x6. CanCollide stays false so the walkway
-- and platform remain the ordinary walking surfaces.
TrainingSceneConfig.RoleMarker = {
	Size = { X = 6, Y = 1, Z = 6 } :: Vec3,
	CanCollide = false,
	CanTouch = true,
	Transparency = 0,
}

-- Return spawn sits on the WORLD-SIDE walkway, near (but not overlapping)
-- default spawn, at the same ground level — never on the training platform
-- and never floating in training-local air. It is placed close to X=0 (a
-- few studs out along the walkway toward the platform) so exiting visibly
-- returns the player toward "the world" without landing back inside the
-- default spawn's own footprint.
TrainingSceneConfig.ReturnSpawnOffset = { X = -(TrainingSceneConfig.Origin.X - 12), Y = 0, Z = 0 } :: Vec3

-- One stationary dummy marker/point, used both as a debug anchor and (this
-- increment) as the actual position TrainingDummyService spawns its
-- Studio-only scene dummy at. See TrainingSceneBootstrap.luau and
-- TrainingDummyService.luau for the exact split of responsibility: this
-- module only exposes the pure point, it creates no Instance and spawns no
-- combatant.
TrainingSceneConfig.DummyMarkerOffset = { X = 0, Y = 0, Z = 20 } :: Vec3

local function add(a: Vec3, b: Vec3): Vec3
	return { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }
end

-- Converts a desired standing/top-surface Y and a part's full height into
-- the Y the part's CENTER must be placed at so its top surface rests
-- exactly at `standY`. Exposed so both the bootstrap service and tests
-- share one half-height formula instead of re-deriving it inconsistently.
function TrainingSceneConfig.restingCenterY(standY: number, fullHeightY: number): number
	return standY - fullHeightY / 2
end

export type RoleMarkerVolume = {
	centerY: number,
	bottom: number,
	top: number,
	size: Vec3,
	canCollide: boolean,
	canTouch: boolean,
	transparency: number,
}

-- Places a role-marker volume on a walkable surface. `surfaceTopY` is the
-- top of the part the character actually walks on (walkway or platform).
-- The volume's bottom is that surface, so it is not embedded below it.
function TrainingSceneConfig.roleMarkerVolume(surfaceTopY: number): RoleMarkerVolume
	local marker = TrainingSceneConfig.RoleMarker
	local height = marker.Size.Y
	local bottom = surfaceTopY
	local top = surfaceTopY + height
	return {
		centerY = bottom + height / 2,
		bottom = bottom,
		top = top,
		size = marker.Size,
		canCollide = marker.CanCollide,
		canTouch = marker.CanTouch,
		transparency = marker.Transparency,
	}
end

-- Resolves every named point as an absolute STANDING position (i.e. the
-- walkable surface Y, not any part's center), given the configured Origin.
-- Exposed as a pure function (no Instance creation) so tests can assert
-- exact coordinates, ground-level consistency, and non-overlap without
-- Roblox.
function TrainingSceneConfig.resolve(origin: Vec3?)
	local o = origin or TrainingSceneConfig.Origin
	local walkwayCenter = add(o, TrainingSceneConfig.WalkwayCenterOffset)
	return {
		Origin = o,
		Entrance = add(o, TrainingSceneConfig.EntranceOffset),
		Exit = add(o, TrainingSceneConfig.ExitOffset),
		ReturnSpawn = add(o, TrainingSceneConfig.ReturnSpawnOffset),
		DummyMarker = add(o, TrainingSceneConfig.DummyMarkerOffset),
		WalkwayCenter = walkwayCenter,
	}
end

-- True if `point` falls within the horizontal (X/Z) footprint of an
-- axis-aligned box centered at `boxCenter` with the given full `boxSize`.
function TrainingSceneConfig.pointInsideBox(point: Vec3, boxCenter: Vec3, boxSize: Vec3): boolean
	return math.abs(point.X - boxCenter.X) <= boxSize.X / 2
		and math.abs(point.Z - boxCenter.Z) <= boxSize.Z / 2
end

-- True if two axis-aligned horizontal (X/Z) boxes overlap at all (used to
-- assert the walkway and platform footprints actually touch/overlap, i.e.
-- there is no gap a player would have to jump across).
function TrainingSceneConfig.boxesOverlap(centerA: Vec3, sizeA: Vec3, centerB: Vec3, sizeB: Vec3): boolean
	local overlapX = math.abs(centerA.X - centerB.X) <= (sizeA.X + sizeB.X) / 2
	local overlapZ = math.abs(centerA.Z - centerB.Z) <= (sizeA.Z + sizeB.Z) / 2
	return overlapX and overlapZ
end

return TrainingSceneConfig
