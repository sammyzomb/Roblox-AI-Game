--!strict
-- Server-authoritative combat for players and NPCs, PvE and PvP.
--
-- This service is the Roblox "glue" around the pure combat core
-- (ReplicatedStorage/Shared/Combat). It owns time, geometry, networking,
-- Humanoid health and projectiles. All combat rules live in CombatCore and in
-- data; nothing here branches on a specific weapon.
--
-- The client only sends intent (which attack, where it aims). The server
-- decides everything else: whether the attack can start, who is in reach at
-- impact time, damage, effects, and deaths.
--
-- Public API (server):
--   CombatService:GetCombatant(model) -> Combatant?
--   CombatService:GetModel(combatantId) -> Model?
--   CombatService:RegisterNPC(model, spec) -> Combatant       spec: NpcSpec (below)
--   CombatService:Unregister(model)
--   CombatService:RequestAttack(model, slot, attackId, aimPoint?) -> (boolean, string?)
--   CombatService:SetBlocking(model, active) -> (boolean, string?)
--   CombatService:SetRuleset(player, rulesetId)                "PvE" (default) / "PvP" / custom
--   CombatService:SetTeam(model, team?)
--   CombatService:Revive(model)                                NPC respawn / round reset
--   CombatService:ApplyTrainingPreset(player, presetId) -> (boolean, string?)
--       Temporary in-memory hands for an active training session.
--       Accepts only TrainingLoadouts preset ids. Does not call
--       PlayerDataService:Update and does not change PlayerData.Consumables.
--       The first successful apply in a supply session grants the
--       development health_potion stock. A later preset does not grant again.
--   CombatService:RestorePersistentLoadout(player) -> (boolean, string?)
--       Clears training hands and equips the saved PlayerData hands.
--       Reads PlayerData. Does not call Update.
--   CombatService.AttackStarted:Connect(function(model, plan) end)
--   CombatService.Damaged:Connect(function(targetModel, attackerModel?, result) end)
--   CombatService.Killed:Connect(function(victimModel, killerModel?) end)
--
-- Remote protocol (CombatRequest, client -> server), all fields validated:
--   { Action = "Attack", Slot = "MainHand"|"OffHand", AttackId = string, Aim = Vector3? }
--   { Action = "Block", Active = boolean }
--   { Action = "UseItem", ItemId = string }
--       Outside training this spends PlayerData.Consumables.
--       During training, health_potion spends TrainingSupplies only.
--   { Action = "Equip", Slot = LoadoutSlot, ItemId = string | false }   false unequips
--   { Action = "TrainingPreset", PresetId = "Swordsman"|"Mage"|"Archer" }
--       In-memory only, and only while the training predicate is true.
-- CombatEvent (server -> clients) carries presentation data only (see broadcast calls).
-- A successful temporary apply, saved-hand restore, or fresh-character
-- saved equip also FireClient's
-- { Kind = "Loadout", Temporary = boolean, MainHand = string|false, OffHand = string|false }
-- to the owning player. Temporary is true only for a training preset.
-- It is not broadcast.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local PlayerDataModel = require(Shared.PlayerDataModel)

local Combat = Shared.Combat
local Types = require(Combat.Types)
local Definitions = require(Combat.Definitions)
local CombatCore = require(Combat.CombatCore)
local Rulesets = require(Combat.Rulesets)
local StatusEffects = require(Combat.StatusEffects)
local Projectile = require(Combat.Projectile)
local TrainingLoadouts = require(Combat.TrainingLoadouts)
local TrainingSupplies = require(Combat.TrainingSupplies)

local RateLimiter = require(script.Parent.Parent.Systems.RateLimiter)

type Combatant = Types.Combatant
type Ruleset = Types.Ruleset
type Plan = CombatCore.Plan

type Entry = {
	Combatant: Combatant,
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Player: Player?,
	RulesetId: string,
	BaseWalkSpeed: number,
	LastAttributeSync: number,
	Connections: { RBXScriptConnection },
}

type ActiveProjectile = {
	State: Projectile.State,
	Owner: Entry,
	Plan: Plan,
	Ruleset: Ruleset,
}

export type NpcSpec = {
	Level: number,
	MaxHealth: number?,
	Team: string?,
	Weapons: { string }?, -- weapon ids to equip, in order
	Armor: { string }?,
	BaseDefense: Types.DefenseProfile?,
	RulesetId: string?,
}

local NPC_TAG = "CombatNPC" -- tag a Model with a Humanoid to auto-register it
local MAX_AIM_DISTANCE = 1000
local MAX_ID_LENGTH = 64
local ATTRIBUTE_SYNC_INTERVAL = 0.1
local HAND_SLOTS = { MainHand = true, OffHand = true }

