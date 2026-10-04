--!strict
-- Development configuration for temporary training presets.
--
-- These three presets are server-owned loadouts for an active training
-- session. They are not balance, not a second combat core, and they must
-- never be written into PlayerData. Weapon numbers stay in Data/Weapons.luau;
-- this module only names existing item ids and checks that those definitions
-- can share hands.
--
-- The approved rifle is still absent from Definitions. This module does not
-- invent one. See MISSING_RIFLE.
--
-- Public API:
--   TrainingLoadouts.DEFAULT_PRESET_ID            "Swordsman"
--   TrainingLoadouts.PRESET_IDS                   { "Swordsman", "Mage", "Archer" }
--   TrainingLoadouts.SELECTION_ACTION             "TrainingPreset"
--   TrainingLoadouts.MISSING_RIFLE                dependency note, not an item id
--   TrainingLoadouts.itemIds(presetId) -> { string }?
--   TrainingLoadouts.validatePresetId(value) -> (string?, string?)
--   TrainingLoadouts.validateSelectionRequest(request) -> (string?, string?)
--   TrainingLoadouts.compatibilityErrors(defs) -> { string }
--   TrainingLoadouts.applyPreset(engine, combatant, presetId, now) -> (boolean, string?)
--   TrainingLoadouts.equipSavedHands(engine, combatant, mainId, offId, profile, now) -> (boolean, string?)
--   TrainingLoadouts.readLoadoutEvent(event) -> { Hands, Temporary }?
--   TrainingLoadouts.presentedHands(event) -> { [string]: string }?
--   TrainingLoadouts.applyPresentedLoadout(current, event) -> { [string]: string }
--   TrainingLoadouts.emptyAttackMap() -> { Loadout, Temporary }
--   TrainingLoadouts.applyPersistentAttackMap(state, playerState) -> state
--   TrainingLoadouts.applyLoadoutEvent(state, event) -> state
--       CombatController uses these three for its local attack map. A
--       Temporary=true Loadout event latches the map. While that latch is
--       set, PlayerData StateChanged and a late GetState result do not
--       replace it. A valid Temporary=false event replaces the map and
--       clears the latch. A malformed event changes neither.

local CombatCore = require("./CombatCore")
local Definitions = require("./Definitions")
local ProgressionGates = require("../ProgressionGates")
local Types = require("./Types")

type Combatant = Types.Combatant
type Engine = CombatCore.Engine
type Profile = ProgressionGates.Profile

export type PresentedHands = { [string]: string }

export type ReadLoadout = {
	Hands: PresentedHands,
	Temporary: boolean,
}

export type AttackMap = {
	Loadout: PresentedHands,
	Temporary: boolean,
}

local PRESET_ITEMS: { [string]: { string } } = {
	Swordsman = { "training_sword", "wooden_shield" },
	Mage = { "ember_staff" },
	Archer = { "hunting_bow" },
}

local PRESET_ORDER = { "Swordsman", "Mage", "Archer" }

local TrainingLoadouts = {
	DEFAULT_PRESET_ID = "Swordsman",
	PRESET_IDS = table.freeze({ "Swordsman", "Mage", "Archer" }),
	SELECTION_ACTION = "TrainingPreset",
	MISSING_RIFLE = "approved rifle weapon is absent from Definitions; no rifle preset is defined",
}

local function copyIds(ids: { string }): { string }
	local copy = table.clone(ids)
	table.freeze(copy)
	return copy
end

function TrainingLoadouts.itemIds(presetId: string): { string }?
	local items = PRESET_ITEMS[presetId]
	if items == nil then
		return nil
	end
	return copyIds(items)
end

function TrainingLoadouts.validatePresetId(value: unknown): (string?, string?)
	if type(value) ~= "string" then
		return nil, "MalformedPreset"
	end
	if PRESET_ITEMS[value] == nil then
		return nil, "UnknownPreset"
	end
	return value, nil
end

-- Future UI payload. Only the finite preset id is accepted. Any extra field
-- (including an item id) rejects the whole request.
function TrainingLoadouts.validateSelectionRequest(request: unknown): (string?, string?)
	if type(request) ~= "table" then
		return nil, "MalformedPreset"
	end
	local payload = request :: { [unknown]: unknown }
	if payload.Action ~= TrainingLoadouts.SELECTION_ACTION then
		return nil, "MalformedPreset"
	end
	for key in payload do
		if key ~= "Action" and key ~= "PresetId" then
			return nil, "MalformedPreset"
		end
	end
	return TrainingLoadouts.validatePresetId(payload.PresetId)
