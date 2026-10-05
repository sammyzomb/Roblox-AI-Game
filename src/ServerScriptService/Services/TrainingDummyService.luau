--!strict
-- Studio-only test aid: spawns PvE training dummies so combat can be tried
-- immediately after `rojo serve`. Dummies are ordinary tagged NPCs (see
-- CombatService "CombatNPC" tag), so this also shows how PvE enemies plug in.
-- Does nothing in live servers.
--
-- The three DUMMIES below stay passive. Only the designated scene dummy
-- (TrainingSceneConfig DummyMarker, training_sword) periodically faces one
-- nearby training player and calls CombatService:RequestAttack. Cadence and
-- eligibility live in TrainingAttacker. Death uses the existing respawn
-- path; the replacement becomes the only practice attacker.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TrainingAttacker = require(ReplicatedStorage.Shared.Combat.TrainingAttacker)
local TrainingSceneConfig = require(ReplicatedStorage.Shared.Combat.TrainingSceneConfig)

local TrainingDummyService = {
	Priority = 10, -- after CombatService
}

type DummySpec = {
	Position: Vector3,
	Level: number,
	Weapon: string,
	PracticeAttacker: boolean?,
}

-- Position, level and weapon of each passive dummy. Level 1 = weak, level 20 = armored.
local DUMMIES: { DummySpec } = {
	{ Position = Vector3.new(12, 3, -16), Level = 1, Weapon = "training_sword" },
	{ Position = Vector3.new(-12, 3, -16), Level = 10, Weapon = "wooden_shield" },
	{ Position = Vector3.new(0, 3, -30), Level = 20, Weapon = "tower_shield" },
}

-- Task #23 increment (fix-training-scene-reachability-ensure-dummy): one
-- additional dummy positioned at TrainingSceneConfig's own DummyMarker
-- point, so the bootstrap-created training scene (TrainingSceneBootstrap)
-- has at least one Studio dummy actually standing on its reserved marker,
-- instead of only reserving an empty anchor part. This reuses the exact
-- same spawnDummy/CombatNPC/death-respawn path below as every other
-- dummy - no second dummy/combat system, and still gated by
-- RunService:IsStudio() like the rest of this service. A small Y offset
-- (+3) matches the other DUMMIES entries' stand-height above their own
-- ground-level marker/position.
--
-- CURSOR-TRAINING-020: this marker dummy is the only practice attacker.
local function sceneDummySpec(): DummySpec
	local marker = TrainingSceneConfig.resolve().DummyMarker
	return {
		Position = Vector3.new(marker.X, marker.Y + 3, marker.Z),
		Level = 1,
		Weapon = "training_sword",
		PracticeAttacker = true,
	}
end

local RESPAWN_SECONDS = 3

local combat: any
local training: any
local practiceState: TrainingAttacker.State = TrainingAttacker.initial(0)
local practiceModel: Model? = nil
local practiceConnected = false

local function spawnDummy(spec: DummySpec)
	local model = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	model.Name = `TrainingDummy_L{spec.Level}`
	model:PivotTo(CFrame.new(spec.Position) * CFrame.Angles(0, math.pi, 0))
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.BreakJointsOnDeath = false
	if spec.PracticeAttacker == true then
		-- Keep the horizontal facing set just before RequestAttack through
		-- the sword windup. The dummy still does not walk or chase.
		humanoid.AutoRotate = false
	end
	model:SetAttribute("Level", spec.Level)
	model:SetAttribute("Weapon", spec.Weapon)
	model.Parent = Workspace
	CollectionService:AddTag(model, "CombatNPC")
	return model
end

local function bindPracticeAttacker(model: Model)
	practiceModel = model
	practiceState = TrainingAttacker.adopt(practiceState, model, os.clock())
end

local function clearPracticeAttacker(model: Model)
	practiceState = TrainingAttacker.retire(practiceState, model)
	if practiceModel == model then
		practiceModel = nil
	end
end