local CombatService = {
	Priority = 0,
	AttackStarted = Signal.new() :: any,
	Damaged = Signal.new() :: any,
	Killed = Signal.new() :: any,
}

local defs = Definitions.get()
local settings = Config.Combat :: any
local HIT_RADIUS = settings.CharacterHitRadius -- studs: approximate half-width of a character
local engine = CombatCore.new(defs, settings)
local trainingSupplies = TrainingSupplies.new(Config.Combat.DevelopmentTrainingStock)
local limiter = RateLimiter.new(Config.Combat.RateLimit.MaxRequests, Config.Combat.RateLimit.WindowSeconds)

local playerData: any -- PlayerDataService, resolved in Init
local combatEvent: RemoteEvent

-- Set by TrainingGroundService:Init via CombatService:SetTrainingPredicate so
-- Equip can be rejected, and UseItem can spend temporary training stock,
-- at the server boundary while a player is training. CombatService does not
-- require TrainingGroundService (which itself depends on CombatService).
-- Defaults to "nobody is training" so behavior is unchanged until the
-- training service registers itself.
local isTraining: (player: Player) -> boolean = function()
	return false
end

local entries: { [Model]: Entry } = {}
local byId: { [string]: Entry } = {}
local byPlayer: { [Player]: Entry } = {}
local playerRuleset: { [Player]: string } = {}
local projectiles: { ActiveProjectile } = {}
local nextNpcId = 0

local function now(): number
	return os.clock()
end

local function maxHealthFor(level: number): number
	return Config.Combat.Health.Base + Config.Combat.Health.PerLevel * (level - 1)
end

local function isFiniteVector(v: unknown): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	local vec = v :: Vector3
	for _, n in { vec.X, vec.Y, vec.Z } do
		if n ~= n or n == math.huge or n == -math.huge then
			return false
		end
	end
	return true
end

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_ID_LENGTH
end

-- Degrees between `look` and `direction`, measured on the ground plane.
local function flatAngle(look: Vector3, direction: Vector3): number
	local a = Vector3.new(look.X, 0, look.Z)
	local b = Vector3.new(direction.X, 0, direction.Z)
	if a.Magnitude < 1e-3 or b.Magnitude < 1e-3 then
		return 0
	end
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

local function broadcast(event: { [string]: any })
	combatEvent:FireAllClients(event)
end

local function reject(entry: Entry, reason: string?)
	if entry.Player then
		combatEvent:FireClient(entry.Player, { Kind = "Rejected", Reason = reason or "Rejected" })
	end
end

-- Tells only the owning client which hands are actually equipped in memory.
-- Temporary is true for a training preset and false for saved hands.
-- Persistent StateChanged still describes saved PlayerData, so the client
-- keeps a temporary map until a later event sets Temporary to false.
local function presentLoadout(entry: Entry, temporary: boolean)
	local player = entry.Player
	if player == nil then
		return
	end
	local hands = entry.Combatant.Loadout
	combatEvent:FireClient(player, {
		Kind = "Loadout",
		Temporary = temporary,
		MainHand = if hands.MainHand then hands.MainHand.Id else false,
		OffHand = if hands.OffHand then hands.OffHand.Id else false,
	})
end

---------------------------------------------------------------------------
-- Health / movement / HUD sync
---------------------------------------------------------------------------

local function sync(entry: Entry, t: number)
	local c = entry.Combatant
	local humanoid = entry.Humanoid
	if humanoid.MaxHealth ~= c.MaxHealth then
		humanoid.MaxHealth = c.MaxHealth
	end
	if humanoid.Health > 0 and humanoid.Health ~= c.Health then
		humanoid.Health = c.Health
	end

	local mods = StatusEffects.modifiers(c)
	local speed = entry.BaseWalkSpeed * mods.MoveSpeed
	if c.Blocking then
		local shield = (c.Loadout.OffHand and c.Loadout.OffHand.Block) or (c.Loadout.MainHand and c.Loadout.MainHand.Block)
		speed *= if shield then shield.MoveSpeedMultiplier or 1 else 1
	end
	if mods.PreventsActions then
		speed = 0
	end
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end

	-- Replicate pools for the HUD at a low rate (attributes replicate to clients).
	if t - entry.LastAttributeSync >= ATTRIBUTE_SYNC_INTERVAL then
		entry.LastAttributeSync = t
		for poolId, pool in c.Pools do
			entry.Model:SetAttribute(poolId, math.floor(pool.Current))
			entry.Model:SetAttribute(`{poolId}Max`, pool.Max)
		end
		entry.Model:SetAttribute("Blocking", c.Blocking)
		entry.Model:SetAttribute("Barrier", math.floor(StatusEffects.totalAbsorb(c)))
	end
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

