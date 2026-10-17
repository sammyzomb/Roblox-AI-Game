--!strict
-- Level / milestone unlock checks. Pure module (no Roblox APIs).
--
-- A gate is { Level = number?, Milestones = { string }? }. Every field that is
-- present must be satisfied. A missing gate means "always unlocked".
-- Milestones are free-form ids granted by gameplay ("boss_forest_warden",
-- "arena_bronze") and stored in PlayerData.Milestones.

export type Gate = {
	Level: number?,
	Milestones: { string }?,
}

export type Profile = {
	Level: number,
	Milestones: { [string]: boolean },
}

-- Anything with an optional Unlock gate (weapons, armor, consumables, spells).
export type Gated = { Id: string, Unlock: Gate? }

local ProgressionGates = {}

-- Returns true, or false plus a reason the client can display.
function ProgressionGates.check(gate: Gate?, profile: Profile): (boolean, string?)
	if gate == nil then
		return true, nil
	end
	if gate.Level and profile.Level < gate.Level then
		return false, `Requires level {gate.Level}`
	end
	if gate.Milestones then
		for _, milestone in gate.Milestones do
			if not profile.Milestones[milestone] then
				return false, `Requires milestone {milestone}`
			end
		end
	end
	return true, nil
end

-- Ids of every entry in `defs` that `profile` has unlocked, sorted.
function ProgressionGates.unlocked(defs: { [string]: Gated }, profile: Profile): { string }
	local ids = {}
	for id, def in defs do
		if ProgressionGates.check(def.Unlock, profile) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- Ids whose level requirement is exactly `level` (for "new unlocks!" UI on level up).
-- Milestone-only gates are not included.
function ProgressionGates.newAtLevel(defs: { [string]: Gated }, level: number): { string }
	local ids = {}
	for id, def in defs do
		if def.Unlock and def.Unlock.Level == level then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

return table.freeze(ProgressionGates)
