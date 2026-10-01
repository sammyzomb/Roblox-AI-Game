--!strict
-- Task #23 increment: training-scene-bootstrap.
--
-- Creates the smallest server-authored placeholder scene needed for the
-- training ground to be enterable in a FRESH Studio place with no manual
-- level-authoring: a platform, an entrance part tagged "TrainingEntrance",
-- an exit part tagged "TrainingExit", and a return-spawn part tagged
-- "TrainingReturnSpawn" (the exact CollectionService tags
-- TrainingGroundService.luau already listens for — see that file's header).
--
-- This service owns ONLY geometry creation/idempotency. It does not
-- duplicate any combat, lifecycle, ruleset, or session logic: once the
-- tagged parts exist, TrainingGroundService's existing CollectionService
-- hookup (Start()) does the rest, unchanged.
--
-- Idempotency: all geometry lives under one named Folder
-- (TrainingSceneConfig.ContainerName) directly in Workspace. If that folder
-- already exists when :Start() runs, this service does nothing further -
-- no duplicate parts, no duplicate tags, no duplicate connections are ever
-- created on a second boot (e.g. a server restart that did not wipe
-- Workspace, or this service's :Start() somehow running twice in one
-- process). This is a plain existence check, not a signal/connection, so
-- there is nothing to double-connect.
--
-- Placeholder-only: parts are plain gray/neutral BaseParts with deterministic
-- Names and Attributes (see below), anchored, non-collaped. No materials,
-- meshes, decals, or other art pass are included, per the assignment's
-- "no art polish or external assets" instruction.
--
-- Dummy reuse (assignment item 3): TrainingDummyService.luau (inspected for
-- this increment) only spawns its Studio-only dummies from a hardcoded
-- Workspace-relative DUMMIES position list inside its own :Start(), gated
-- behind RunService:IsStudio(), with no public method to add/relocate a
-- dummy at an arbitrary world position. It cannot be safely "pointed at"
-- this scene's DummyMarker without editing that service's own DUMMIES table
-- (which would be scene/content work, not bootstrap-layer work, and risks
-- scope creep into a second combat/dummy system if done incorrectly). This
-- increment therefore only reserves and tags a marker Part
-- ("TrainingDummyMarker", informational attribute only, NOT one of the three
-- CollectionService tags TrainingGroundService listens for) at
-- TrainingSceneConfig.DummyMarkerOffset, and documents the exact missing
-- API in docs/TRAINING_SMOKE_TEST.md instead of forking dummy spawning
-- logic here. No dummy Model is created by this service.

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

local function makePart(name: string, position: Vector3, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Thin marker parts (entrance/exit/return-spawn) are small, walkable, and
-- visually distinct placeholder colors only so a tester can find them;
-- not an art deliverable.
local MARKER_SIZE = Vector3.new(6, 1, 6)

function TrainingSceneBootstrap:Init(_registry)
	-- No dependency on other services: this is pure geometry creation and
	-- must not require CombatService/TrainingGroundService to avoid any
	-- ordering coupling beyond Priority (which only controls Start order).
end

function TrainingSceneBootstrap:Start()
	if Workspace:FindFirstChild(TrainingSceneConfig.ContainerName) then
		-- Idempotent: scene already created by a previous boot in this
		-- Workspace. Do not recreate or re-tag anything.
		return
	end

	local points = TrainingSceneConfig.resolve()

	local container = Instance.new("Folder")
	container.Name = TrainingSceneConfig.ContainerName
	container:SetAttribute("SceneVersion", TrainingSceneConfig.SceneVersion)
	container:SetAttribute("Placeholder", true)

	local platform = makePart(
		"TrainingPlatform",
		vec(points.Origin) - Vector3.new(0, TrainingSceneConfig.Platform.Size.Y / 2, 0),
		vec(TrainingSceneConfig.Platform.Size),
		Color3.fromRGB(120, 120, 130)
	)
	platform.Parent = container

	local entrance = makePart("TrainingEntrancePad", vec(points.Entrance), MARKER_SIZE, Color3.fromRGB(70, 170, 90))
	entrance.Parent = container
	CollectionService:AddTag(entrance, "TrainingEntrance")

	local exitPad = makePart("TrainingExitPad", vec(points.Exit), MARKER_SIZE, Color3.fromRGB(170, 90, 70))
	exitPad.Parent = container
	CollectionService:AddTag(exitPad, "TrainingExit")

	local returnSpawn = makePart(
		"TrainingReturnSpawnPad",
		vec(points.ReturnSpawn),
		MARKER_SIZE,
		Color3.fromRGB(90, 120, 170)
	)
	returnSpawn.Parent = container
	CollectionService:AddTag(returnSpawn, "TrainingReturnSpawn")

	-- Informational-only marker: NOT one of TrainingGroundService's tags.
	-- See this file's header ("Dummy reuse") for why no dummy is spawned
	-- here yet.
	local dummyMarker = makePart(
		"TrainingDummyMarker",
		vec(points.DummyMarker),
		Vector3.new(3, 0.2, 3),
		Color3.fromRGB(200, 170, 60)
	)
	dummyMarker.CanCollide = false
	dummyMarker:SetAttribute("Purpose", "ReservedForStationaryDummy")
	dummyMarker.Parent = container

	container.Parent = Workspace
	print(`[Combat] Training scene bootstrap created "{TrainingSceneConfig.ContainerName}" placeholder geometry`)
end

return TrainingSceneBootstrap