local function onKilled(victim: Entry, killer: Entry?)
	if victim.Humanoid.Health > 0 then
		victim.Humanoid.Health = 0
	end
	broadcast({ Kind = "Killed", Victim = victim.Model, Killer = killer and killer.Model })
	CombatService.Killed:Fire(victim.Model, killer and killer.Model)
end

local function register(model: Model, humanoid: Humanoid, root: BasePart, combatant: Combatant, player: Player?, rulesetId: string): Entry
	local entry: Entry = {
		Combatant = combatant,
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Player = player,
		RulesetId = rulesetId,
		BaseWalkSpeed = humanoid.WalkSpeed,
		LastAttributeSync = 0,
		Connections = {},
	}
	entries[model] = entry
	byId[combatant.Id] = entry

	humanoid.MaxHealth = combatant.MaxHealth
	humanoid.Health = combatant.Health

	-- Deaths that did not come from combat (falling, reset, other scripts).
	table.insert(entry.Connections, humanoid.Died:Connect(function()
		if combatant.Alive then
			combatant.Alive = false
			combatant.Health = 0
			combatant.Pending = nil
			onKilled(entry, nil)
		end
	end))
	table.insert(entry.Connections, model.Destroying:Connect(function()
		CombatService:Unregister(model)
	end))
	return entry
end

function CombatService:Unregister(model: Model)
	local entry = entries[model]
	if entry == nil then
		return
	end
	for _, connection in entry.Connections do
		connection:Disconnect()
	end
	entries[model] = nil
	byId[entry.Combatant.Id] = nil
	if entry.Player and byPlayer[entry.Player] == entry then
		byPlayer[entry.Player] = nil
	end
end

-- Equips the saved loadout. Items that no longer exist or are locked are
-- removed from the saved data so the player is never stuck with invalid gear.
local function equipSavedLoadout(player: Player, combatant: Combatant)
	local data = playerData:Get(player)
	local profile = playerData:GetProfile(player)
	if data == nil or profile == nil then
		return
	end
	local invalid = {}
	for _, slot in PlayerDataModel.LOADOUT_SLOTS do
		local id = (data.Loadout :: any)[slot]
		if id then
			local ok
			if HAND_SLOTS[slot] then
				local def = defs.Weapons[id]
				ok = def ~= nil and def.Slot == slot and engine:equipWeapon(combatant, id, profile)
			else
				local def = defs.Armor[id]
				ok = def ~= nil and def.Slot == slot and engine:equipArmor(combatant, id, profile)
			end
			if not ok then
				table.insert(invalid, slot)
			end
		end
	end
	if #invalid > 0 then
		playerData:Update(player, function(d)
			for _, slot in invalid do
				(d.Loadout :: any)[slot] = nil
			end
		end)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	-- Death and respawn replace the character. Drop temporary stock even
	-- when this races ahead of the ruleset restore. Clearing is idempotent.
	trainingSupplies:clear(player)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if humanoid == nil or root == nil or character.Parent == nil then
		return
	end
	-- Health comes from the combat system only: remove Roblox's default regen script.
	local regen = character:FindFirstChild("Health")
	if regen and regen:IsA("Script") then
		regen:Destroy()
	end

	local data = playerData:Get(player)
	local level = if data then data.Level else 1
	local combatant = engine:newCombatant({
		Id = `player_{player.UserId}`,
		Kind = "Player",
		Level = level,
		MaxHealth = maxHealthFor(level),
	})
	local old = byPlayer[player]
	if old then
		CombatService:Unregister(old.Model)
	end
	-- A fresh character (death/respawn, first join) must never silently
	-- inherit a leftover "Training" ruleset from a session that did not
	-- explicitly carry over (training sessions are tied to a specific
	-- character/combatant, not the player forever). TrainingGroundService is
	-- responsible for restoring the correct prior ruleset via SetRuleset
	-- before/around this point; if for any reason playerRuleset is still
	-- "Training" here (e.g. a respawn raced ahead of that cleanup), fall
	-- back to the configured default rather than keep training rules active
	-- on a character nobody asked to put into training.
	local rulesetId = playerRuleset[player] or Config.Combat.DefaultRuleset
	if rulesetId == "Training" then
		rulesetId = Config.Combat.DefaultRuleset
		playerRuleset[player] = rulesetId
	end
	local entry = register(character, humanoid, root, combatant, player, rulesetId)
	byPlayer[player] = entry
	equipSavedLoadout(player, combatant)
	-- The fresh character is on the saved loadout. Tell the owning client
	-- so a temporary attack-map latch from the previous character clears.
	presentLoadout(entry, false)