local function attackerView(model: Model): (boolean, TrainingAttacker.Vec3?)
	if model.Parent == nil then
		return false, nil
	end
	local combatant = combat:GetCombatant(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false, nil
	end
	local position = root.Position
	return combatant ~= nil and combatant.Alive == true, {
		X = position.X,
		Y = position.Y,
		Z = position.Z,
	}
end

local function practiceCandidates(): { TrainingAttacker.Candidate }
	local candidates: { TrainingAttacker.Candidate } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local combatant = if character then combat:GetCombatant(character) else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local rootPosition: TrainingAttacker.Vec3? = nil
		if root ~= nil and root:IsA("BasePart") then
			local position = root.Position
			rootPosition = { X = position.X, Y = position.Y, Z = position.Z }
		end
		table.insert(candidates, {
			Id = player,
			TieKey = tostring(player.UserId),
			Training = training:IsTraining(player),
			Registered = combatant ~= nil,
			Alive = combatant ~= nil and combatant.Alive == true,
			Root = rootPosition,
		})
	end
	return candidates
end

local function faceHorizontally(model: Model, aim: TrainingAttacker.Vec3): boolean
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	local flatTarget = Vector3.new(aim.X, root.Position.Y, aim.Z)
	if (flatTarget - root.Position).Magnitude < 1e-3 then
		return true
	end
	model:PivotTo(CFrame.lookAt(root.Position, flatTarget))
	return true
end

local function onPracticeHeartbeat()
	local model = practiceModel
	if model == nil then
		return
	end
	-- AttackerId is an opaque identity. Compare it as unknown so the
	-- Model on this side is not checked against a different metatable.
	local attackerId: unknown = model
	if practiceState.AttackerId ~= attackerId then
		return
	end
	local now = os.clock()
	if not TrainingAttacker.isDue(practiceState, attackerId, now) then
		return
	end
	local alive, origin = attackerView(model)
	local decision, nextState = TrainingAttacker.step(practiceState, {
		Now = now,
		AttackerId = attackerId,
		AttackerAlive = alive,
		Origin = origin,
		Candidates = practiceCandidates(),
	})
	practiceState = nextState
	local action: TrainingAttacker.Action = decision.Action
	if action == "Attack" then
		local aim = decision.Aim
		if aim == nil or model.Parent == nil then
			return
		end
		if not faceHorizontally(model, aim) then
			return
		end
		-- The due time was already advanced. A core rejection must not
		-- swing again before the next development interval.
		combat:RequestAttack(model, "MainHand", "Primary", Vector3.new(aim.X, aim.Y, aim.Z))
	elseif action == "Wait" or action == "Skip" or action == "Inactive" then
		return
	else
		local unhandled: never = action
		error(`unhandled training attacker action "{unhandled}"`)
	end
end

local function startPracticeLoop()
	if practiceConnected then
		return
	end
	practiceConnected = true
	RunService.Heartbeat:Connect(onPracticeHeartbeat)
end

function TrainingDummyService:Init(registry)
	combat = registry.CombatService
	training = registry.TrainingGroundService
end

function TrainingDummyService:Start()
	if not RunService:IsStudio() then
		return
	end
	local specByModel: { [Model]: DummySpec } = {}
	for _, spec in DUMMIES do
		specByModel[spawnDummy(spec)] = spec
	end
	local sceneSpec = sceneDummySpec()
	local sceneModel = spawnDummy(sceneSpec)
	specByModel[sceneModel] = sceneSpec
	bindPracticeAttacker(sceneModel)
	combat.Killed:Connect(function(victim: Model)
		local spec = specByModel[victim]
		if spec == nil then
			return
		end
		specByModel[victim] = nil
		if spec.PracticeAttacker == true then
			clearPracticeAttacker(victim)
		end
		task.delay(RESPAWN_SECONDS, function()
			victim:Destroy()
			local replacement = spawnDummy(spec)
			specByModel[replacement] = spec
			if spec.PracticeAttacker == true then
				bindPracticeAttacker(replacement)
			end
		end)
	end)
	startPracticeLoop()
	print("[Combat] Studio training dummies spawned")
end

return TrainingDummyService
