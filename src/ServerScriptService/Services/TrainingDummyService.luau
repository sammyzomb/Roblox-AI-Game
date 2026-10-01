--!strict
-- Studio-only test aid: spawns PvE training dummies so combat can be tried
-- immediately after `rojo serve`. Dummies are ordinary tagged NPCs (see
-- CombatService "CombatNPC" tag), so this also shows how PvE enemies plug in.
-- Does nothing in live servers.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TrainingDummyService = {
	Priority = 10, -- after CombatService
}

-- Position, level and weapon of each dummy. Level 1 = weak, level 20 = armored.
local DUMMIES = {
	{ Position = Vector3.new(12, 3, -16), Level = 1, Weapon = "training_sword" },
	{ Position = Vector3.new(-12, 3, -16), Level = 10, Weapon = "wooden_shield" },
	{ Position = Vector3.new(0, 3, -30), Level = 20, Weapon = "tower_shield" },
}
local RESPAWN_SECONDS = 3

local combat: any

local function spawnDummy(spec: typeof(DUMMIES[1]))
	local model = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	model.Name = `TrainingDummy_L{spec.Level}`
	model:PivotTo(CFrame.new(spec.Position) * CFrame.Angles(0, math.pi, 0))
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.BreakJointsOnDeath = false
	model:SetAttribute("Level", spec.Level)
	model:SetAttribute("Weapon", spec.Weapon)
	model.Parent = Workspace
	CollectionService:AddTag(model, "CombatNPC")
	return model
end

function TrainingDummyService:Init(registry)
	combat = registry.CombatService
end

function TrainingDummyService:Start()
	if not RunService:IsStudio() then
		return
	end
	local specByModel: { [Model]: typeof(DUMMIES[1]) } = {}
	for _, spec in DUMMIES do
		specByModel[spawnDummy(spec)] = spec
	end
	combat.Killed:Connect(function(victim: Model)
		local spec = specByModel[victim]
		if spec == nil then
			return
		end
		specByModel[victim] = nil
		task.delay(RESPAWN_SECONDS, function()
			victim:Destroy()
			specByModel[spawnDummy(spec)] = spec
		end)
	end)
	print("[Combat] Studio training dummies spawned")
end

return TrainingDummyService