end

local function onPlayerDataLoaded(player: Player)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

function CombatService:RegisterNPC(model: Model, spec: NpcSpec): Combatant
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	assert(humanoid and root and root:IsA("BasePart"), `[Combat] NPC {model:GetFullName()} needs a Humanoid and a HumanoidRootPart`)
	self:Unregister(model)

	nextNpcId += 1
	local combatant = engine:newCombatant({
		Id = `npc_{nextNpcId}`,
		Kind = "NPC",
		Team = spec.Team,
		Level = spec.Level,
		MaxHealth = spec.MaxHealth or maxHealthFor(spec.Level),
		BaseDefense = spec.BaseDefense,
	})
	local weapons: { string } = spec.Weapons or {}
	local armor: { string } = spec.Armor or {}
	for _, id in weapons do
		local ok, why = engine:equipWeapon(combatant, id)
		if not ok then
			warn(`[Combat] NPC {model.Name}: cannot equip {id}: {why}`)
		end
	end
	for _, id in armor do
		local ok, why = engine:equipArmor(combatant, id)
		if not ok then
			warn(`[Combat] NPC {model.Name}: cannot equip {id}: {why}`)
		end
	end
	register(model, humanoid :: Humanoid, root :: BasePart, combatant, nil, spec.RulesetId or "PvE")
	return combatant
end

-- Tagged models: attributes Level (number), MaxHealth (number?), Weapon (string?), Team (string?).
local function registerTagged(instance: Instance)
	if not instance:IsA("Model") or entries[instance] then
		return
	end
	local weapon = instance:GetAttribute("Weapon")
	local ok, err = pcall(function()
		CombatService:RegisterNPC(instance, {
			Level = tonumber(instance:GetAttribute("Level")) or 1,
			MaxHealth = tonumber(instance:GetAttribute("MaxHealth")),
			Team = instance:GetAttribute("Team") :: string?,
			Weapons = if type(weapon) == "string" then { weapon } else nil,
		})
	end)
	if not ok then
		warn(err)
	end
end

---------------------------------------------------------------------------
-- Attack resolution
---------------------------------------------------------------------------

local function applyHit(attacker: Entry, target: Entry, plan: Plan, ruleset: Ruleset, hitFrom: Vector3)
	local t = now()
	local result = engine:applyHit(attacker.Combatant, target.Combatant, plan.Weapon, plan.Attack, ruleset, t, {
		AngleFromTargetFacing = flatAngle(target.Root.CFrame.LookVector, hitFrom - target.Root.Position),
	})
	if not result.Hit then
		if result.Reason == "Evaded" then
			broadcast({ Kind = "Evaded", Target = target.Model, Attacker = attacker.Model })
		end
		return
	end
	sync(target, t)
	sync(attacker, t)
	broadcast({
		Kind = "Hit",
		Target = target.Model,
		Attacker = attacker.Model,
		Damage = result.Damage,
		Blocked = math.floor(result.Blocked + 0.5),
		Absorbed = math.floor(result.Absorbed + 0.5),
		Reflected = result.Reflected,
		GuardBroken = result.GuardBroken,
		Statuses = result.AppliedStatuses,
	})
	CombatService.Damaged:Fire(target.Model, attacker.Model, result)
	if result.Killed then
		onKilled(target, attacker)
	end
	if result.Reflected > 0 and not attacker.Combatant.Alive then
		onKilled(attacker, target)
	end
end

local function resolveMelee(attacker: Entry, plan: Plan, ruleset: Ruleset)
	local origin = attacker.Root.Position
	local look = attacker.Root.CFrame.LookVector
	for _, target in entries do
		if target ~= attacker and target.Combatant.Alive then
			local offset = target.Root.Position - origin
			local reach = { Distance = math.max(0, offset.Magnitude - HIT_RADIUS), Angle = flatAngle(look, offset) }
			if engine:checkReach(attacker.Combatant, target.Combatant, plan.Attack, ruleset, reach) then
				applyHit(attacker, target, plan, ruleset, origin)
			end
		end
	end
end

local function clampAim(attacker: Entry, aim: Vector3?, range: number): Vector3
	local origin = attacker.Root.Position
	local point = aim or (origin + attacker.Root.CFrame.LookVector * range)
	local offset = point - origin
	if offset.Magnitude > range then
		point = origin + offset.Unit * range
	end
	return point