end

local function checkPreset(errors: { string }, defs: any, presetId: string, itemIds: { string })
	local mainSlot = false
	local offSlot = false
	local mainTwoHanded = false
	for index, itemId in itemIds do
		if type(itemId) ~= "string" then
			table.insert(errors, `{presetId}: item {index} is not an existing item id`)
			continue
		end
		local weapon = defs.Weapons[itemId]
		if weapon == nil then
			table.insert(errors, `{presetId}: missing weapon {itemId}`)
			continue
		end
		if weapon.Slot == "MainHand" then
			if mainSlot then
				table.insert(errors, `{presetId}: more than one main-hand item`)
			end
			if index ~= 1 then
				table.insert(errors, `{presetId}: main hand must be equipped first`)
			end
			mainSlot = true
			mainTwoHanded = weapon.TwoHanded == true
		elseif weapon.Slot == "OffHand" then
			if offSlot then
				table.insert(errors, `{presetId}: more than one off-hand item`)
			end
			offSlot = true
		else
			table.insert(errors, `{presetId}: {itemId} is not a hand item`)
		end
	end
	if not mainSlot then
		table.insert(errors, `{presetId}: missing main hand`)
	end
	if mainTwoHanded and offSlot then
		table.insert(errors, `{presetId}: two-handed weapon cannot share hands with an off-hand item`)
	end
end

function TrainingLoadouts.compatibilityErrors(defs: any): { string }
	local errors = {}
	for _, presetId in PRESET_ORDER do
		local itemIds = PRESET_ITEMS[presetId]
		if itemIds == nil then
			table.insert(errors, `{presetId}: missing development configuration`)
		else
			checkPreset(errors, defs, presetId, itemIds)
		end
	end
	return errors
end

local function rejectBeforeMutation(engine: Engine, combatant: Combatant, now: number): string?
	if not combatant.Alive then
		return "Dead"
	end
	local canAct, why = engine:canAct(combatant, now)
	if not canAct then
		return why
	end
	if combatant.Blocking or combatant.Pending then
		return "Busy"
	end
	return nil
end

local function clearHands(engine: Engine, combatant: Combatant)
	engine:unequip(combatant, "OffHand")
	engine:unequip(combatant, "MainHand")
end

local function snapshotHands(combatant: Combatant): (string?, string?)
	local main = combatant.Loadout.MainHand
	local off = combatant.Loadout.OffHand
	return if main then main.Id else nil, if off then off.Id else nil
end

local function restoreSnapshot(engine: Engine, combatant: Combatant, mainId: string?, offId: string?): (boolean, string?)
	clearHands(engine, combatant)
	if mainId ~= nil then
		local ok, why = engine:equipWeapon(combatant, mainId, nil)
		if not ok then
			return false, why
		end
	end
	if offId ~= nil then
		local ok, why = engine:equipWeapon(combatant, offId, nil)
		if not ok then
			return false, why
		end
	end
	return true, nil
end

-- Replaces hand items with one approved preset. Progression gates are not
-- applied: the server chose the preset. On an unexpected equip failure the
-- previous in-memory hands are put back. Armor is left untouched.
function TrainingLoadouts.applyPreset(engine: Engine, combatant: Combatant, presetId: unknown, now: number): (boolean, string?)
	local id, why = TrainingLoadouts.validatePresetId(presetId)
	if id == nil then
		return false, why
	end
	local blocked = rejectBeforeMutation(engine, combatant, now)
	if blocked ~= nil then
		return false, blocked
	end
	local previousMain, previousOff = snapshotHands(combatant)
	clearHands(engine, combatant)
	for _, itemId in PRESET_ITEMS[id] do
		local equipped, equipWhy = engine:equipWeapon(combatant, itemId, nil)
		if not equipped then
			local rolledBack, rollbackWhy = restoreSnapshot(engine, combatant, previousMain, previousOff)
			if not rolledBack then
				return false, rollbackWhy
			end
			return false, equipWhy
		end
	end
	return true, nil
end

local function savedHandId(engine: Engine, itemId: string?, slot: string): string?
	if type(itemId) ~= "string" then
		return nil
	end
	local weapon = engine.Defs.Weapons[itemId]
	if weapon == nil or weapon.Slot ~= slot then
		return nil
	end
	return itemId
end