end

local function resolveArea(attacker: Entry, plan: Plan, ruleset: Ruleset, aim: Vector3?)
	local center = clampAim(attacker, aim, plan.Attack.Range or 0)
	broadcast({ Kind = "Area", Attacker = attacker.Model, Center = center, Radius = plan.Attack.Radius })
	for _, target in entries do
		if target ~= attacker and target.Combatant.Alive then
			local distance = math.max(0, (target.Root.Position - center).Magnitude - HIT_RADIUS)
			if engine:checkReach(attacker.Combatant, target.Combatant, plan.Attack, ruleset, { Distance = distance }) then
				applyHit(attacker, target, plan, ruleset, center)
			end
		end
	end
end

local function launchProjectile(attacker: Entry, plan: Plan, ruleset: Ruleset, aim: Vector3?)
	local spec = plan.Attack.Projectile
	if spec == nil then
		return
	end
	local root = attacker.Root
	local origin = root.Position + root.CFrame.LookVector * 1.5 + Vector3.new(0, 1.5, 0)
	local target = aim or (origin + root.CFrame.LookVector * spec.MaxRange)
	-- Roblox's `vector` type is Vector3 at runtime; the casts only satisfy the type checker.
	local state = Projectile.new(origin :: any, (target - origin) :: any, spec, attacker.Combatant.Id)
	if state == nil then
		return
	end
	table.insert(projectiles, { State = state, Owner = attacker, Plan = plan, Ruleset = ruleset })
	broadcast({
		Kind = "Projectile",
		Attacker = attacker.Model,
		Weapon = plan.Weapon.Id,
		Attack = plan.AttackId,
		Origin = origin,
		Velocity = state.Velocity :: any,
		Gravity = spec.Gravity or 0,
		MaxRange = spec.MaxRange,
	})
end

local function resolve(attacker: Entry, plan: Plan, aim: Vector3?)
	if entries[attacker.Model] ~= attacker or not engine:isPlanValid(attacker.Combatant, plan) then
		return -- interrupted, dead or unregistered during the windup
	end
	local ruleset = Rulesets.get(attacker.RulesetId)
	local delivery = plan.Attack.Delivery
	if delivery == "Melee" then
		resolveMelee(attacker, plan, ruleset)
	elseif delivery == "Area" then
		resolveArea(attacker, plan, ruleset, aim)
	elseif delivery == "Projectile" then
		launchProjectile(attacker, plan, ruleset, aim)
	end
	if plan.Attack.OnSelf or plan.Attack.Heal then
		engine:applySelf(attacker.Combatant, plan, ruleset, now())
	end
	engine:finishAttack(attacker.Combatant, plan)
	sync(attacker, now())
end

local function stepProjectiles(dt: number)
	if #projectiles == 0 then
		return
	end
	local exclude: { Instance } = {}
	for model in entries do
		table.insert(exclude, model)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude

	for i = #projectiles, 1, -1 do
		local p = projectiles[i]
		local state = p.State
		local fromV, toV = Projectile.step(state, dt)
		local from: Vector3, to: Vector3 = (fromV :: any), (toV :: any)
		local segment = to - from

		-- World geometry stops projectiles.
		local limit = 1
		local wall = Workspace:Raycast(from, segment, params)
		if wall and segment.Magnitude > 0 then
			limit = (wall.Position - from).Magnitude / segment.Magnitude
		end

		-- Combatants hit along the segment, nearest first.
		local candidates = {}
		for _, target in entries do
			local id = target.Combatant.Id
			if id ~= state.OwnerId and target.Combatant.Alive and not state.HitIds[id] then
				local hit, t = Projectile.sweepSphere(fromV, toV, target.Root.Position :: any, HIT_RADIUS + state.Spec.Radius)
				if hit and t <= limit and Rulesets.canTarget(p.Ruleset, p.Owner.Combatant, target.Combatant) then
					table.insert(candidates, { Entry = target, T = t })
				end
			end
		end
		table.sort(candidates, function(a, b)
			return a.T < b.T
		end)
		for _, candidate in candidates do
			applyHit(p.Owner, candidate.Entry, p.Plan, p.Ruleset, from)
			if not Projectile.registerHit(state, candidate.Entry.Combatant.Id) then
				break
			end
		end

		if wall then
			state.Done = true
		end
		if state.Done then
			table.remove(projectiles, i)
		end
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function CombatService:GetCombatant(model: Model): Combatant?
	local entry = entries[model]
	return if entry then entry.Combatant else nil
end

function CombatService:GetModel(combatantId: string): Model?
	local entry = byId[combatantId]
	return if entry then entry.Model else nil
end

function CombatService:RequestAttack(model: Model, slot: Types.Slot, attackId: string, aim: Vector3?): (boolean, string?)
	local entry = entries[model]
	if entry == nil then
		return false, "NotCombatant"
	end
	local t = now()
	local plan, why = engine:beginAttack(entry.Combatant, slot, attackId, t)
	if plan == nil then
		return false, why
	end
	broadcast({
		Kind = "AttackStarted",
		Attacker = model,
		Weapon = plan.Weapon.Id,
		Attack = attackId,
		Windup = plan.ImpactAt - t,
	})
	self.AttackStarted:Fire(model, plan)
	task.delay(plan.ImpactAt - t, resolve, entry, plan, aim)
	return true, nil
end

function CombatService:SetBlocking(model: Model, active: boolean): (boolean, string?)
	local entry = entries[model]
	if entry == nil then
		return false, "NotCombatant"
	end
	local ok, why = engine:setBlocking(entry.Combatant, active, now())
	sync(entry, now())
	return ok, why
end

function CombatService:SetRuleset(player: Player, rulesetId: string)
	assert(Rulesets.exists(rulesetId), `unknown ruleset "{rulesetId}"`)
	-- A manual exit reaches this only after RestorePersistentLoadout has
	-- succeeded. Death and a character-less exit also leave "Training"
	-- through this call. Failed loadout restore never gets here, so that
	-- player keeps the active training stock.
	if playerRuleset[player] == "Training" and rulesetId ~= "Training" then
		trainingSupplies:clear(player)
	end
	playerRuleset[player] = rulesetId
	local entry = byPlayer[player]
	if entry then
		entry.RulesetId = rulesetId
	end
end

-- Returns the ruleset id currently stored for `player` (falls back to the
-- configured default if the player has never had one set, e.g. before their
-- first CharacterAdded). Used by TrainingGroundService to capture the prior
-- ruleset before switching to "Training" so it can be restored exactly on
-- exit/death/disconnect instead of assuming "PvE".
function CombatService:GetRuleset(player: Player): string
	return playerRuleset[player] or Config.Combat.DefaultRuleset
end

-- Lets another service (TrainingGroundService) register a predicate used to
-- reject persistent-data-affecting requests (UseItem/Equip) while a player
-- is in a training session. Kept as an injected callback instead of a direct
-- require to avoid a circular dependency between the two services.
function CombatService:SetTrainingPredicate(predicate: (player: Player) -> boolean)
	isTraining = predicate
end

-- Applies one approved training preset to the player's live combatant.
-- Requires the injected training predicate. Missing, dead, and busy
-- combatants are rejected before any hand changes. An unexpected equip
-- failure rolls the previous in-memory hands back inside TrainingLoadouts.
-- PlayerDataService:Update is intentionally not called.
function CombatService:ApplyTrainingPreset(player: Player, presetId: unknown): (boolean, string?)
	if not isTraining(player) then
		return false, "NotTraining"
	end
	local preset, why = TrainingLoadouts.validatePresetId(presetId)
	if preset == nil then
		return false, why
	end
	local entry = byPlayer[player]
	if entry == nil then
		return false, "NotRegistered"
	end
	local applied, reason = TrainingLoadouts.applyPreset(engine, entry.Combatant, preset, now())
	if not applied then
		return false, reason
	end
	-- Same active session: a later preset must not refill. Repeat Enter
	-- does not call this at all. A new session calls it again after clear.
	trainingSupplies:beginSession(player)
	presentLoadout(entry, true)
	return true, nil
end

-- Replaces in-memory training hands with the hands stored in PlayerData.
-- This reads the saved record and does not call PlayerDataService:Update,
-- so a training preset cannot be persisted by leaving the area.
function CombatService:RestorePersistentLoadout(player: Player): (boolean, string?)
	local entry = byPlayer[player]
	if entry == nil then
		return false, "NotRegistered"
	end
	local data = playerData:Get(player)
	local profile = playerData:GetProfile(player)
	if data == nil or profile == nil then
		return false, "NoData"
	end
	local restored, why = TrainingLoadouts.equipSavedHands(
		engine,
		entry.Combatant,
		data.Loadout.MainHand,
		data.Loadout.OffHand,
		profile,
		now()
	)
	if not restored then
		return false, why
	end
	presentLoadout(entry, false)
	return true, nil
end

function CombatService:SetTeam(model: Model, team: string?)
	local entry = entries[model]
	if entry then
		entry.Combatant.Team = team
	end