-- Puts the saved hand ids onto a live combatant. Gates apply, matching the
-- normal saved-loadout path. A hand that cannot be equipped is left empty;
-- this function never writes PlayerData and never keeps a training weapon in
-- a slot it failed to replace. Callers must reject a busy combatant first
-- (this function does that and does not mutate on rejection).
function TrainingLoadouts.equipSavedHands(
	engine: Engine,
	combatant: Combatant,
	mainId: string?,
	offId: string?,
	profile: Profile?,
	now: number
): (boolean, string?)
	local blocked = rejectBeforeMutation(engine, combatant, now)
	if blocked ~= nil then
		return false, blocked
	end
	clearHands(engine, combatant)
	local savedMain = savedHandId(engine, mainId, "MainHand")
	if savedMain ~= nil then
		engine:equipWeapon(combatant, savedMain, profile)
	end
	local savedOff = savedHandId(engine, offId, "OffHand")
	if savedOff ~= nil then
		engine:equipWeapon(combatant, savedOff, profile)
	end
	return true, nil
end

local function presentedSlot(value: unknown): (string?, boolean)
	if value == false then
		return nil, true
	end
	if type(value) == "string" and Definitions.get().Weapons[value] ~= nil then
		return value, true
	end
	return nil, false
end

-- Owning-client CombatEvent shape: Kind "Loadout", a boolean Temporary
-- flag, and both hand fields. Each hand is either false (empty) or an
-- existing weapon id. Missing or non-boolean Temporary, a bad hand, or an
-- unknown weapon id returns nil so the caller keeps both its map and latch.
function TrainingLoadouts.readLoadoutEvent(event: unknown): ReadLoadout?
	if type(event) ~= "table" then
		return nil
	end
	local payload = event :: { [unknown]: unknown }
	if payload.Kind ~= "Loadout" then
		return nil
	end
	local temporary = payload.Temporary
	if type(temporary) ~= "boolean" then
		return nil
	end
	local mainId, mainOk = presentedSlot(payload.MainHand)
	local offId, offOk = presentedSlot(payload.OffHand)
	if not mainOk or not offOk then
		return nil
	end
	local hands: PresentedHands = {}
	if mainId ~= nil then
		hands.MainHand = mainId
	end
	if offId ~= nil then
		hands.OffHand = offId
	end
	return { Hands = hands, Temporary = temporary }
end

function TrainingLoadouts.presentedHands(event: unknown): PresentedHands?
	local read = TrainingLoadouts.readLoadoutEvent(event)
	if read == nil then
		return nil
	end
	return read.Hands
end

function TrainingLoadouts.applyPresentedLoadout(current: PresentedHands, event: unknown): PresentedHands
	local read = TrainingLoadouts.readLoadoutEvent(event)
	if read == nil then
		return current
	end
	return read.Hands
end

function TrainingLoadouts.emptyAttackMap(): AttackMap
	return { Loadout = {}, Temporary = false }
end

local function persistentHands(loadout: { [unknown]: unknown }): PresentedHands
	local hands: PresentedHands = {}
	local main = loadout.MainHand
	local off = loadout.OffHand
	if type(main) == "string" then
		hands.MainHand = main
	end
	if type(off) == "string" then
		hands.OffHand = off
	end
	return hands
end

-- PlayerData snapshots always describe the saved loadout. They must not
-- replace a temporary training map. A snapshot with no Loadout table is
-- ignored either way, matching the previous client check.
function TrainingLoadouts.applyPersistentAttackMap(state: AttackMap, playerState: unknown): AttackMap
	if state.Temporary then
		return state
	end
	if type(playerState) ~= "table" then
		return state
	end
	local payload = playerState :: { [unknown]: unknown }
	local loadout = payload.Loadout
	if type(loadout) ~= "table" then
		return state
	end
	return { Loadout = persistentHands(loadout :: { [unknown]: unknown }), Temporary = false }
end

-- A valid Loadout event replaces the map and sets the latch from Temporary.
-- Anything else, including a non-Loadout CombatEvent, returns the same state.
function TrainingLoadouts.applyLoadoutEvent(state: AttackMap, event: unknown): AttackMap
	local read = TrainingLoadouts.readLoadoutEvent(event)
	if read == nil then
		return state
	end
	return { Loadout = read.Hands, Temporary = read.Temporary }
end

local bootErrors = TrainingLoadouts.compatibilityErrors(Definitions.get())
if #bootErrors > 0 then
	error(`[TrainingLoadouts] {table.concat(bootErrors, "; ")}`)
end

return TrainingLoadouts