end

function CombatService:Revive(model: Model)
	local entry = entries[model]
	if entry == nil then
		return
	end
	engine:revive(entry.Combatant)
	entry.Humanoid.Health = entry.Combatant.MaxHealth
	sync(entry, now())
end

-- Restores a live combatant to full Health and full resource pools, and
-- clears transient statuses/blocking/pending state. Used by training areas
-- and similar "practice reset" features; does not touch persistent data.
-- No-op if the model is not a registered, living combatant.
function CombatService:ResetVitals(model: Model): boolean
	local entry = entries[model]
	if entry == nil or not entry.Combatant.Alive then
		return false
	end
	local c = entry.Combatant
	c.Health = c.MaxHealth
	for _, pool in c.Pools do
		pool.Current = pool.Max
		pool.LastSpent = 0
	end
	c.Statuses = {}
	c.Blocking = false
	c.BlockSince = 0
	c.Pending = nil
	c.BusyUntil = 0
	c.VulnerableFrom = 0
	c.VulnerableUntil = 0
	c.VulnerabilityMultiplier = 1
	entry.Humanoid.Health = c.MaxHealth
	sync(entry, now())
	return true
end

---------------------------------------------------------------------------
-- Remote handling
---------------------------------------------------------------------------

local function trainingHealBlocked(itemId: string, combatant: Combatant): boolean
	local def = defs.Consumables[itemId]
	local heal = if def ~= nil then def.Heal else nil
	if heal == nil or heal <= 0 then
		return false
	end
	return combatant.Health >= combatant.MaxHealth
end

local function onTrainingUseItem(entry: Entry, player: Player, itemId: string)
	-- Temporary stock only. This branch does not call PlayerDataService:Get
	-- or :Update, so PlayerData.Consumables cannot change here.
	local plan = trainingSupplies:planUse(player, itemId, true, trainingHealBlocked(itemId, entry.Combatant))
	local route: TrainingSupplies.Route = TrainingSupplies.route(plan)
	if route == "Training" then
		local ok, why = engine:useConsumable(
			entry.Combatant,
			itemId,
			now(),
			playerData:GetProfile(player),
			Rulesets.get(entry.RulesetId)
		)
		local spent, spendWhy = trainingSupplies:finishUse(player, itemId, ok)
		if not ok then
			return reject(entry, why)
		end
		if not spent then
			return reject(entry, spendWhy)
		end
		sync(entry, now())
		broadcast({ Kind = "ItemUsed", User = entry.Model, Item = itemId })
		return
	elseif route == "Reject" then
		return reject(entry, plan.Reason)
	elseif route == "Persistent" then
		return reject(entry, "TrainingNoPersistentUse")
	else
		local _exhaustive: never = route
		return reject(entry, "Rejected")
	end
end

local function onUseItem(entry: Entry, player: Player, itemId: string)
	if isTraining(player) then
		return onTrainingUseItem(entry, player, itemId)
	end
	local data = playerData:Get(player)
	if data == nil or (data.Consumables[itemId] or 0) <= 0 then
		return reject(entry, "NoItem")
	end
	local ok, why = engine:useConsumable(entry.Combatant, itemId, now(), playerData:GetProfile(player), Rulesets.get(entry.RulesetId))
	if not ok then
		return reject(entry, why)
	end
	playerData:Update(player, function(d)
		local left = (d.Consumables[itemId] or 1) - 1
		if left > 0 then
			d.Consumables[itemId] = left
		else
			d.Consumables[itemId] = nil
		end
	end)
	sync(entry, now())
	broadcast({ Kind = "ItemUsed", User = entry.Model, Item = itemId })
end

local function onEquip(entry: Entry, player: Player, slot: string, itemId: string | false)
	if not table.find(PlayerDataModel.LOADOUT_SLOTS, slot) then
		return
	end
	if isTraining(player) then
		-- Equip writes the loadout through PlayerDataService below. Training
		-- presets use Action "TrainingPreset" and must never reach this write.
		return reject(entry, "TrainingNoPersistentEquip")
	end
	local c = entry.Combatant
	if c.Pending or c.Blocking then
		return reject(entry, "Busy")
	end
	if itemId == false then
		engine:unequip(c, slot :: Types.Slot)
	else
		local profile = playerData:GetProfile(player)
		local ok, why
		if HAND_SLOTS[slot] then
			local def = defs.Weapons[itemId]
			if def == nil or def.Slot ~= slot then
				return reject(entry, "WrongSlot")
			end
			ok, why = engine:equipWeapon(c, itemId, profile)
		else
			local def = defs.Armor[itemId]
			if def == nil or def.Slot ~= slot then
				return reject(entry, "WrongSlot")
			end
			ok, why = engine:equipArmor(c, itemId, profile)
		end
		if not ok then
			return reject(entry, why)
		end
	end
	-- Persist the combatant's actual loadout (two-handed weapons may clear the off hand).
	playerData:Update(player, function(d)
		local loadout: any = {
			MainHand = c.Loadout.MainHand and c.Loadout.MainHand.Id,
			OffHand = c.Loadout.OffHand and c.Loadout.OffHand.Id,
		}
		for _, piece in c.Loadout.Armor do
			loadout[piece.Slot] = piece.Id
		end
		d.Loadout = loadout
	end)
end

local function onRequest(player: Player, request: unknown)
	if type(request) ~= "table" then
		return
	end
	if not limiter:allow(player.UserId, now()) then
		return
	end
	local entry = byPlayer[player]
	if entry == nil or not entry.Combatant.Alive then
		return
	end
	local r = request :: any
	local action = r.Action

	if action == "Attack" then
		if not HAND_SLOTS[r.Slot] or not isId(r.AttackId) then
			return
		end
		local aim: Vector3? = nil
		if r.Aim ~= nil then
			if not isFiniteVector(r.Aim) or (r.Aim - entry.Root.Position).Magnitude > MAX_AIM_DISTANCE then
				return
			end
			aim = r.Aim
		end
		local ok, why = CombatService:RequestAttack(entry.Model, r.Slot, r.AttackId, aim)
		if not ok then
			reject(entry, why)
		end
	elseif action == "Block" then
		if type(r.Active) ~= "boolean" then
			return
		end
		local ok, why = CombatService:SetBlocking(entry.Model, r.Active)
		if not ok then
			reject(entry, why)
		end
	elseif action == "UseItem" then
		if isId(r.ItemId) then
			onUseItem(entry, player, r.ItemId)
		end
	elseif action == "Equip" then
		if type(r.Slot) == "string" and (r.ItemId == false or isId(r.ItemId)) then
			onEquip(entry, player, r.Slot, r.ItemId)
		end
	elseif action == "TrainingPreset" then
		local presetId, why = TrainingLoadouts.validateSelectionRequest(r)
		if presetId == nil then
			reject(entry, why)
		else
			local ok, reason = CombatService:ApplyTrainingPreset(player, presetId)
			if not ok then
				reject(entry, reason)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function CombatService:Init(registry)
	playerData = registry.PlayerDataService
	combatEvent = Net.event(Net.Names.CombatEvent)
end

function CombatService:Start()
	Net.event(Net.Names.CombatRequest).OnServerEvent:Connect(onRequest)

	playerData.Loaded:Connect(onPlayerDataLoaded)
	for _, player in Players:GetPlayers() do
		if playerData:Get(player) then
			onPlayerDataLoaded(player)
		end
	end

	-- Level ups raise max health; gear gates are re-checked on the next equip.
	playerData.Changed:Connect(function(player: Player, data)
		local entry = byPlayer[player]
		if entry and entry.Combatant.Level ~= data.Level then
			local c = entry.Combatant
			local ratio = c.Health / c.MaxHealth
			c.Level = data.Level
			c.MaxHealth = maxHealthFor(data.Level)
			c.Health = math.max(1, math.floor(c.MaxHealth * ratio + 0.5))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		trainingSupplies:clear(player)
		local entry = byPlayer[player]
		if entry then
			self:Unregister(entry.Model)
		end
		playerRuleset[player] = nil
		limiter:clear(player.UserId)
	end)

	CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(registerTagged)
	CollectionService:GetInstanceRemovedSignal(NPC_TAG):Connect(function(instance)
		if instance:IsA("Model") then
			self:Unregister(instance)
		end
	end)
	for _, instance in CollectionService:GetTagged(NPC_TAG) do
		registerTagged(instance)
	end

	RunService.Heartbeat:Connect(function(dt)
		local t = now()
		for _, entry in entries do
			local c = entry.Combatant
			if c.Alive then
				local tick = engine:tick(c, t, dt, Rulesets.get(entry.RulesetId))
				if tick.Damage > 0 then
					broadcast({ Kind = "Hit", Target = entry.Model, Damage = tick.Damage, OverTime = true })
				end
				if tick.Killed then
					onKilled(entry, tick.KillerId and byId[tick.KillerId] or nil)
				end
				sync(entry, t)
			end
		end
		stepProjectiles(dt)
	end)
end

return CombatService
